"""Computed multi-axis taxonomy. Nothing here is set by hand per food.

* ``macro_dominant``: fibre ≥ 15 g/100 g → ``fiber``; otherwise the macro
  with more than half of the energy (protein 4, fat 9, available
  carbohydrate 4 kcal/g); carbohydrate splits into ``carb_sugar`` when
  sugars exceed starch, else ``carb_starch``. No majority, or a carbohydrate
  food whose sugar/starch split is unknown, is ``mixed``.
* food group, heme iron, polyphenol inhibitors, allergens and practical
  notes come from the FDC category and description words.
* limiting amino acid uses the FAO 2013 scoring pattern (no digestibility,
  so it is not a DIAAS; DIAAS stays NULL unless published).
"""
from __future__ import annotations

import re
from typing import Mapping

FIBER_DOMINANT_G = 15.0
DOMINANCE_SHARE = 0.5

PROTEIN = 1003
FAT = 1004
FAT_NLEA = 1085
CARBS = 1005
CARBS_SUM = 1050
FIBER = 1079
FIBER_AOAC = 2033
SUGARS = 2000
SUGARS_ALT = 1063
STARCH = 1009
LEUCINE = 1213


def first(nutrients: Mapping[int, float], *ids: int) -> float | None:
    for nutrient_id in ids:
        value = nutrients.get(nutrient_id)
        if value is not None:
            return value
    return None


def macros(nutrients: Mapping[int, float]) -> dict[str, float | None]:
    return {
        "protein": first(nutrients, PROTEIN),
        "fat": first(nutrients, FAT, FAT_NLEA),
        "carbs": first(nutrients, CARBS, CARBS_SUM),
        "fiber": first(nutrients, FIBER, FIBER_AOAC),
        "sugars": first(nutrients, SUGARS, SUGARS_ALT),
        "starch": first(nutrients, STARCH),
    }


def macro_dominant(
    *,
    protein: float | None,
    fat: float | None,
    carbs: float | None,
    fiber: float | None,
    sugars: float | None,
    starch: float | None,
) -> str:
    if fiber is not None and fiber >= FIBER_DOMINANT_G:
        return "fiber"
    available = None if carbs is None else max(carbs - (fiber or 0.0), 0.0)
    energy = {}
    if protein is not None:
        energy["protein"] = protein * 4
    if fat is not None:
        energy["fat"] = fat * 9
    if available is not None:
        energy["carb"] = available * 4
    total = sum(energy.values())
    if total <= 0:
        return "mixed"
    top, value = max(energy.items(), key=lambda item: item[1])
    if value / total <= DOMINANCE_SHARE:
        return "mixed"
    if top != "carb":
        return top
    if sugars is not None and starch is not None:
        return "carb_sugar" if sugars > starch else "carb_starch"
    if sugars is not None:
        return "carb_sugar" if sugars > max(available - sugars, 0.0) else "carb_starch"
    if starch is not None:
        return "carb_sugar" if max(available - starch, 0.0) > starch else "carb_starch"
    return "mixed"


CATEGORY_ES = {
    "Dairy and Egg Products": "Lácteos y huevos",
    "Spices and Herbs": "Especias y hierbas",
    "Baby Foods": "Alimentos infantiles",
    "Fats and Oils": "Grasas y aceites",
    "Poultry Products": "Aves",
    "Soups, Sauces, and Gravies": "Sopas y salsas",
    "Sausages and Luncheon Meats": "Embutidos",
    "Breakfast Cereals": "Cereales de desayuno",
    "Fruits and Fruit Juices": "Frutas y jugos",
    "Pork Products": "Cerdo",
    "Vegetables and Vegetable Products": "Verduras y hortalizas",
    "Nut and Seed Products": "Frutos secos y semillas",
    "Beef Products": "Res",
    "Beverages": "Bebidas",
    "Finfish and Shellfish Products": "Pescados y mariscos",
    "Legumes and Legume Products": "Leguminosas",
    "Lamb, Veal, and Game Products": "Cordero, ternera y caza",
    "Baked Products": "Panadería",
    "Sweets": "Dulces",
    "Cereal Grains and Pasta": "Cereales y pastas",
    "Fast Foods": "Comida rápida",
    "Meals, Entrees, and Side Dishes": "Platos preparados",
    "Snacks": "Snacks",
    "American Indian/Alaska Native Foods": "Alimentos tradicionales nativos (EE. UU.)",
    "Restaurant Foods": "Comida de restaurante",
}

