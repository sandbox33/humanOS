"""Curated Spanish names and the search acceptance criteria."""
import sqlite3
from collections import Counter

from etl.build_reference_db import DATA_DIR, read_csv
from etl.derive.names_es import normalize

ROWS = read_csv(DATA_DIR / "synonyms_es.csv")
BANANA = "Bananas, raw"
GREEN = "Plantains, green, raw"
RIPE = "Plantains, yellow, raw"
BLACK_BEANS = "Beans, black, mature seeds, raw"


def descriptions_for(name: str) -> set[str]:
    return {r["fdc_description"] for r in ROWS if normalize(r["name"]) == normalize(name)}


def test_every_food_has_exactly_one_primary_name():
    primaries = Counter(r["fdc_description"] for r in ROWS if r["is_primary"] == "1")
    foods = {r["fdc_description"] for r in ROWS}
    assert all(primaries[f] == 1 for f in foods), [f for f in foods if primaries[f] != 1]


def test_regions_and_ripeness_values():
    assert {r["region"] for r in ROWS} <= {"EC", "VE", "CO", "GEN"}
    assert {r["ripeness"] for r in ROWS} <= {"", "green", "ripe", "na"}


def test_banana_and_plantains_are_three_distinct_foods():
    assert len({BANANA, GREEN, RIPE}) == 3
    ripeness = {r["fdc_description"]: r["ripeness"] for r in ROWS if r["is_primary"] == "1"}
    assert ripeness[GREEN] == "green"
    assert ripeness[RIPE] == "ripe"


def test_regional_synonyms_point_to_the_right_food():
    assert descriptions_for("cambur") == {BANANA}
    assert descriptions_for("guineo") == {BANANA}
    assert descriptions_for("caraota negra") == {BLACK_BEANS}
    assert descriptions_for("fréjol negro") == {BLACK_BEANS}
    assert all("Plantains" not in d for d in descriptions_for("cambur"))


def fts(db: sqlite3.Connection, query: str) -> list[str]:
    return [
        row[0]
        for row in db.execute(
            "SELECT DISTINCT f.canonical_name_en FROM food_names_fts "
            "JOIN foods f ON f.id = food_names_fts.food_id WHERE food_names_fts MATCH ?",
            (query,),
        )
    ]


def test_search_acceptance_on_fixture_db(fixture_db):
    path, _ = fixture_db
    db = sqlite3.connect(path)
    plantains = fts(db, '"platano"*')
    assert "Plantains, green, raw" in plantains and "Plantains, yellow, raw" in plantains
    cambur = fts(db, '"cambur"*')
    assert cambur == ["Bananas, raw"]
    assert fts(db, '"caraota"*') == ["Beans, black, mature seeds, raw"]
    db.close()
