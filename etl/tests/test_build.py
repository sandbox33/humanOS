"""End-to-end build on synthetic FDC/OFF fixtures (offline)."""
import hashlib
import sqlite3

import pytest

from etl.build_reference_db import MappingError, build

from .conftest import FIXTURE_SYNONYMS


def q(path, sql, *args):
    con = sqlite3.connect(path)
    try:
        return con.execute(sql, args).fetchall()
    finally:
        con.close()


def test_schema_version_and_sha256(fixture_db):
    path, report = fixture_db
    assert q(path, "PRAGMA user_version")[0][0] == 1
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    sha_file = path.with_name("reference.sqlite.sha256").read_text(encoding="utf-8")
    assert sha_file == f"{digest}  reference.sqlite\n"
    tables = {r[0] for r in q(path, "SELECT name FROM sqlite_master WHERE type IN ('table')")}
    for table in ("sources", "foods", "food_names", "nutrients", "food_nutrients", "food_properties",
                  "products", "recipes", "recipe_items", "exercises", "exercise_templates"):
        assert table in tables
    assert report.counts["skipped_without_energy"] == 1


def test_missing_values_stay_null(fixture_db):
    path, _ = fixture_db
    # Honey fixture has no starch row: no food_nutrients entry, never a zero.
    rows = q(path, "SELECT amount_per_100g FROM food_nutrients WHERE food_id = 1004 AND nutrient_id = 1009")
    assert rows == []


def test_plantain_sugars_are_null_unless_analytical(fixture_db):
    path, report = fixture_db
    green = q(path, "SELECT nutrient_id FROM food_nutrients WHERE food_id = 1002")
    assert (2000,) not in green and (1009,) not in green
    banana = q(path, "SELECT nutrient_id FROM food_nutrients WHERE food_id = 1001")
    assert (2000,) in banana and (1009,) in banana
    assert any("NULL: no analítico" in line for line in report.ripeness_audit)
    ripeness = dict(q(path, "SELECT id, ripeness FROM foods WHERE id IN (1001, 1002, 1003)"))
    assert ripeness == {1001: "ripe", 1002: "green", 1003: "ripe"}


def test_taxonomy_in_the_database(fixture_db):
    path, _ = fixture_db
    md = dict(q(path, "SELECT food_id, macro_dominant FROM food_properties"))
    assert md[1004] == "carb_sugar"  # honey
    assert md[1005] == "fiber"  # chia
    assert md[1010] == "protein"
    assert md[1002] == "mixed"  # sugars/starch unknown
    heme = dict(q(path, "SELECT food_id, iron_heme FROM food_properties"))
    assert heme[1010] == 1 and heme[1006] == 0
    inhibitors = dict(q(path, "SELECT food_id, inhibits_nonheme_iron FROM food_properties"))
    assert inhibitors[1011] == 1 and inhibitors[1006] == 0


def test_gi_only_from_the_csv(fixture_db):
    path, _ = fixture_db
    gi = dict(q(path, "SELECT food_id, gi FROM food_properties WHERE gi IS NOT NULL"))
    assert gi == {1001: 51.0}
    ref = q(path, "SELECT gi_ref, gl_per_100g FROM food_properties WHERE food_id = 1001")[0]
    assert "Banana, raw" in ref[0]
    assert ref[1] == pytest.approx(51 * (22.8 - 2.6) / 100)


def test_spanish_names_and_english_are_searchable(fixture_db):
    path, _ = fixture_db
    names = {r[0] for r in q(path, "SELECT name FROM food_names WHERE food_id = 1001")}
    assert {"Cambur / guineo (banano)", "cambur", "guineo", "Bananas, raw"} <= names
    translated = q(path, "SELECT canonical_name_es FROM foods WHERE id = 1007")[0][0]
    assert translated.lower().startswith("kiwi")


def test_products_and_nova_sources(fixture_db):
    path, _ = fixture_db
    rows = {r[0]: (r[1], r[2]) for r in q(path, "SELECT barcode, nova, nova_source FROM products")}
    assert rows["7861000000017"] == (4, "rules")  # hydrogenated oil
    assert rows["7861000000024"] == (1, "rules")  # maní 100%
    assert rows["7861000000031"] == (4, "off")
    found = q(path, "SELECT barcode FROM products_fts WHERE products_fts MATCH ?", '"mani"*')
    assert ("7861000000024",) in found


def test_arepa_recipe_uses_a_scanned_flour(fixture_db):
    path, _ = fixture_db
    recipe = q(path, "SELECT id, name_es FROM recipes")
    assert len(recipe) == 1 and recipe[0][1].startswith("Arepa")
    items = q(path, "SELECT food_id, barcode, grams FROM recipe_items ORDER BY grams DESC")
    assert (None, "7590000000001", 120.0) in items
    assert (1008, None, 150.0) in items and (1009, None, 1.5) in items


def test_recipe_is_skipped_without_flour(fixture_inputs, tmp_path):
    fixture_inputs.products = [p for p in fixture_inputs.products if "Harina" not in p.name]
    report = build(fixture_inputs, tmp_path / "ref.sqlite")
    assert report.counts["recipes"] == 0
    assert any("arepa" in w for w in report.warnings)


def test_heavy_duty_templates(fixture_db):
    path, _ = fixture_db
    a = [r[0] for r in q(path, "SELECT e.name_es FROM exercise_templates t JOIN exercises e ON e.id = t.exercise_id "
                               "WHERE t.template = 'A' ORDER BY t.position")]
    assert a == ["Prensa de piernas", "Jalón supino agarre cerrado", "Fondos asistidos en máquina",
                 "Gemelos de pie (pausa 2 s)"]
    b = [r[0] for r in q(path, "SELECT e.name_es FROM exercise_templates t JOIN exercises e ON e.id = t.exercise_id "
                               "WHERE t.template = 'B' ORDER BY t.position")]
    assert b[0] == "Peso muerto rumano"
    baseline = q(path, "SELECT exercise_id FROM exercise_templates WHERE template = 'BASELINE' ORDER BY position")
    assert [r[0] for r in baseline] == [1, 2, 3, 4]
    rdl = q(path, "SELECT failure_safe, rep_min, rep_max FROM exercises WHERE name_es = 'Peso muerto rumano'")[0]
    assert rdl == (0, 6, 8)
    subs = q(path, "SELECT count(*) FROM exercises WHERE substitute_id IS NOT NULL")[0][0]
    assert subs == 16


def test_sources_carry_licences(fixture_db):
    path, _ = fixture_db
    sources = {r[0]: r[1] for r in q(path, "SELECT code, license FROM sources")}
    assert "CC0" in sources["FDC_SR"]
    assert "ODbL" in sources["OFF"]


def test_strict_mapping_reports_close_matches(fixture_inputs, tmp_path):
    fixture_inputs.synonyms = FIXTURE_SYNONYMS + [
        {"fdc_description": "Bananas, rawx", "name": "x", "region": "GEN", "is_primary": "1", "ripeness": ""}
    ]
    with pytest.raises(MappingError) as error:
        build(fixture_inputs, tmp_path / "ref.sqlite")
    assert "Bananas, raw" in str(error.value)
