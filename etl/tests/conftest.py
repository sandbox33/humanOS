"""Shared fixtures.

Synthetic FDC-format archives keep the unit tests offline. Their numbers are
test fixtures, not reference data. Tests marked ``real_data`` download the
real USDA files and run in CI; set ``HUMANOS_OFFLINE=1`` to skip them where
the network cannot reach fdc.nal.usda.gov.
"""
from __future__ import annotations

import csv
import io
import os
import zipfile
from pathlib import Path

import pytest

from etl.build_reference_db import BuildInputs, build, read_csv, DATA_DIR
from etl.derive.names_es import Glossary
from etl.sources import fdc, off

ROOT = Path(__file__).resolve().parents[2]

# (fdc_id, description, category, {nutrient_id: (amount, derivation_id)})
FIXTURE_FOODS = [
    (1001, "Bananas, raw", "Fruits and Fruit Juices",
     {1008: (89, "1"), 1003: (1.1, "1"), 1004: (0.3, "1"), 1005: (22.8, "1"), 1079: (2.6, "1"),
      2000: (12.2, "1"), 1009: (5.4, "1"), 1089: (0.3, "1"), 1162: (8.7, "1")}),
    (1002, "Plantains, green, raw", "Fruits and Fruit Juices",
     {1008: (120, "1"), 1003: (1.2, "1"), 1004: (0.4, "1"), 1005: (31.0, "1"), 1079: (2.2, "1"),
      2000: (15.0, "2"), 1009: (10.0, "2")}),
    (1003, "Plantains, yellow, raw", "Fruits and Fruit Juices",
     {1008: (125, "1"), 1003: (1.3, "1"), 1004: (0.4, "1"), 1005: (32.0, "1"), 1079: (2.3, "1"),
      2000: (16.0, "2")}),
    (1004, "Honey", "Sweets",
     {1008: (300, "1"), 1003: (0.3, "1"), 1004: (0.0, "1"), 1005: (82.0, "1"), 1079: (0.2, "1"),
      2000: (82.1, "1")}),
    (1005, "Seeds, chia seeds, dried", "Nut and Seed Products",
     {1008: (480, "1"), 1003: (16.5, "1"), 1004: (30.0, "1"), 1005: (42.0, "1"), 1079: (34.4, "1")}),
    (1006, "Beans, black, mature seeds, raw", "Legumes and Legume Products",
     {1008: (340, "1"), 1003: (21.6, "1"), 1004: (1.4, "1"), 1005: (62.0, "1"), 1079: (15.5, "1"),
      2000: (2.1, "1"), 1089: (5.0, "1")}),
    (1007, "Kiwifruit, green, raw", "Fruits and Fruit Juices",
     {1008: (61, "1"), 1003: (1.1, "1"), 1004: (0.5, "1"), 1005: (14.7, "1"), 1079: (3.0, "1"),
      2000: (9.0, "1"), 1162: (92.7, "1")}),
    (1008, "Beverages, water, tap, drinking", "Beverages", {1008: (0, "1"), 1093: (4, "1")}),
    (1009, "Salt, table", "Spices and Herbs", {1008: (0, "1"), 1093: (38758, "1")}),
    (1010, "Chicken, broilers or fryers, breast, meat only, raw", "Poultry Products",
     {1008: (120, "1"), 1003: (22.5, "1"), 1004: (2.6, "1"), 1005: (0.0, "1"), 1089: (0.4, "1")}),
    (1011, "Beverages, coffee, brewed, prepared with tap water", "Beverages",
     {1008: (1, "1"), 1003: (0.1, "1"), 1004: (0.0, "1"), 1005: (0.0, "1")}),
    (1012, "Mystery food without energy", "Sweets", {1003: (1.0, "1")}),
]
FIXTURE_NUTRIENTS = [
    (1003, "Protein", "G"), (1004, "Total lipid (fat)", "G"), (1005, "Carbohydrate, by difference", "G"),
    (1008, "Energy", "KCAL"), (1009, "Starch", "G"), (1079, "Fiber, total dietary", "G"),
    (1089, "Iron, Fe", "MG"), (1093, "Sodium, Na", "MG"), (1162, "Vitamin C, total ascorbic acid", "MG"),
    (2000, "Sugars, total including NLEA", "G"),
]


def _csv_bytes(header: list[str], rows: list[list[object]]) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer, quoting=csv.QUOTE_ALL)
    writer.writerow(header)
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def make_fdc_zip(path: Path, foods=FIXTURE_FOODS, data_type: str = "sr_legacy_food") -> Path:
    categories = sorted({f[2] for f in foods})
    category_ids = {name: i + 1 for i, name in enumerate(categories)}
    folder = "FoodData_Central_sr_legacy_food_csv_2018-04/"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr(folder + "food_category.csv", _csv_bytes(
            ["id", "code", "description"], [[i, f"{i:04d}", n] for n, i in category_ids.items()]))
        archive.writestr(folder + "food.csv", _csv_bytes(
            ["fdc_id", "data_type", "description", "food_category_id", "publication_date"],
            [[f[0], data_type, f[1], category_ids[f[2]], "2019-04-01"] for f in foods]))
        archive.writestr(folder + "sr_legacy_food.csv", _csv_bytes(
            ["fdc_id", "NDB_number"], [[f[0], 90000 + i] for i, f in enumerate(foods)]))
        archive.writestr(folder + "nutrient.csv", _csv_bytes(
            ["id", "name", "unit_name", "nutrient_nbr", "rank"],
            [[nid, name, unit, "", ""] for nid, name, unit in FIXTURE_NUTRIENTS]))
        archive.writestr(folder + "food_nutrient_derivation.csv", _csv_bytes(
            ["id", "code", "description", "source_id"],
            [["1", "A", "Analytical data", "1"], ["2", "BFZN", "Based on another form of the food or similar food; Concentration adjustment; Non-fat solids; Retention factors not used", "1"]]))
        rows = []
        row_id = 1
        for fdc_id, _desc, _cat, values in foods:
            for nid, (amount, derivation) in values.items():
                rows.append([row_id, fdc_id, nid, amount, 1, derivation, "", "", "", "", ""])
                row_id += 1
        archive.writestr(folder + "food_nutrient.csv", _csv_bytes(
            ["id", "fdc_id", "nutrient_id", "amount", "data_points", "derivation_id", "min", "max",
             "median", "footnote", "min_year_acquired"], rows))
    return path


