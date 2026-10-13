import pytest

from etl.derive.nrf93 import ENCOURAGE, LIMIT, nrf93_per_100kcal


def test_hand_computed_index():
    # 200 kcal per 100 g → factor 0.5. Protein 10 g → 5 g/100 kcal → 10 %DV.
    # Vitamin C 360 mg → 180 mg/100 kcal → 200 % → capped at 100.
    # Sodium 460 mg → 230 mg/100 kcal → 10 % of 2300.
    nutrients = {1003: 10.0, 1162: 360.0, 1093: 460.0}
    value, missing = nrf93_per_100kcal(nutrients, 200.0)
    assert value == pytest.approx(10.0 + 100.0 - 10.0)
    assert 1079 in missing and 1235 in missing
    assert 1003 not in missing


def test_missing_components_are_dropped_not_zeroed():
    value, missing = nrf93_per_100kcal({}, 100.0)
    assert value == 0.0
    assert len(missing) == len(ENCOURAGE) + len(LIMIT)


def test_without_energy_there_is_no_index():
    value, _ = nrf93_per_100kcal({1003: 10.0}, None)
    assert value is None
    assert nrf93_per_100kcal({1003: 10.0}, 0.0)[0] is None


def test_daily_values_are_fda_2016():
    assert ENCOURAGE[1003] == 50.0 and ENCOURAGE[1079] == 28.0 and ENCOURAGE[1092] == 4700.0
    assert LIMIT == {1258: 20.0, 1235: 50.0, 1093: 2300.0}
