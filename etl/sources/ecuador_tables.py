"""Optional local food tables (e.g. MSP Ecuador 2012, USFQ 2021).

They are used only when the owner drops CSV exports into
``etl/data/local/``. Each file must use the header below and state its
source and licence on every row; files without a licence are rejected so
nothing unverified is published. Rows may point to an FDC food with
``proxy_fdc_id`` (stored as ``foods.proxy_of``). Empty cells stay NULL.

Header::

    name_es,region,proxy_fdc_id,kcal_100g,protein_100g,fat_100g,carb_100g,
    fiber_100g,sugars_100g,sodium_mg_100g,source_name,source_license,
    source_url,source_version
"""
from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

HEADER = (
    "name_es",
    "region",
    "proxy_fdc_id",
    "kcal_100g",
    "protein_100g",
    "fat_100g",
    "carb_100g",
    "fiber_100g",
    "sugars_100g",
    "sodium_mg_100g",
    "source_name",
    "source_license",
    "source_url",
    "source_version",
)
REGIONS = {"EC", "VE", "CO", "GEN"}

# Column → FDC nutrient id used for the stored value.
NUTRIENT_COLUMNS = {
    "kcal_100g": 1008,
    "protein_100g": 1003,
    "fat_100g": 1004,
    "carb_100g": 1005,
    "fiber_100g": 1079,
    "sugars_100g": 2000,
    "sodium_mg_100g": 1093,
}


@dataclass(frozen=True)
class LocalFood:
    file_code: str
    name_es: str
    region: str
    proxy_fdc_id: int | None
    nutrients: dict[int, float]
    source_name: str
    source_license: str
    source_url: str
    source_version: str


def _value(text: str) -> float | None:
    text = (text or "").strip().replace(",", ".")
    if not text:
        return None
    value = float(text)
    if value < 0:
        raise ValueError(f"Valor negativo: {text}")
    return value


def load_local_tables(directory: Path) -> list[LocalFood]:
    """Reads every ``*.csv`` in ``directory``. Raises on malformed files."""
    foods: list[LocalFood] = []
    if not directory.exists():
        return foods
    for path in sorted(directory.glob("*.csv")):
        with open(path, encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            missing = [column for column in HEADER if column not in (reader.fieldnames or [])]
            if missing:
                raise ValueError(f"{path.name}: faltan columnas {missing}")
            for line, row in enumerate(reader, start=2):
                name = (row["name_es"] or "").strip()
                if not name:
                    continue
                license_text = (row["source_license"] or "").strip()
                if not license_text:
                    raise ValueError(f"{path.name}:{line}: falta source_license")
                region = (row["region"] or "GEN").strip().upper()
                if region not in REGIONS:
                    raise ValueError(f"{path.name}:{line}: región inválida {region}")
                proxy = (row["proxy_fdc_id"] or "").strip()
                nutrients = {}
                for column, nutrient_id in NUTRIENT_COLUMNS.items():
                    value = _value(row[column])
                    if value is not None:
                        nutrients[nutrient_id] = value
                foods.append(
                    LocalFood(
                        file_code=path.stem,
                        name_es=name,
                        region=region,
                        proxy_fdc_id=int(proxy) if proxy else None,
                        nutrients=nutrients,
                        source_name=(row["source_name"] or path.stem).strip(),
                        source_license=license_text,
                        source_url=(row["source_url"] or "").strip(),
                        source_version=(row["source_version"] or "").strip() or "sin versión",
                    )
                )
    return foods
