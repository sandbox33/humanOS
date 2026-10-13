from etl.derive.names_es import Glossary, normalize, nutrient_name_es, strip_accents, unit_es


def test_normalize():
    assert normalize("  Plátano   MADURO ") == "platano maduro"
    assert strip_accents("fréjol") == "frejol"


def test_glossary_translates_segments_and_phrases():
    g = Glossary.load()
    assert g.translate("Beans, black, mature seeds, raw") == "Fréjoles, negro, semillas maduras, crudo"
    assert g.translate("Chicken, broilers or fryers, breast, meat only, raw").startswith("Pollo, pollo de engorde, pechuga")
    assert g.translate("Rice, white, long-grain, regular, enriched, cooked").startswith("Arroz, blanco, grano largo")


def test_unknown_words_are_kept():
    g = Glossary({"raw": "crudo"})
    assert g.translate("Zorblax, raw") == "Zorblax, crudo"


def test_nutrient_names():
    assert nutrient_name_es(1003, "Protein") == ("Proteína", "macro")
    assert nutrient_name_es(9999, "Leucine") == ("Leucina", "aminoacido")
    assert nutrient_name_es(9998, "PUFA 18:2") == ("AGPI 18:2", "acido_graso")
    assert nutrient_name_es(9997, "Something new") == ("Something new", "otro")
    assert unit_es("UG") == "µg" and unit_es("KCAL") == "kcal"


def test_glossary_has_no_empty_translations():
    import csv
    from etl.derive.names_es import DATA_DIR

    with open(DATA_DIR / "terms_es.csv", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert rows
    assert all(r["en"].strip() and r["es"].strip() for r in rows)
