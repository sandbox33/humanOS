"""Energy resolution and energy density (kcal per gram)."""
from __future__ import annotations

from typing import Mapping

# FDC energy nutrients in order of preference: SR Legacy reports 1008;
# Foundation Foods often reports only the Atwater variants.
ENERGY_IDS = (1008, 2048, 2047)


def energy_kcal(nutrients: Mapping[int, float]) -> float | None:
    """Energy per 100 g in kcal as published, or None when absent."""
    for nutrient_id in ENERGY_IDS:
        value = nutrients.get(nutrient_id)
        if value is not None:
            return value
    return None


def energy_density_kcal_g(kcal_per_100g: float | None) -> float | None:
    if kcal_per_100g is None or kcal_per_100g < 0:
        return None
    return kcal_per_100g / 100.0
