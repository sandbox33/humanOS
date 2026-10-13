"""Spanish names: normalisation, nutrient names and FDC description glossary.

FDC descriptions are English and follow a comma-separated pattern
("Beans, black, mature seeds, raw"). Curated foods get proper Spanish names
from ``data/synonyms_es.csv``; every other food gets a glossary translation
so that Spanish search works across the whole database. The English
description is always kept as a searchable name too.
"""
from __future__ import annotations

import csv
import re
import unicodedata
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def strip_accents(text: str) -> str:
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def normalize(text: str) -> str:
    """Lowercase, accent-free, single-spaced text for matching."""
    return " ".join(strip_accents(text).lower().split())


# --------------------------------------------------------------- nutrients
_NUTRIENT_ES: dict[int, tuple[str, str]] = {
    1008: ("Energía", "energia"),
    1062: ("Energía (kJ)", "energia"),
    2047: ("Energía (factores Atwater generales)", "energia"),
    2048: ("Energía (factores Atwater específicos)", "energia"),
    1003: ("Proteína", "macro"),
    1004: ("Grasa total", "macro"),
    1085: ("Grasa total (NLEA)", "macro"),
    1005: ("Carbohidratos (por diferencia)", "macro"),
    1050: ("Carbohidratos (por suma)", "macro"),
    1079: ("Fibra dietética total", "macro"),
    2033: ("Fibra dietética total (AOAC 2011.25)", "macro"),
    2000: ("Azúcares totales", "azucar"),
    1063: ("Azúcares totales", "azucar"),
    1235: ("Azúcares añadidos", "azucar"),
    1009: ("Almidón", "macro"),
    1010: ("Sacarosa", "azucar"),
    1011: ("Glucosa", "azucar"),
    1012: ("Fructosa", "azucar"),
    1013: ("Lactosa", "azucar"),
    1014: ("Maltosa", "azucar"),
    1075: ("Galactosa", "azucar"),
    1051: ("Agua", "otro"),
    1007: ("Cenizas", "otro"),
    1018: ("Alcohol etílico", "otro"),
    1057: ("Cafeína", "otro"),
    1058: ("Teobromina", "otro"),
    1253: ("Colesterol", "acido_graso"),
    1258: ("Ácidos grasos saturados totales", "acido_graso"),
    1292: ("Ácidos grasos monoinsaturados totales", "acido_graso"),
    1293: ("Ácidos grasos poliinsaturados totales", "acido_graso"),
    1257: ("Ácidos grasos trans totales", "acido_graso"),
    1087: ("Calcio", "mineral"),
    1089: ("Hierro", "mineral"),
    1090: ("Magnesio", "mineral"),
    1091: ("Fósforo", "mineral"),
    1092: ("Potasio", "mineral"),
    1093: ("Sodio", "mineral"),
    1095: ("Zinc", "mineral"),
    1098: ("Cobre", "mineral"),
    1099: ("Flúor", "mineral"),
    1101: ("Manganeso", "mineral"),
    1103: ("Selenio", "mineral"),
    1104: ("Vitamina A (UI)", "vitamina"),
    1105: ("Retinol", "vitamina"),
    1106: ("Vitamina A (RAE)", "vitamina"),
    1107: ("Betacaroteno", "vitamina"),
    1108: ("Alfacaroteno", "vitamina"),
    1109: ("Vitamina E (alfa-tocoferol)", "vitamina"),
    1110: ("Vitamina D (UI)", "vitamina"),
    1114: ("Vitamina D (D2 + D3)", "vitamina"),
    1120: ("Betacriptoxantina", "vitamina"),
    1122: ("Licopeno", "vitamina"),
    1123: ("Luteína + zeaxantina", "vitamina"),
    1162: ("Vitamina C", "vitamina"),
    1165: ("Tiamina (B1)", "vitamina"),
    1166: ("Riboflavina (B2)", "vitamina"),
    1167: ("Niacina (B3)", "vitamina"),
    1170: ("Ácido pantoténico (B5)", "vitamina"),
    1175: ("Vitamina B6", "vitamina"),
    1176: ("Biotina", "vitamina"),
    1177: ("Folato total", "vitamina"),
    1178: ("Vitamina B12", "vitamina"),
    1180: ("Colina", "vitamina"),
    1185: ("Vitamina K (filoquinona)", "vitamina"),
    1186: ("Ácido fólico", "vitamina"),
    1187: ("Folato de los alimentos", "vitamina"),
    1190: ("Folato (DFE)", "vitamina"),
}