_HEME = {
    "Poultry Products",
    "Pork Products",
    "Beef Products",
    "Finfish and Shellfish Products",
    "Lamb, Veal, and Game Products",
    "Sausages and Luncheon Meats",
}
_NON_HEME = {
    "Dairy and Egg Products",
    "Spices and Herbs",
    "Fats and Oils",
    "Breakfast Cereals",
    "Fruits and Fruit Juices",
    "Vegetables and Vegetable Products",
    "Nut and Seed Products",
    "Beverages",
    "Legumes and Legume Products",
    "Baked Products",
    "Sweets",
    "Cereal Grains and Pasta",
    "Snacks",
}


def food_group_es(category: str | None) -> str:
    if not category:
        return "Sin grupo"
    return CATEGORY_ES.get(category, category)


def iron_heme(category: str | None) -> int | None:
    """1 when the food's iron is (partly) heme, 0 for plant/dairy/egg."""
    if category in _HEME:
        return 1
    if category in _NON_HEME:
        return 0
    return None


_INHIBITOR_RE = re.compile(r"\b(coffee|tea|cocoa|chocolate|hibiscus|mate)\b", re.I)


def inhibits_nonheme_iron(description: str) -> int:
    return 1 if _INHIBITOR_RE.search(description) else 0


_ALLERGENS = (
    ("leche", re.compile(r"\b(milk|cheese|yogurt|butter|cream|whey|casein|ice cream)\b", re.I)),
    ("huevo", re.compile(r"\begg(s)?\b", re.I)),
    ("maní", re.compile(r"\bpeanut", re.I)),
    (
        "frutos de cáscara",
        re.compile(r"\b(almond|walnut|cashew|pistachio|hazelnut|pecan|macadamia|brazilnut)", re.I),
    ),
    ("soya", re.compile(r"\bsoy", re.I)),
    ("trigo", re.compile(r"\bwheat\b", re.I)),
    ("pescado", re.compile(r"^fish\b", re.I)),
    (
        "mariscos",
        re.compile(r"\b(shrimp|crab|lobster|clam|oyster|mussel|scallop|squid|octopus|crustacean)", re.I),
    ),
    ("sésamo", re.compile(r"\bsesame\b", re.I)),
)


def allergens(description: str) -> str | None:
    """Possible allergens detected from the food name (not from a label)."""
    found = [name for name, pattern in _ALLERGENS if pattern.search(description)]
    return ", ".join(found) if found else None


_ANTINUTRIENT_NOTES = (
    (
        re.compile(r"^beans, kidney.*\braw\b", re.I),
        "Fréjol rojo crudo: contiene fitohemaglutinina; remojar y hervir a fondo (10 min o más).",
    ),
    (
        re.compile(r"^(beans|lentils|chickpeas|peas|soybeans|cowpeas)\b.*\bmature seeds, raw", re.I),
        "Leguminosa cruda: remojar y cocer bien (lectinas, fitatos).",
    ),
    (
        re.compile(r"^cassava\b.*\braw\b", re.I),
        "Yuca cruda: contiene glucósidos cianogénicos; pelar y cocer bien.",
    ),
    (
        re.compile(r"^(spinach|chard|beet greens|amaranth leaves)\b", re.I),
        "Oxalatos: reducen la absorción de su propio calcio.",
    ),
    (
        re.compile(r"\b(bran|whole-grain|whole grain|whole-wheat)\b", re.I),
        "Fitatos: reducen algo la absorción de hierro y zinc.",
    ),
)
_RESISTANT_STARCH_NOTES = (
    (
        re.compile(r"^(plantains|bananas)\b.*\bgreen\b", re.I),
        "Verde: más almidón resistente; baja al madurar y al cocer.",
    ),
    (
        re.compile(r"^(rice|potatoes|pasta)\b.*\b(cooked|boiled)\b", re.I),
        "Cocido y enfriado aumenta el almidón resistente.",
    ),
)


