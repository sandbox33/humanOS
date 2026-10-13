"""Builds ``reference.sqlite``: the read-only food and exercise database.

Usage (from the repository root)::

    python -m etl.build_reference_db --out assets/db/reference.sqlite

Sources: USDA FoodData Central SR Legacy + Foundation Foods (CC0), Open
Food Facts filtered to EC/VE/CO (ODbL), optional local tables in
``etl/data/local/`` and the curated CSVs in ``etl/data/``. Nothing is
invented: a value missing in the source is NULL in the database.

The build is strict by default: a curated row (synonym, GI value, recipe
item) that does not match a source food stops the build and prints the
closest descriptions, so mistakes surface in CI instead of shipping.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import difflib
import hashlib
import json
import os
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    __package__ = "etl"

from .derive import energy_density, nova_rules, nrf93, taxonomy  # noqa: E402
from .derive.names_es import Glossary, normalize, nutrient_name_es, unit_es  # noqa: E402
from .sources import ecuador_tables, fdc, off  # noqa: E402
from .sources.http import download  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(__file__).resolve().parent / "data"
USER_VERSION = 1
LOCAL_ID_BASE = 900_000_000

DDL = """
CREATE TABLE sources(id INTEGER PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
  license TEXT NOT NULL, url TEXT NOT NULL, version TEXT NOT NULL);
CREATE TABLE foods(id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL REFERENCES sources(id), source_ref TEXT NOT NULL,
  canonical_name_es TEXT NOT NULL, canonical_name_en TEXT, food_group TEXT NOT NULL,
  state TEXT CHECK(state IN('raw','cooked','prepared')),
  ripeness TEXT NOT NULL DEFAULT 'na' CHECK(ripeness IN('green','ripe','na')),
  proxy_of INTEGER REFERENCES foods(id), parent_id INTEGER REFERENCES foods(id));
CREATE TABLE food_names(food_id INTEGER NOT NULL REFERENCES foods(id), name TEXT NOT NULL,
  region TEXT NOT NULL CHECK(region IN('EC','VE','CO','GEN')), is_primary INTEGER NOT NULL DEFAULT 0);
CREATE INDEX food_names_food ON food_names(food_id);
CREATE VIRTUAL TABLE food_names_fts USING fts5(name, food_id UNINDEXED, tokenize="unicode61 remove_diacritics 2");
CREATE TABLE nutrients(id INTEGER PRIMARY KEY, fdc_nutrient_id INTEGER UNIQUE, name_es TEXT NOT NULL,
  unit TEXT NOT NULL, category TEXT NOT NULL);
CREATE TABLE food_nutrients(food_id INTEGER NOT NULL REFERENCES foods(id), nutrient_id INTEGER NOT NULL REFERENCES nutrients(id),
  amount_per_100g REAL NOT NULL, PRIMARY KEY(food_id, nutrient_id)) WITHOUT ROWID;
CREATE TABLE food_properties(food_id INTEGER PRIMARY KEY REFERENCES foods(id),
  macro_dominant TEXT NOT NULL CHECK(macro_dominant IN('carb_sugar','carb_starch','fiber','protein','fat','mixed')),
  gi REAL, gi_ref TEXT, gl_per_100g REAL, resistant_starch_note TEXT, diaas REAL, diaas_ref TEXT, limiting_aa TEXT,
  leucine_g_100g REAL, nova INTEGER CHECK(nova BETWEEN 1 AND 4),
  nova_source TEXT CHECK(nova_source IN('off','rules','ml','manual')),
  energy_density_kcal_g REAL NOT NULL, gastric_heuristic REAL, antinutrient_note TEXT, allergens TEXT,
  nrf93_per_100kcal REAL, iron_heme INTEGER, inhibits_nonheme_iron INTEGER NOT NULL DEFAULT 0,
  confidence TEXT NOT NULL DEFAULT 'media' CHECK(confidence IN('alta','media','baja')));
CREATE TABLE products(barcode TEXT PRIMARY KEY, name TEXT NOT NULL, brand TEXT, countries TEXT, nova INTEGER, nova_source TEXT,
  nutriscore TEXT, additives TEXT, ingredients_text TEXT, kcal_100g REAL, protein_100g REAL, fat_100g REAL, carb_100g REAL,
  sugars_100g REAL, fiber_100g REAL, sodium_mg_100g REAL, mapped_food_id INTEGER REFERENCES foods(id));
