import pytest

from etl.sources.ecuador_tables import HEADER, load_local_tables


def write(path, rows):
    path.write_text(",".join(HEADER) + "\n" + "\n".join(rows) + "\n", encoding="utf-8")


def test_reads_rows_with_licence_and_keeps_missing_as_absent(tmp_path):
    write(tmp_path / "msp.csv", [
        "Mote,EC,,150,4,1,30,,,,MSP Ecuador,Uso con cita,https://example.org,2012",
    ])
    foods = load_local_tables(tmp_path)
    assert len(foods) == 1
    assert foods[0].nutrients == {1008: 150.0, 1003: 4.0, 1004: 1.0, 1005: 30.0}
    assert foods[0].region == "EC"


def test_rejects_rows_without_licence(tmp_path):
    write(tmp_path / "x.csv", ["Mote,EC,,150,4,1,30,,,,MSP,,,2012"])
    with pytest.raises(ValueError):
        load_local_tables(tmp_path)


def test_missing_directory_is_empty(tmp_path):
    assert load_local_tables(tmp_path / "nope") == []