def antinutrient_note(description: str) -> str | None:
    for pattern, note in _ANTINUTRIENT_NOTES:
        if pattern.search(description):
            return note
    return None


def resistant_starch_note(description: str) -> str | None:
    for pattern, note in _RESISTANT_STARCH_NOTES:
        if pattern.search(description):
            return note
    return None


# FAO 2013 amino acid scoring pattern for older children, adolescents and
# adults, mg per g of protein.
FAO_2013_PATTERN = {
    "Histidina": 16.0,
    "Isoleucina": 30.0,
    "Leucina": 61.0,
    "Lisina": 48.0,
    "Azufrados (metionina + cistina)": 23.0,
    "Aromáticos (fenilalanina + tirosina)": 41.0,
    "Treonina": 25.0,
    "Triptófano": 6.6,
    "Valina": 40.0,
}
# FDC amino acid nutrient ids (g per 100 g of food).
AMINO_IDS = {
    "trp": 1210,
    "thr": 1211,
    "ile": 1212,
    "leu": 1213,
    "lys": 1214,
    "met": 1215,
    "cys": 1216,
    "phe": 1217,
    "tyr": 1218,
    "val": 1219,
    "his": 1221,
}


def limiting_amino_acid(nutrients: Mapping[int, float]) -> str | None:
    """Most limiting amino acid when its score is below 1, else None."""
    protein = nutrients.get(PROTEIN)
    values = {key: nutrients.get(fdc_id) for key, fdc_id in AMINO_IDS.items()}
    if not protein or protein <= 0 or any(v is None for v in values.values()):
        return None

    def per_g(grams: float) -> float:
        return grams / protein * 1000.0

    scores = {
        "Histidina": per_g(values["his"]) / FAO_2013_PATTERN["Histidina"],
        "Isoleucina": per_g(values["ile"]) / FAO_2013_PATTERN["Isoleucina"],
        "Leucina": per_g(values["leu"]) / FAO_2013_PATTERN["Leucina"],
        "Lisina": per_g(values["lys"]) / FAO_2013_PATTERN["Lisina"],
        "Azufrados (metionina + cistina)": per_g(values["met"] + values["cys"])
        / FAO_2013_PATTERN["Azufrados (metionina + cistina)"],
        "Aromáticos (fenilalanina + tirosina)": per_g(values["phe"] + values["tyr"])
        / FAO_2013_PATTERN["Aromáticos (fenilalanina + tirosina)"],
        "Treonina": per_g(values["thr"]) / FAO_2013_PATTERN["Treonina"],
        "Triptófano": per_g(values["trp"]) / FAO_2013_PATTERN["Triptófano"],
        "Valina": per_g(values["val"]) / FAO_2013_PATTERN["Valina"],
    }
    name, score = min(scores.items(), key=lambda item: item[1])
    return name if score < 1.0 else None


def fat_energy_share(nutrients: Mapping[int, float], energy_kcal: float | None) -> float | None:
    """Share of energy from fat (0–1): a proxy for slower gastric emptying."""
    fat = first(nutrients, FAT, FAT_NLEA)
    if fat is None or not energy_kcal or energy_kcal <= 0:
        return None
    return min(fat * 9.0 / energy_kcal, 1.0)


def confidence(nutrients: Mapping[int, float], *, nrf_missing: int, proxy: bool) -> str:
    """alta: macros and ≥ 8 of 12 NRF components; media: macros present;
    baja: a macro missing or the food is a proxy of another one."""
    m = macros(nutrients)
    if proxy or any(m[key] is None for key in ("protein", "fat", "carbs")):
        return "baja"
    if nrf_missing <= 4:
        return "alta"
    return "media"