CREATE VIRTUAL TABLE products_fts USING fts5(name, brand, barcode UNINDEXED, tokenize="unicode61 remove_diacritics 2");
CREATE TABLE recipes(id INTEGER PRIMARY KEY, name_es TEXT NOT NULL);
CREATE TABLE recipe_items(recipe_id INTEGER NOT NULL REFERENCES recipes(id), food_id INTEGER REFERENCES foods(id),
  barcode TEXT, grams REAL NOT NULL CHECK(grams > 0));
CREATE INDEX recipe_items_recipe ON recipe_items(recipe_id);
CREATE TABLE exercises(id INTEGER PRIMARY KEY, name_es TEXT NOT NULL, equipment TEXT NOT NULL, muscles TEXT NOT NULL,
  failure_safe INTEGER NOT NULL, rep_min INTEGER NOT NULL, rep_max INTEGER NOT NULL, min_increment_kg REAL NOT NULL,
  tempo TEXT NOT NULL DEFAULT '4-1-X-2', substitute_id INTEGER REFERENCES exercises(id), cue_es TEXT NOT NULL);
CREATE TABLE exercise_templates(template TEXT NOT NULL CHECK(template IN('A','B','BASELINE')),
  position INTEGER NOT NULL, exercise_id INTEGER NOT NULL REFERENCES exercises(id), PRIMARY KEY(template, position));
