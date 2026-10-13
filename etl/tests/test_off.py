import pytest

from etl.sources import off

from .conftest import FIXTURE_OFF_LINES, OFF_HEADER, off_line


def test_keeps_only_target_countries_with_nutrition():
    products = list(off.parse_lines(FIXTURE_OFF_LINES))
    codes = {p.barcode for p in products}
    assert "3000000000001" not in codes  # France
    assert "7861000000048" not in codes  # no nutrition at all
    assert {"7590000000001", "7861000000017", "7861000000024", "7861000000031"} <= codes


def test_implausible_values_become_null_and_sodium_is_mg():
    products = {p.barcode: p for p in off.parse_lines(FIXTURE_OFF_LINES)}
    impossible = products["7861000000055"]
    assert impossible.kcal_100g is None
    assert impossible.protein_100g == 10.0
    assert products["7861000000017"].sodium_mg_100g == 400.0


def test_countries_and_nova_from_off():
    products = {p.barcode: p for p in off.parse_lines(FIXTURE_OFF_LINES)}
    assert products["7590000000001"].countries == "en:venezuela,en:colombia"
    assert products["7861000000031"].nova == 4
    assert products["7590000000001"].popularity == 50


def test_duplicates_and_bad_barcodes_are_skipped():
    lines = [
        "\t".join(OFF_HEADER) + "\n",
        off_line(code="7861000000062", product_name="A", countries_tags="en:ecuador", **{"proteins_100g": "1"}),
        off_line(code="7861000000062", product_name="A bis", countries_tags="en:ecuador", **{"proteins_100g": "1"}),
        off_line(code="abc", product_name="B", countries_tags="en:ecuador", **{"proteins_100g": "1"}),
    ]
    products = list(off.parse_lines(lines))
    assert [p.name for p in products] == ["A"]


def test_off_download_failure_is_fatal_unless_optional(tmp_path):
    from etl.build_reference_db import load_off

    def failing(url, cache):
        raise RuntimeError("sin red")

    products, version = load_off("https://example.invalid/x.csv.gz", tmp_path, optional=True, downloader=failing)
    assert products == [] and version is None
    with pytest.raises(RuntimeError):
        load_off("https://example.invalid/x.csv.gz", tmp_path, optional=False, downloader=failing)