_AMINO_ES = {
    "tryptophan": "Triptófano",
    "threonine": "Treonina",
    "isoleucine": "Isoleucina",
    "leucine": "Leucina",
    "lysine": "Lisina",
    "methionine": "Metionina",
    "cystine": "Cistina",
    "cysteine": "Cisteína",
    "phenylalanine": "Fenilalanina",
    "tyrosine": "Tirosina",
    "valine": "Valina",
    "arginine": "Arginina",
    "histidine": "Histidina",
    "alanine": "Alanina",
    "aspartic acid": "Ácido aspártico",
    "glutamic acid": "Ácido glutámico",
    "glycine": "Glicina",
    "proline": "Prolina",
    "serine": "Serina",
    "hydroxyproline": "Hidroxiprolina",
}

_FATTY_PREFIX = {"SFA": "AGS", "MUFA": "AGMI", "PUFA": "AGPI", "TFA": "AGT"}

_UNITS = {
    "G": "g",
    "MG": "mg",
    "UG": "µg",
    "KCAL": "kcal",
    "KJ": "kJ",
    "IU": "UI",
    "MG_ATE": "mg ATE",
    "MG_GAE": "mg EAG",
    "SP_GR": "densidad",
}


def nutrient_name_es(fdc_id: int, english: str) -> tuple[str, str]:
    """Spanish name and category for an FDC nutrient."""
    if fdc_id in _NUTRIENT_ES:
        return _NUTRIENT_ES[fdc_id]
    key = english.strip().lower()
    if key in _AMINO_ES:
        return _AMINO_ES[key], "aminoacido"
    parts = english.split(" ", 1)
    if parts[0] in _FATTY_PREFIX:
        rest = parts[1] if len(parts) > 1 else ""
        return f"{_FATTY_PREFIX[parts[0]]} {rest}".strip(), "acido_graso"
    return english.strip(), "otro"


def unit_es(unit: str) -> str:
    return _UNITS.get(unit.strip().upper(), unit.strip().lower())


# ------------------------------------------------------------- glossary
class Glossary:
    """English → Spanish phrase table for FDC descriptions."""

    def __init__(self, pairs: dict[str, str]):
        self._pairs = {normalize(k): v for k, v in pairs.items()}
        self._max_words = max((len(k.split()) for k in self._pairs), default=1)

    @classmethod
    def load(cls, path: Path | None = None) -> "Glossary":
        path = path or DATA_DIR / "terms_es.csv"
        with open(path, encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            return cls({row["en"]: row["es"] for row in reader if row["en"].strip()})

    def _segment(self, segment: str) -> str:
        key = normalize(segment)
        if key in self._pairs:
            return self._pairs[key]
        words = re.findall(r"[\w'%/.-]+|[()]", segment)
        out: list[str] = []
        i = 0
        while i < len(words):
            for size in range(min(self._max_words, len(words) - i), 0, -1):
                phrase = normalize(" ".join(words[i : i + size]))
                if phrase in self._pairs:
                    out.append(self._pairs[phrase])
                    i += size
                    break
            else:
                out.append(words[i])
                i += 1
        text = " ".join(out)
        return text.replace("( ", "(").replace(" )", ")")

    def translate(self, description: str) -> str:
        segments = [s.strip() for s in description.split(",") if s.strip()]
        translated = [self._segment(s) for s in segments]
        text = ", ".join(t for t in translated if t)
        return text[:1].upper() + text[1:] if text else description
