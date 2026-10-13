"""Checks against the real USDA SR Legacy data (downloaded; runs in CI)."""
import sqlite3
from pathlib import Path

import pytest

from etl.build_reference_db import DATA_DIR, BuildInputs, build, read_csv
from etl.derive.names_es import Glossary
from etl.sources import fdc

from .conftest import ROOT, offline

pytestmark = pytest.mark.skipif(offline(), reason="HUMANOS_OFFLINE=1: sin acceso a fdc.nal.usda.gov")
CACHE = ROOT / "etl" / ".cache"


@pytest.fixture(scope="module")
def real_db(tmp_path_factory) -> Path:
    sr = fdc.load_sr_legacy(CACHE)
    inputs = BuildInputs(
        sr=sr,
        foundation=None,
        synonyms=read_csv(DATA_DIR / "synonyms_es.csv"),
        gi_rows=read_csv(DATA_DIR / "gi_values.csv"),
        recipes=read_csv(DATA_DIR / "recipes.csv"),
        exercises=read_csv(DATA_DIR / "exercises.csv"),
        glossary=Glossary.load(),
    )
    out = tmp_path_factory.mktemp("real") / "reference.sqlite"
    report = build(inputs, out)
    for line in report.ripeness_audit:
        print("[madurez]", line)
    return out


def value(db: Path, description: str, nutrient_id: int) -> float | None:
    con = sqlite3.connect(db)
    try:
        row = con.execute(
            "SELECT n.amount_per_100g FROM foods f JOIN food_nutrients n ON n.food_id = f.id "
            "WHERE f.canonical_name_en = ? AND n.nutrient_id = ?",
            (description, nutrient_id),
        ).fetchone()
        return None if row is None else row[0]
    finally:
        con.close()


def test_kiwi_energy(real_db):
    assert value(real_db, "Kiwifruit, green, raw", 1008) == pytest.approx(61, rel=0.02)


def test_chia_fiber(real_db):
    assert value(real_db, "Seeds, chia seeds, dried", 1079) == pytest.approx(34.4, rel=0.02)


def test_honey_sugars(real_db):
    assert value(real_db, "Honey", 2000) == pytest.approx(82.1, rel=0.02)


def test_honey_and_chia_taxonomy(real_db):
    con = sqlite3.connect(real_db)
    rows = dict(con.execute(
        "SELECT f.canonical_name_en, p.macro_dominant FROM foods f JOIN food_properties p ON p.food_id = f.id "
        "WHERE f.canonical_name_en IN ('Honey', 'Seeds, chia seeds, dried')").fetchall())
    con.close()
    assert rows == {"Honey": "carb_sugar", "Seeds, chia seeds, dried": "fiber"}


def test_banana_green_and_ripe_plantain_are_distinct(real_db):
    con = sqlite3.connect(real_db)
    rows = con.execute(
        "SELECT canonical_name_en, id, ripeness FROM foods WHERE canonical_name_en IN "
        "('Bananas, raw', 'Plantains, green, raw', 'Plantains, yellow, raw')").fetchall()
    con.close()
    assert len({r[1] for r in rows}) == 3
    assert {r[0]: r[2] for r in rows}["Plantains, green, raw"] == "green"


def test_search_acceptance(real_db):
    con = sqlite3.connect(real_db)

    def search(term):
        return {r[0] for r in con.execute(
            "SELECT DISTINCT f.canonical_name_en FROM food_names_fts JOIN foods f ON f.id = food_names_fts.food_id "
            "WHERE food_names_fts MATCH ?", (f'"{term}"*',))}

    platano = search("platano")
    assert any(name.startswith("Plantains") for name in platano)
    assert "Beans, black, mature seeds, raw" in search("caraota")
    cambur = search("cambur")
    assert "Bananas, raw" in cambur
    assert not any(name.startswith("Plantains") for name in cambur)
    con.close()


def test_every_gi_row_is_applied(real_db):
    con = sqlite3.connect(real_db)
    count = con.execute("SELECT count(*) FROM food_properties WHERE gi IS NOT NULL").fetchone()[0]
    con.close()
    assert count == len(read_csv(DATA_DIR / "gi_values.csv"))