"""

# Nutrients that are kept only when analytical for ripeness-tracked foods
# (banana, green plantain, ripe plantain): sugars, individual sugars, starch.
ANALYTICAL_ONLY = {2000, 1063, 1010, 1011, 1012, 1013, 1014, 1075, 1009}

_COOKED_WORDS = (
    "cooked", "boiled", "roasted", "baked", "fried", "grilled", "broiled",
    "braised", "stewed", "steamed", "microwaved", "simmered", "toasted",
)


class MappingError(RuntimeError):
    """A curated row does not match the source data."""


@dataclass
class BuildInputs:
    sr: fdc.FdcDataset
    foundation: fdc.FdcDataset | None = None
    products: list[off.OffProduct] = field(default_factory=list)
    off_version: str | None = None
    local_foods: list[ecuador_tables.LocalFood] = field(default_factory=list)
    synonyms: list[dict[str, str]] = field(default_factory=list)
    gi_rows: list[dict[str, str]] = field(default_factory=list)
    recipes: list[dict[str, str]] = field(default_factory=list)
    exercises: list[dict[str, str]] = field(default_factory=list)
    glossary: Glossary | None = None


@dataclass
class BuildReport:
    counts: dict[str, int] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    ripeness_audit: list[str] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(self.__dict__, ensure_ascii=False, indent=2)


def read_csv(path: Path) -> list[dict[str, str]]:
    with open(path, encoding="utf-8", newline="") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def state_of(description: str) -> str | None:
    text = description.lower()
    if ", raw" in text or text.endswith(" raw") or text.startswith("raw"):
        return "raw"
    if any(word in text for word in _COOKED_WORDS):
        return "cooked"
    if "prepared" in text:
        return "prepared"
    return None


def _closest(description: str, candidates: list[str]) -> str:
    """Hints for a description that did not match: fuzzy matches plus
    descriptions containing all of its significant words."""
    fuzzy = difflib.get_close_matches(description, candidates, n=5, cutoff=0.55)
    words = [w for w in re.findall(r"[a-z]+", description.lower()) if len(w) >= 3]
    containing = sorted(
        (c for c in candidates if all(w in c.lower() for w in words[:4])), key=len
    )[:5]
    hints = list(dict.fromkeys([*containing, *fuzzy]))
    return "; ".join(hints) if hints else "(sin coincidencias cercanas)"


class _Resolver:
    """Maps exact FDC descriptions to food ids (SR first, then Foundation)."""

    def __init__(self, datasets: list[fdc.FdcDataset]):
        self._by_desc: dict[str, int] = {}
        self._by_norm: dict[str, int] = {}
        for dataset in datasets:
            for fdc_id, food in dataset.foods.items():
                self._by_desc.setdefault(food.description, fdc_id)
                self._by_norm.setdefault(normalize(food.description), fdc_id)
        self.descriptions = sorted(self._by_desc)

    def resolve(self, description: str) -> int | None:
        found = self._by_desc.get(description)
        if found is None:
            found = self._by_norm.get(normalize(description))
        return found


def _insert_sources(con: sqlite3.Connection, inputs: BuildInputs) -> dict[str, int]:
    rows = [
        (
            "FDC_SR",
            "USDA FoodData Central — SR Legacy",
            "CC0 1.0 (dominio público)",
            "https://fdc.nal.usda.gov/",
            inputs.sr.version,
        )
    ]
    if inputs.foundation is not None:
        rows.append(
            (
                "FDC_FOUNDATION",
                "USDA FoodData Central — Foundation Foods",
                "CC0 1.0 (dominio público)",
                "https://fdc.nal.usda.gov/",
                inputs.foundation.version,
            )
        )
    if inputs.products:
        rows.append(
            (
                "OFF",
                "Open Food Facts (Ecuador, Venezuela, Colombia)",
                "ODbL 1.0 — © colaboradores de Open Food Facts",
                "https://world.openfoodfacts.org/",
                inputs.off_version or dt.date.today().isoformat(),
            )
        )
    if inputs.gi_rows:
        rows.append(
            (
                "GI_TABLES",
                "International tables of glycemic index and glycemic load values (valores citados uno a uno)",
                "Cita bibliográfica por valor",
                "https://doi.org/10.2337/dc08-1239",
                "2008",
            )
        )
    rows.append(
        (
            "HUMANOS",
            "HumanOS — recetas y ejercicios curados",
            "Datos propios del proyecto",
            "https://github.com/sandbox33/humanOS",
            "3.0",
        )
    )
    seen_local: set[str] = set()
    for food in inputs.local_foods:
        code = f"LOCAL_{food.file_code}"
        if code in seen_local:
            continue
        seen_local.add(code)
        rows.append((code, food.source_name, food.source_license, food.source_url or "local", food.source_version))
    ids: dict[str, int] = {}
    for code, name, license_text, url, version in rows:
        cursor = con.execute(
            "INSERT INTO sources(code, name, license, url, version) VALUES (?,?,?,?,?)",
            (code, name, license_text, url, version),
        )
        ids[code] = int(cursor.lastrowid)
    return ids


def _filtered_amounts(
    food: fdc.FdcFood,
    amounts: dict[int, fdc.FdcAmount],
    ripeness: str,
    report: BuildReport,
) -> dict[int, float]:
    values: dict[int, float] = {}
    for nutrient_id, amount in amounts.items():
        if ripeness != "na" and nutrient_id in ANALYTICAL_ONLY:
            kept = amount.analytical
            report.ripeness_audit.append(
                f"{food.description} | nutriente {nutrient_id} = {amount.amount} | "
                f"derivación {amount.derivation_code or '?'} ({amount.derivation_description or 'sin descripción'}) | "
                f"{'se conserva' if kept else 'NULL: no analítico'}"
            )
            if not kept:
                continue
        values[nutrient_id] = amount.amount
    return values


def _properties(
    description: str,
    category: str | None,
    nutrients: dict[int, float],
    energy: float,
    *,
    proxy: bool,
) -> dict[str, object]:
    macros = taxonomy.macros(nutrients)
    index, missing = nrf93.nrf93_per_100kcal(nutrients, energy)
    nova = nova_rules.classify_fdc_food(description, category)
    return {
        "macro_dominant": taxonomy.macro_dominant(**macros),
        "resistant_starch_note": taxonomy.resistant_starch_note(description),
        "limiting_aa": taxonomy.limiting_amino_acid(nutrients),
        "leucine_g_100g": nutrients.get(taxonomy.LEUCINE),
        "nova": nova,
        "nova_source": "rules" if nova is not None else None,
        "energy_density_kcal_g": energy_density.energy_density_kcal_g(energy),
        "gastric_heuristic": taxonomy.fat_energy_share(nutrients, energy),
        "antinutrient_note": taxonomy.antinutrient_note(description),
        "allergens": taxonomy.allergens(description),
        "nrf93_per_100kcal": index,
        "iron_heme": taxonomy.iron_heme(category),
        "inhibits_nonheme_iron": taxonomy.inhibits_nonheme_iron(description),
        "confidence": taxonomy.confidence(nutrients, nrf_missing=len(missing), proxy=proxy),
    }


def _insert_food(
    con: sqlite3.Connection,
    *,
    food_id: int,
    source_id: int,
    source_ref: str,
    name_es: str,
    name_en: str | None,
    group: str,
    state: str | None,
    ripeness: str,
    proxy_of: int | None,
    nutrients: dict[int, float],
    properties: dict[str, object],
) -> None:
    con.execute(
        "INSERT INTO foods(id, source_id, source_ref, canonical_name_es, canonical_name_en, food_group, state, "
        "ripeness, proxy_of, parent_id) VALUES (?,?,?,?,?,?,?,?,?,NULL)",
        (food_id, source_id, source_ref, name_es, name_en, group, state, ripeness, proxy_of),
    )
    con.executemany(
        "INSERT INTO food_nutrients(food_id, nutrient_id, amount_per_100g) VALUES (?,?,?)",
        [(food_id, nutrient_id, value) for nutrient_id, value in sorted(nutrients.items())],
    )
    columns = ", ".join(properties)
    marks = ", ".join("?" for _ in properties)
    con.execute(
        f"INSERT INTO food_properties(food_id, {columns}) VALUES (?, {marks})",
        (food_id, *properties.values()),
    )


def build(inputs: BuildInputs, out_path: Path, *, strict: bool = True) -> BuildReport:
    """Writes the database to ``out_path`` and ``out_path.sha256``."""
    report = BuildReport()
    glossary = inputs.glossary or Glossary.load()
    datasets = [inputs.sr] + ([inputs.foundation] if inputs.foundation else [])
    resolver = _Resolver(datasets)

    # Curated synonyms → food ids, primary names and ripeness.
    synonyms_by_food: dict[int, list[dict[str, str]]] = {}
    for row in inputs.synonyms:
        food_id = resolver.resolve(row["fdc_description"])
        if food_id is None:
            report.errors.append(
                f"sinónimo «{row['name']}»: no existe «{row['fdc_description']}». "
                f"Parecidos: {_closest(row['fdc_description'], resolver.descriptions)}"
            )
            continue
        synonyms_by_food.setdefault(food_id, []).append(row)
    for food_id, rows in synonyms_by_food.items():
        primaries = [r for r in rows if r.get("is_primary") == "1"]
        if len(primaries) != 1:
            report.errors.append(f"alimento {food_id}: debe tener exactamente un nombre principal")

    gi_by_food: dict[int, dict[str, str]] = {}
    for row in inputs.gi_rows:
        food_id = resolver.resolve(row["fdc_description"])
        if food_id is None:
            report.errors.append(
                f"IG «{row['food_in_source']}»: no existe «{row['fdc_description']}». "
                f"Parecidos: {_closest(row['fdc_description'], resolver.descriptions)}"
            )
            continue
        gi_by_food[food_id] = row

    if strict and report.errors:
        raise MappingError("\n".join(report.errors))

    tmp = out_path.with_name(out_path.name + ".tmp")
    if tmp.exists():
        tmp.unlink()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(tmp)
    try:
        con.executescript(DDL)
        source_ids = _insert_sources(con, inputs)

        # Nutrients present in any kept food.
        nutrient_defs: dict[int, fdc.FdcNutrient] = {}
        for dataset in datasets:
            used = {nid for amounts in dataset.amounts.values() for nid in amounts}
            for nid in used:
                if nid in dataset.nutrients:
                    nutrient_defs.setdefault(nid, dataset.nutrients[nid])
        for nid, nutrient in sorted(nutrient_defs.items()):
            name_es, category = nutrient_name_es(nid, nutrient.name)
            con.execute(
                "INSERT INTO nutrients(id, fdc_nutrient_id, name_es, unit, category) VALUES (?,?,?,?,?)",
                (nid, nid, name_es, unit_es(nutrient.unit), category),
            )
        known_nutrients = set(nutrient_defs)

        names: list[tuple[int, str, str, int]] = []
        skipped_no_energy = 0
        food_count = 0
        for dataset, code in ((inputs.sr, "FDC_SR"), (inputs.foundation, "FDC_FOUNDATION")):
            if dataset is None:
                continue
            for fdc_id, food in sorted(dataset.foods.items()):
                curated = synonyms_by_food.get(fdc_id, [])
                primary = next((r for r in curated if r.get("is_primary") == "1"), None)
                ripeness = (primary or {}).get("ripeness") or "na"
                nutrients = _filtered_amounts(food, dataset.amounts.get(fdc_id, {}), ripeness, report)
                energy = energy_density.energy_kcal(nutrients)
                if energy is None:
                    skipped_no_energy += 1
                    continue
                name_es = primary["name"] if primary else glossary.translate(food.description)
                properties = _properties(food.description, food.category, nutrients, energy, proxy=False)
                gi_row = gi_by_food.get(fdc_id)
                if gi_row:
                    gi = float(gi_row["gi"])
                    m = taxonomy.macros(nutrients)
                    available = None
                    if m["carbs"] is not None and m["fiber"] is not None:
                        available = max(m["carbs"] - m["fiber"], 0.0)
                    properties["gi"] = gi
                    properties["gi_ref"] = (
                        f"{gi_row['reference']} — «{gi_row['food_in_source']}», IG {gi_row['gi']} ± {gi_row['gi_sem']}"
                    )
                    properties["gl_per_100g"] = None if available is None else gi * available / 100.0
                ref = f"FDC {fdc_id}" + (f" / NDB {food.ndb_number}" if food.ndb_number else "")
                _insert_food(
                    con,
                    food_id=fdc_id,
                    source_id=source_ids[code],
                    source_ref=ref,
                    name_es=name_es,
                    name_en=food.description,
                    group=taxonomy.food_group_es(food.category),
                    state=state_of(food.description),
                    ripeness=ripeness,
                    proxy_of=None,
                    nutrients=nutrients,
                    properties=properties,
                )
                food_count += 1
                names.append((fdc_id, name_es, "GEN", 1))
                names.append((fdc_id, food.description, "GEN", 0))
                for row in curated:
                    if row is primary:
                        continue
                    names.append((fdc_id, row["name"], row["region"], 0))

        for index, local in enumerate(inputs.local_foods):
            food_id = LOCAL_ID_BASE + index
            energy = energy_density.energy_kcal(local.nutrients)
            if energy is None:
                report.warnings.append(f"local «{local.name_es}» sin energía: no se incluye")
                continue
            proxy = local.proxy_fdc_id
            if proxy is not None and proxy not in resolver._by_desc.values():
                report.warnings.append(f"local «{local.name_es}»: proxy_fdc_id {proxy} no existe; se ignora")
                proxy = None
            nutrients = {k: v for k, v in local.nutrients.items() if k in known_nutrients}
            properties = _properties(local.name_es, None, nutrients, energy, proxy=proxy is not None)
            _insert_food(
                con,
                food_id=food_id,
                source_id=source_ids[f"LOCAL_{local.file_code}"],
                source_ref=f"{local.file_code} #{index + 1}",
                name_es=local.name_es,
                name_en=None,
                group="Tabla local",
                state=None,
                ripeness="na",
                proxy_of=proxy,
                nutrients=nutrients,
                properties=properties,
            )
            food_count += 1
            names.append((food_id, local.name_es, local.region, 1))

        con.executemany(
            "INSERT INTO food_names(food_id, name, region, is_primary) VALUES (?,?,?,?)", names
        )
        con.execute("INSERT INTO food_names_fts(name, food_id) SELECT name, food_id FROM food_names")

        product_rows = []
        for product in inputs.products:
            nova, nova_source = product.nova, "off" if product.nova is not None else None
            if nova is None:
                nova, _reason = nova_rules.classify_ingredients(product.ingredients_text)
                nova_source = "rules" if nova is not None else None
            product_rows.append(
                (
                    product.barcode, product.name, product.brand, product.countries, nova, nova_source,
                    product.nutriscore, product.additives, product.ingredients_text, product.kcal_100g,
                    product.protein_100g, product.fat_100g, product.carb_100g, product.sugars_100g,
                    product.fiber_100g, product.sodium_mg_100g,
                )
            )
        con.executemany(
            "INSERT INTO products(barcode, name, brand, countries, nova, nova_source, nutriscore, additives, "
            "ingredients_text, kcal_100g, protein_100g, fat_100g, carb_100g, sugars_100g, fiber_100g, "
            "sodium_mg_100g, mapped_food_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)",
            product_rows,
        )
        con.execute("INSERT INTO products_fts(name, brand, barcode) SELECT name, coalesce(brand, ''), barcode FROM products")

        recipe_count = _insert_recipes(con, inputs, resolver, report)
        exercise_count = _insert_exercises(con, inputs, report)

        if strict and report.errors:
            raise MappingError("\n".join(report.errors))

        con.commit()
        con.execute(f"PRAGMA user_version = {USER_VERSION}")
        con.commit()
        con.execute("VACUUM")
        report.counts = {
            "foods": food_count,
            "food_names": len(names),
            "nutrients": len(nutrient_defs),
            "products": len(product_rows),
            "recipes": recipe_count,
            "exercises": exercise_count,
            "gi_values": len(gi_by_food),
            "skipped_without_energy": skipped_no_energy,
        }
    finally:
        con.close()

    os.replace(tmp, out_path)
    digest = hashlib.sha256(out_path.read_bytes()).hexdigest()
    out_path.with_name(out_path.name + ".sha256").write_text(f"{digest}  {out_path.name}\n", encoding="utf-8")
    return report


def _find_product(products: list[off.OffProduct], query: str) -> off.OffProduct | None:
    tokens = normalize(query).split()
    candidates = [
        p
        for p in products
        if all(token in normalize(p.name) for token in tokens)
        and p.kcal_100g is not None
        and p.protein_100g is not None
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda p: (p.popularity, p.barcode))


def _insert_recipes(
    con: sqlite3.Connection, inputs: BuildInputs, resolver: _Resolver, report: BuildReport
) -> int:
    grouped: dict[str, list[dict[str, str]]] = {}
    for row in inputs.recipes:
        grouped.setdefault(row["recipe_key"], []).append(row)
    count = 0
    for recipe_id, (key, rows) in enumerate(grouped.items(), start=1):
        items: list[tuple[int | None, str | None, float]] = []
        complete = True
        for row in rows:
            grams = float(row["grams"])
            if row["kind"] == "fdc":
                food_id = resolver.resolve(row["ref"])
                if food_id is None:
                    report.errors.append(
                        f"receta {key}: no existe «{row['ref']}». Parecidos: {_closest(row['ref'], resolver.descriptions)}"
                    )
                    complete = False
                    continue
                items.append((food_id, None, grams))
            elif row["kind"] == "product_query":
                product = _find_product(inputs.products, row["ref"])
                if product is None:
                    report.warnings.append(
                        f"receta {key}: ningún producto de EC/VE/CO coincide con «{row['ref']}»; la receta no se incluye"
                    )
                    complete = False
                    continue
                items.append((None, product.barcode, grams))
            elif row["kind"] == "barcode":
                items.append((None, row["ref"], grams))
            else:
                report.errors.append(f"receta {key}: tipo desconocido {row['kind']}")
                complete = False
        if not complete:
            continue
        con.execute("INSERT INTO recipes(id, name_es) VALUES (?, ?)", (recipe_id, rows[0]["name_es"]))
        con.executemany(
            "INSERT INTO recipe_items(recipe_id, food_id, barcode, grams) VALUES (?,?,?,?)",
            [(recipe_id, food_id, barcode, grams) for food_id, barcode, grams in items],
        )
        count += 1
    return count


def _insert_exercises(con: sqlite3.Connection, inputs: BuildInputs, report: BuildReport) -> int:
    by_key = {row["key"]: int(row["id"]) for row in inputs.exercises}
    for row in inputs.exercises:
        substitute = row.get("substitute_key") or ""
        if substitute and substitute not in by_key:
            report.errors.append(f"ejercicio {row['key']}: sustituto desconocido {substitute}")
        con.execute(
            "INSERT INTO exercises(id, name_es, equipment, muscles, failure_safe, rep_min, rep_max, "
            "min_increment_kg, tempo, substitute_id, cue_es) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (
                int(row["id"]), row["name_es"], row["equipment"], row["muscles"], int(row["failure_safe"]),
                int(row["rep_min"]), int(row["rep_max"]), float(row["min_increment_kg"]), row["tempo"],
                by_key.get(substitute) if substitute else None, row["cue_es"],
            ),
        )
    template_rows = []
    for row in inputs.exercises:
        template = (row.get("template") or "").strip()
        if not template:
            continue
        position = int(row["position"])
        template_rows.append((template, position, int(row["id"])))
        if template == "A":
            template_rows.append(("BASELINE", position, int(row["id"])))
    con.executemany(
        "INSERT INTO exercise_templates(template, position, exercise_id) VALUES (?,?,?)", template_rows
    )
    return len(inputs.exercises)


def load_off(
    url: str,
    cache: Path,
    *,
    optional: bool,
    downloader=download,
) -> tuple[list[off.OffProduct], str | None]:
    """Downloads and filters the Open Food Facts export.

    With ``optional`` a failed download is reported and the build continues
    without packaged products (the app still looks them up online).
    """
    try:
        path = downloader(url, cache)
    except (RuntimeError, OSError) as error:
        if not optional:
            raise
        print(f"[aviso] Open Food Facts no disponible, se omite: {error}", file=sys.stderr)
        return [], None
    return off.load_products(path), dt.date.fromtimestamp(path.stat().st_mtime).isoformat()


def default_inputs(args: argparse.Namespace) -> BuildInputs:
    cache = Path(args.cache)
    sr = fdc.load_sr_legacy(cache, args.sr_url)
    foundation = None if args.no_foundation else fdc.load_foundation(cache, args.foundation_url)
    products: list[off.OffProduct] = []
    off_version = None
    if args.off_file:
        path = Path(args.off_file)
        products = off.load_products(path)
        off_version = dt.date.fromtimestamp(path.stat().st_mtime).isoformat()
    elif not args.skip_off:
        products, off_version = load_off(args.off_url, cache, optional=args.off_optional)
    return BuildInputs(
        sr=sr,
        foundation=foundation,
        products=products,
        off_version=off_version,
        local_foods=ecuador_tables.load_local_tables(Path(args.local_dir)),
        synonyms=read_csv(DATA_DIR / "synonyms_es.csv"),
        gi_rows=read_csv(DATA_DIR / "gi_values.csv"),
        recipes=read_csv(DATA_DIR / "recipes.csv"),
        exercises=read_csv(DATA_DIR / "exercises.csv"),
        glossary=Glossary.load(),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Construye reference.sqlite")
    parser.add_argument("--out", default=str(ROOT / "assets" / "db" / "reference.sqlite"))
    parser.add_argument("--cache", default=str(ROOT / "etl" / ".cache"))
    parser.add_argument("--local-dir", default=str(DATA_DIR / "local"))
    parser.add_argument("--sr-url", default=fdc.SR_LEGACY_URL)
    parser.add_argument("--foundation-url", default=None)
    parser.add_argument("--no-foundation", action="store_true")
    parser.add_argument("--skip-off", action="store_true")
    parser.add_argument("--off-url", default=off.OFF_CSV_URL)
    parser.add_argument("--off-file", default=None)
    parser.add_argument(
        "--off-optional",
        action="store_true",
        help="continúa sin productos si la descarga de Open Food Facts falla",
    )
    parser.add_argument("--report-json", default=None)
    parser.add_argument("--non-strict", action="store_true")
    args = parser.parse_args(argv)

    inputs = default_inputs(args)
    try:
        report = build(inputs, Path(args.out), strict=not args.non_strict)
    except MappingError as error:
        print("ERRORES DE MAPEO:\n" + str(error), file=sys.stderr)
        return 2
    for line in report.ripeness_audit:
        print(f"[madurez] {line}")
    for warning in report.warnings:
        print(f"[aviso] {warning}")
    print(json.dumps(report.counts, ensure_ascii=False))
    if args.report_json:
        Path(args.report_json).write_text(report.to_json(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
