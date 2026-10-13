"""Nutrient Rich Foods index NRF9.3 per 100 kcal.

NRF9.3 = Σ %DV of 9 nutrients to encourage (each capped at 100 %)
       − Σ %MRV of 3 nutrients to limit, both per 100 kcal
(Fulgoni VL, Keast DR, Drewnowski A. J Nutr 2009;139:1549–1554).

Reference amounts are the US FDA Daily Values of the 2016 labelling rule
(21 CFR 101.9). A component without data is *dropped*, never imputed as
zero; the missing components are returned so confidence can be lowered.
SR Legacy has no "added sugars", so that limit usually drops out.
"""
from __future__ import annotations

from typing import Mapping

# FDC nutrient id → (daily value, unit) for nutrients to encourage.
ENCOURAGE = {
    1003: 50.0,  # protein, g
    1079: 28.0,  # dietary fibre, g
    1106: 900.0,  # vitamin A, µg RAE
    1162: 90.0,  # vitamin C, mg
    1109: 15.0,  # vitamin E (alpha-tocopherol), mg
    1087: 1300.0,  # calcium, mg
    1089: 18.0,  # iron, mg
    1092: 4700.0,  # potassium, mg
    1090: 420.0,  # magnesium, mg
}
# FDC nutrient id → maximum recommended value for nutrients to limit.
LIMIT = {
    1258: 20.0,  # saturated fat, g
    1235: 50.0,  # added sugars, g
    1093: 2300.0,  # sodium, mg
}


def nrf93_per_100kcal(
    nutrients: Mapping[int, float], energy_kcal: float | None
) -> tuple[float | None, list[int]]:
    """Returns (index, missing nutrient ids). Index is None without energy."""
    if energy_kcal is None or energy_kcal <= 0:
        return None, sorted([*ENCOURAGE, *LIMIT])
    factor = 100.0 / energy_kcal
    missing: list[int] = []
    encourage = 0.0
    for nutrient_id, daily_value in ENCOURAGE.items():
        amount = nutrients.get(nutrient_id)
        if amount is None:
            missing.append(nutrient_id)
            continue
        encourage += min(100.0, amount * factor / daily_value * 100.0)
    limit = 0.0
    for nutrient_id, maximum in LIMIT.items():
        amount = nutrients.get(nutrient_id)
        if amount is None:
            missing.append(nutrient_id)
            continue
        limit += amount * factor / maximum * 100.0
    return encourage - limit, missing