OFF_HEADER = [
    "code", "url", "product_name", "brands", "countries_tags", "nova_group", "nutriscore_grade",
    "additives_tags", "ingredients_text", "unique_scans_n", "energy-kcal_100g", "proteins_100g",
    "fat_100g", "carbohydrates_100g", "sugars_100g", "fiber_100g", "sodium_100g",
]


def off_line(**values: str) -> str:
    return "\t".join(values.get(column, "") for column in OFF_HEADER) + "\n"


FIXTURE_OFF_LINES = [
    "\t".join(OFF_HEADER) + "\n",
    off_line(code="7590000000001", product_name="Harina de maíz blanco precocida", brands="Marca A",
             countries_tags="en:venezuela,en:colombia", ingredients_text="Maíz blanco desgerminado, niacina, hierro",
             unique_scans_n="50", **{"energy-kcal_100g": "350", "proteins_100g": "7", "fat_100g": "1.5",
                                     "carbohydrates_100g": "78"}),
    off_line(code="7861000000017", product_name="Mantequilla de maní cremosa", brands="Marca B",
             countries_tags="en:ecuador", ingredients_text="maní, aceite vegetal hidrogenado, azúcar, sal",
             **{"energy-kcal_100g": "600", "proteins_100g": "24", "fat_100g": "50", "sodium_100g": "0.4"}),
    off_line(code="7861000000024", product_name="Maní natural", brands="Marca C", countries_tags="en:ecuador",
             ingredients_text="maní 100%", **{"energy-kcal_100g": "570", "proteins_100g": "26"}),
    off_line(code="7861000000031", product_name="Galletas", countries_tags="en:ecuador", nova_group="4",
             ingredients_text="harina de trigo, azúcar", **{"energy-kcal_100g": "480"}),
    off_line(code="3000000000001", product_name="Producto francés", countries_tags="en:france",
             **{"energy-kcal_100g": "100"}),
    off_line(code="7861000000048", product_name="Sin nutrición", countries_tags="en:ecuador"),
    off_line(code="7861000000055", product_name="Dato imposible", countries_tags="en:ecuador",
             **{"energy-kcal_100g": "5000", "proteins_100g": "10"}),
]

FIXTURE_SYNONYMS = [
    {"fdc_description": "Bananas, raw", "name": "Cambur / guineo (banano)", "region": "GEN", "is_primary": "1", "ripeness": "ripe"},
    {"fdc_description": "Bananas, raw", "name": "cambur", "region": "VE", "is_primary": "0", "ripeness": ""},
    {"fdc_description": "Bananas, raw", "name": "guineo", "region": "EC", "is_primary": "0", "ripeness": ""},
    {"fdc_description": "Plantains, green, raw", "name": "Plátano verde, crudo", "region": "GEN", "is_primary": "1", "ripeness": "green"},
    {"fdc_description": "Plantains, yellow, raw", "name": "Plátano maduro, crudo", "region": "GEN", "is_primary": "1", "ripeness": "ripe"},
    {"fdc_description": "Beans, black, mature seeds, raw", "name": "Caraota negra / fréjol negro, cruda", "region": "GEN", "is_primary": "1", "ripeness": ""},
    {"fdc_description": "Beans, black, mature seeds, raw", "name": "caraota negra", "region": "VE", "is_primary": "0", "ripeness": ""},
    {"fdc_description": "Honey", "name": "Miel de abeja", "region": "GEN", "is_primary": "1", "ripeness": ""},
]
FIXTURE_GI = [
    {"fdc_description": "Bananas, raw", "gi": "51", "gi_sem": "3", "food_in_source": "Banana, raw", "reference": "Tabla de prueba"},
]


@pytest.fixture
def fixture_inputs(tmp_path: Path) -> BuildInputs:
    zip_path = make_fdc_zip(tmp_path / "FoodData_Central_sr_legacy_food_csv_2018-04.zip")
    sr = fdc.load_zip(zip_path, keep_type=fdc.SR_LEGACY_TYPE, label="FDC_SR", url="file://fixture")
    products = list(off.parse_lines(FIXTURE_OFF_LINES))
    return BuildInputs(
        sr=sr,
        products=products,
        off_version="2026-10-01",
        synonyms=FIXTURE_SYNONYMS,
        gi_rows=FIXTURE_GI,
        recipes=read_csv(DATA_DIR / "recipes.csv"),
        exercises=read_csv(DATA_DIR / "exercises.csv"),
        glossary=Glossary.load(),
    )


@pytest.fixture
def fixture_db(tmp_path: Path, fixture_inputs: BuildInputs):
    out = tmp_path / "reference.sqlite"
    report = build(fixture_inputs, out)
    return out, report


def offline() -> bool:
    return os.environ.get("HUMANOS_OFFLINE") == "1"
