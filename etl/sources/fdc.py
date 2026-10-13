"""USDA FoodData Central loader: SR Legacy and Foundation Foods (CSV zips).

Both datasets are public domain (CC0). Values are loaded exactly as
published; a missing value stays missing. The derivation code of every
value is kept so that "analytical only" rules can drop imputed or borrowed
values (e.g. sugars and starch of plantains).
"""
from __future__ import annotations

import csv
import io
import re
import sys
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

from .http import download, fetch_text

SR_LEGACY_URL = (
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip"
)
DOWNLOAD_PAGE_URLS = (
    "https://fdc.nal.usda.gov/download-datasets",
    "https://fdc.nal.usda.gov/download-datasets.html",
)
# Known Foundation Foods releases, newest first. Used only when the
# download page cannot be parsed.
FOUNDATION_FALLBACK_URLS = (
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2025-12-18.zip",
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2025-04-24.zip",
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2024-10-31.zip",
    "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2024-04-18.zip",
)
_FOUNDATION_RE = re.compile(r"FoodData_Central_foundation_food_csv_(\d{4}-\d{2}-\d{2})\.zip")

SR_LEGACY_TYPE = "sr_legacy_food"
FOUNDATION_TYPE = "foundation_food"


@dataclass(frozen=True)
class FdcFood:
    fdc_id: int
    data_type: str
    description: str
    category: str | None
    ndb_number: str | None


@dataclass(frozen=True)
class FdcNutrient:
    id: int
    name: str
    unit: str
    nutrient_nbr: str | None


@dataclass(frozen=True)
class FdcAmount:
    amount: float
    derivation_code: str | None
    derivation_description: str | None

    @property
    def analytical(self) -> bool:
        """True when the value comes from analysis of this food itself."""
        code = (self.derivation_code or "").upper()
        description = (self.derivation_description or "").lower()
        if code in {"A", "AS", "AR", "MA"}:
            return True
        return description.startswith("analytical")


@dataclass
class FdcDataset:
    label: str
    version: str
    url: str
    foods: dict[int, FdcFood] = field(default_factory=dict)
    nutrients: dict[int, FdcNutrient] = field(default_factory=dict)
    amounts: dict[int, dict[int, FdcAmount]] = field(default_factory=dict)

    def by_description(self) -> dict[str, int]:
        return {food.description: fdc_id for fdc_id, food in self.foods.items()}


def _member(archive: zipfile.ZipFile, basename: str) -> str | None:
    for name in archive.namelist():
        if name.rsplit("/", 1)[-1] == basename:
            return name
    return None


def _rows(archive: zipfile.ZipFile, basename: str):
    member = _member(archive, basename)
    if member is None:
        return
    with archive.open(member) as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
        yield from csv.DictReader(text)


def _version_from_name(path: Path) -> str:
    match = re.search(r"(\d{4}-\d{2}(?:-\d{2})?)", path.name)
    return match.group(1) if match else "desconocida"


def load_zip(path: Path, *, keep_type: str, label: str, url: str) -> FdcDataset:
    """Parses an FDC CSV zip, keeping only foods of ``keep_type``."""
    dataset = FdcDataset(label=label, version=_version_from_name(path), url=url)
    with zipfile.ZipFile(path) as archive:
        categories = {
            row["id"]: row.get("description") or None
            for row in _rows(archive, "food_category.csv")
        }
        ndb: dict[int, str] = {}
        for source in ("sr_legacy_food.csv", "foundation_food.csv"):
            for row in _rows(archive, source):
                number = (row.get("NDB_number") or row.get("ndb_number") or "").strip()
                if number:
                    ndb[int(row["fdc_id"])] = number
        for row in _rows(archive, "food.csv"):
            if row.get("data_type") != keep_type:
                continue
            fdc_id = int(row["fdc_id"])
            category_id = (row.get("food_category_id") or "").strip()
            dataset.foods[fdc_id] = FdcFood(
                fdc_id=fdc_id,
                data_type=keep_type,
                description=(row.get("description") or "").strip(),
                category=categories.get(category_id),
                ndb_number=ndb.get(fdc_id),
            )
        for row in _rows(archive, "nutrient.csv"):
            dataset.nutrients[int(row["id"])] = FdcNutrient(
                id=int(row["id"]),
                name=(row.get("name") or "").strip(),
                unit=(row.get("unit_name") or "").strip(),
                nutrient_nbr=(row.get("nutrient_nbr") or "").strip() or None,
            )
        derivations = {
            row["id"]: ((row.get("code") or "").strip() or None, (row.get("description") or "").strip() or None)
            for row in _rows(archive, "food_nutrient_derivation.csv")
        }
        for row in _rows(archive, "food_nutrient.csv"):
            fdc_id = int(row["fdc_id"])
            if fdc_id not in dataset.foods:
                continue
            amount_text = (row.get("amount") or "").strip()
            if not amount_text:
                continue
            try:
                amount = float(amount_text)
            except ValueError:
                continue
            code, description = derivations.get((row.get("derivation_id") or "").strip(), (None, None))
            dataset.amounts.setdefault(fdc_id, {})[int(row["nutrient_id"])] = FdcAmount(
                amount=amount, derivation_code=code, derivation_description=description
            )
    return dataset


def discover_foundation_url() -> str | None:
    """Finds the newest Foundation Foods CSV zip on the FDC download page."""
    for page in DOWNLOAD_PAGE_URLS:
        try:
            html = fetch_text(page)
        except Exception as error:  # network or HTTP error: try the next page
            print(f"[fdc] no se pudo leer {page}: {error}", file=sys.stderr)
            continue
        dates = sorted(set(_FOUNDATION_RE.findall(html)), reverse=True)
        if dates:
            return f"https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_{dates[0]}.zip"
    return None


def load_sr_legacy(cache_dir: Path, url: str = SR_LEGACY_URL) -> FdcDataset:
    path = download(url, cache_dir)
    return load_zip(path, keep_type=SR_LEGACY_TYPE, label="FDC_SR", url=url)


def load_foundation(cache_dir: Path, url: str | None = None) -> FdcDataset | None:
    """Loads Foundation Foods; returns None (with a warning) if unavailable."""
    candidates = [url] if url else []
    if not url:
        discovered = discover_foundation_url()
        if discovered:
            candidates.append(discovered)
        candidates.extend(u for u in FOUNDATION_FALLBACK_URLS if u not in candidates)
    for candidate in candidates:
        try:
            path = download(candidate, cache_dir)
        except Exception as error:
            print(f"[fdc] Foundation no disponible en {candidate}: {error}", file=sys.stderr)
            continue
        return load_zip(path, keep_type=FOUNDATION_TYPE, label="FDC_FOUNDATION", url=candidate)
    print("[fdc] AVISO: se construye sin Foundation Foods.", file=sys.stderr)
    return None
