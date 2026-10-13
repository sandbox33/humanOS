"""Open Food Facts export (ODbL), filtered to Ecuador, Venezuela, Colombia.

The nightly CSV is tab separated and very large, so it is streamed from the
gzip file line by line. A cheap substring test discards most lines before
any field is split; the ``countries_tags`` column is then checked exactly.
Label values per 100 g are kept as published; implausible values become
NULL instead of being "fixed".
"""
from __future__ import annotations

import gzip
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator

OFF_CSV_URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
COUNTRY_TAGS = ("en:ecuador", "en:venezuela", "en:colombia")

_NUMERIC = {
    "kcal_100g": "energy-kcal_100g",
    "protein_100g": "proteins_100g",
    "fat_100g": "fat_100g",
    "carb_100g": "carbohydrates_100g",
    "sugars_100g": "sugars_100g",
    "fiber_100g": "fiber_100g",
    "sodium_100g": "sodium_100g",
}
# Physical upper bounds per 100 g; anything above is a data-entry error.
_MAX_PER_100G = {
    "kcal_100g": 900.0,
    "protein_100g": 100.0,
    "fat_100g": 100.0,
    "carb_100g": 100.0,
    "sugars_100g": 100.0,
    "fiber_100g": 100.0,
    "sodium_100g": 40.0,
}
_BARCODE_RE = re.compile(r"^\d{8,14}$")


@dataclass(frozen=True)
class OffProduct:
    barcode: str
    name: str
    brand: str | None
    countries: str
    nova: int | None
    nutriscore: str | None
    additives: str | None
    ingredients_text: str | None
    kcal_100g: float | None
    protein_100g: float | None
    fat_100g: float | None
    carb_100g: float | None
    sugars_100g: float | None
    fiber_100g: float | None
    sodium_mg_100g: float | None
    popularity: int


def _number(text: str | None, key: str) -> float | None:
    if text is None:
        return None
    text = text.strip()
    if not text:
        return None
    try:
        value = float(text)
    except ValueError:
        return None
    if value != value or value < 0 or value > _MAX_PER_100G[key]:
        return None
    return value


def _clean(text: str | None) -> str | None:
    if text is None:
        return None
    text = " ".join(text.split())
    return text or None


def parse_lines(lines: Iterable[str], countries: tuple[str, ...] = COUNTRY_TAGS) -> Iterator[OffProduct]:
    """Parses the export's lines (header first)."""
    iterator = iter(lines)
    try:
        header = next(iterator).rstrip("\n").split("\t")
    except StopIteration:
        return
    index = {name: i for i, name in enumerate(header)}
    required = ("code", "product_name", "countries_tags")
    if any(name not in index for name in required):
        raise ValueError("Cabecera de Open Food Facts inesperada")
    width = len(header)

    def field(values: list[str], name: str) -> str | None:
        i = index.get(name)
        return values[i] if i is not None and i < len(values) else None

    seen: set[str] = set()
    for line in iterator:
        if not any(tag in line for tag in countries):
            continue
        values = line.rstrip("\n").split("\t")
        if len(values) != width:
            continue
        tags = (field(values, "countries_tags") or "").split(",")
        matched = [tag for tag in tags if tag in countries]
        if not matched:
            continue
        barcode = (field(values, "code") or "").strip()
        name = _clean(field(values, "product_name"))
        if not _BARCODE_RE.match(barcode) or not name or barcode in seen:
            continue
        numbers = {key: _number(field(values, column), key) for key, column in _NUMERIC.items()}
        if numbers["kcal_100g"] is None and numbers["protein_100g"] is None:
            continue
        nova_text = (field(values, "nova_group") or "").strip()
        nova = int(float(nova_text)) if nova_text and nova_text.replace(".", "", 1).isdigit() else None
        if nova is not None and not 1 <= nova <= 4:
            nova = None
        scans_text = (field(values, "unique_scans_n") or "").strip()
        popularity = int(float(scans_text)) if scans_text.replace(".", "", 1).isdigit() else 0
        sodium = numbers["sodium_100g"]
        seen.add(barcode)
        yield OffProduct(
            barcode=barcode,
            name=name,
            brand=_clean(field(values, "brands")),
            countries=",".join(matched),
            nova=nova,
            nutriscore=_clean(field(values, "nutriscore_grade")),
            additives=_clean(field(values, "additives_tags")),
            ingredients_text=_clean(field(values, "ingredients_text")),
            kcal_100g=numbers["kcal_100g"],
            protein_100g=numbers["protein_100g"],
            fat_100g=numbers["fat_100g"],
            carb_100g=numbers["carb_100g"],
            sugars_100g=numbers["sugars_100g"],
            fiber_100g=numbers["fiber_100g"],
            sodium_mg_100g=None if sodium is None else sodium * 1000,
            popularity=popularity,
        )


def load_products(path: Path, countries: tuple[str, ...] = COUNTRY_TAGS) -> list[OffProduct]:
    """Streams a downloaded ``.csv.gz`` (or plain ``.csv``) export."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8", errors="replace", newline="") as handle:
        return list(parse_lines(handle, countries))
