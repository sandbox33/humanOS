"""NOVA classification rules (Monteiro CA et al. 2019).

Products keep Open Food Facts' own ``nova_group`` when present
(``nova_source = 'off'``). Otherwise these rules run on the ingredient list
(``'rules'``):

* NOVA 4 when a marker of ultra-processing appears: hydrogenated oil,
  high-fructose syrup, maltodextrin, emulsifiers (E471, E322/lecithin),
  artificial sweeteners, flavourings/aromas.
* NOVA 2 for a single culinary ingredient (salt, sugar, oil, butter…).
* NOVA 1 for any other single ingredient ("maní 100%").
* Otherwise unknown (NULL): not enough evidence.

FDC foods have no ingredient list: plain raw or plainly cooked single foods
are NOVA 1; everything else stays NULL.
"""
from __future__ import annotations

import re

from .names_es import normalize

_ULTRA_PATTERNS = [
    r"hidrogenad",
    r"hydrogenated",
    r"jarabe de (maiz de )?alta fructosa",
    r"jarabe de glucosa[- ]fructosa",
    r"high[- ]fructose",
    r"\bjmaf\b",
    r"maltodextrin",
    r"\bins ?471\b",
    r"\be[ -]?471\b",
    r"mono ?y ?digliceridos",
    r"mono- y digliceridos",
    r"monogliceridos",
    r"mono and diglycerides",
    r"\bins ?322\b",
    r"\be[ -]?322\b",
    r"lecitina",
    r"lecithin",
    r"emulsionante",
    r"emulsificante",
    r"emulsifier",
    r"sucralos",
    r"aspartam",
    r"acesulfam",
    r"sacarina",
    r"saccharin",
    r"ciclamato",
    r"cyclamate",
    r"neotam",
    r"edulcorante",
    r"sweetener",
    r"\be[ -]?95[0-5]\b",
    r"\be[ -]?96[1-2]\b",
    r"saborizante",
    r"aromatizante",
    r"\baromas?\b",
    r"\bsabor(es)? (artificial|natural|identico)",
    r"\bflavou?r(ing|s)?\b",
]
_ULTRA_RE = [re.compile(p) for p in _ULTRA_PATTERNS]

_CULINARY = (
    "sal",
    "sal marina",
    "sal yodada",
    "azucar",
    "azucar morena",
    "panela",
    "miel",
    "miel de abeja",
    "aceite",
    "aceite de oliva",
    "aceite vegetal",
    "aceite de girasol",
    "aceite de soya",
    "manteca",
    "mantequilla",
    "vinagre",
    "almidon",
    "fecula de maiz",
)


def ultra_markers(ingredients_text: str) -> list[str]:
    """Normalised fragments that trigger NOVA 4."""
    text = normalize(ingredients_text)
    found = []
    for pattern in _ULTRA_RE:
        match = pattern.search(text)
        if match:
            found.append(match.group(0))
    return found


def split_ingredients(ingredients_text: str) -> list[str]:
    """Top-level ingredients (commas and semicolons outside parentheses)."""
    parts: list[str] = []
    depth = 0
    current = []
    for ch in ingredients_text:
        if ch in "([":
            depth += 1
        elif ch in ")]" and depth > 0:
            depth -= 1
        if ch in ",;" and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    parts.append("".join(current))
    cleaned = []
    for part in parts:
        text = normalize(part).strip(" .:*")
        text = re.sub(r"^ingredientes?\s*:?\s*", "", text)
        if text:
            cleaned.append(text)
    return cleaned


def classify_ingredients(ingredients_text: str | None) -> tuple[int | None, str]:
    """(NOVA group or None, Spanish reason)."""
    if not ingredients_text or not ingredients_text.strip():
        return None, "sin lista de ingredientes"
    markers = ultra_markers(ingredients_text)
    if markers:
        return 4, "marcador de ultraprocesado: " + ", ".join(sorted(set(markers)))
    ingredients = split_ingredients(ingredients_text)
    if len(ingredients) == 1:
        base = re.sub(r"\s*\d+([.,]\d+)?\s*%", "", ingredients[0]).strip()
        if base in _CULINARY:
            return 2, "ingrediente culinario único"
        return 1, "un solo ingrediente"
    return None, "varios ingredientes sin marcadores: no se puede afirmar"


_PLAIN_GROUPS = {
    "Fruits and Fruit Juices",
    "Vegetables and Vegetable Products",
    "Legumes and Legume Products",
    "Nut and Seed Products",
    "Poultry Products",
    "Pork Products",
    "Beef Products",
    "Finfish and Shellfish Products",
    "Lamb, Veal, and Game Products",
    "Cereal Grains and Pasta",
    "Dairy and Egg Products",
    "Spices and Herbs",
}
_PROCESSED_WORDS = re.compile(
    r"\b(canned|sweetened|salted|cured|smoked|breaded|batter|sauce|syrup|"
    r"juice|nectar|drink|cheese|yogurt|candied|pickled|dehydrated|"
    r"frozen|prepared|ready-to|mix|with added|fortified|enriched|imitation)\b"
)
_COOKED_PLAIN = re.compile(r"\b(boiled|roasted|steamed|baked|broiled|grilled|braised|stewed)\b")


def classify_fdc_food(description: str, category: str | None) -> int | None:
    """NOVA 1 for plain single foods (raw, or plainly cooked without salt)."""
    if category not in _PLAIN_GROUPS:
        return None
    text = description.lower()
    if _PROCESSED_WORDS.search(text):
        return None
    if re.search(r"(^|, )raw(,|$)", text):
        return 1
    if _COOKED_PLAIN.search(text) and "without salt" in text:
        return 1
    return None
