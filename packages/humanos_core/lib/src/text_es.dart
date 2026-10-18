/// Spanish text helpers shared by search, Tox-Check, the Tier 0 assistant,
/// MENTE and the red-flag detector: diacritic folding, normalisation,
/// tokenisation and number words ("tres", "media", "1,5").
library;

const Map<String, String> _fold = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ş': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ř': 'r',
  'ł': 'l',
  'đ': 'd',
  'ď': 'd',
  'ť': 't',
  'ğ': 'g',
  'æ': 'ae',
  'œ': 'oe',
  'ß': 'ss',
};

/// Lower-cases [text] and removes diacritics (á → a, ñ → n, ü → u), the
/// same folding as SQLite FTS5 `unicode61 remove_diacritics 2`.
String foldDiacritics(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_fold[char] ?? char);
  }
  return out.toString();
}

/// Folded text with runs of whitespace collapsed and the ends trimmed.
String normalizeEs(String text) =>
    foldDiacritics(text).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Words and numbers of [text] after [normalizeEs]. Decimal numbers keep
/// their separator ("1,5" stays one token); everything else that is not a
/// letter or digit splits tokens.
List<String> tokenizeEs(String text) => RegExp(
  r'\d+(?:[.,]\d+)?|[a-z0-9]+',
).allMatches(normalizeEs(text)).map((m) => m.group(0)!).toList();

/// Spanish number words (folded) and their values.
const Map<String, double> numberWordsEs = {
  'cero': 0,
  'un': 1,
  'uno': 1,
  'una': 1,
  'dos': 2,
  'tres': 3,
  'cuatro': 4,
  'cinco': 5,
  'seis': 6,
  'siete': 7,
  'ocho': 8,
  'nueve': 9,
  'diez': 10,
  'once': 11,
  'doce': 12,
  'trece': 13,
  'catorce': 14,
  'quince': 15,
  'dieciseis': 16,
  'diecisiete': 17,
  'dieciocho': 18,
  'diecinueve': 19,
  'veinte': 20,
  'treinta': 30,
  'cuarenta': 40,
  'cincuenta': 50,
  'cien': 100,
  'medio': 0.5,
  'media': 0.5,
  'docena': 12,
};

/// Parses a quantity token: digits ("3", "1,5", "1.5"), a fraction ("1/2")
/// or a number word ("tres", "media"). Returns null for anything else.
double? parseQuantityEs(String token) {
  final t = normalizeEs(token);
  final fraction = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (fraction != null) {
    final den = int.parse(fraction.group(2)!);
    if (den == 0) return null;
    return int.parse(fraction.group(1)!) / den;
  }
  if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t)) {
    return double.parse(t.replaceAll(',', '.'));
  }
  return numberWordsEs[t];
}

/// Short function words ignored when matching intents and food names.
const Set<String> stopwordsEs = {
  'a',
  'al',
  'algo',
  'con',
  'como',
  'cual',
  'cuanto',
  'cuanta',
  'cuantos',
  'cuantas',
  'de',
  'del',
  'el',
  'en',
  'es',
  'esta',
  'este',
  'esto',
  'la',
  'las',
  'le',
  'lo',
  'los',
  'me',
  'mi',
  'mis',
  'muy',
  'para',
  'por',
  'que',
  'se',
  'si',
  'sin',
  'su',
  'sus',
  'te',
  'tu',
  'tus',
  'un',
  'una',
  'unas',
  'unos',
  'y',
  'o',
  'u',
  'ya',
  'hoy',
  'ahora',
};

/// Tokens of [text] without [stopwordsEs].
List<String> contentTokensEs(String text) =>
    tokenizeEs(text).where((t) => !stopwordsEs.contains(t)).toList();

/// Very small Spanish plural for display: "1 unidad", "3 unidades",
/// "2 cucharadas". [singular] is returned unchanged for |qty| == 1.
String pluralizeEs(String singular, double qty) {
  if ((qty - 1).abs() < 1e-9) return singular;
  final s = singular.trim();
  if (s.isEmpty) return s;
  final space = s.indexOf(' ');
  if (space > 0) {
    // "cucharada sopera" → "cucharadas soperas"; "taza de arroz" keeps
    // the complement after "de".
    final head = s.substring(0, space);
    final tail = s.substring(space + 1);
    if (tail.startsWith('de ')) return '${pluralizeEs(head, qty)} $tail';
    return '${pluralizeEs(head, qty)} ${pluralizeEs(tail, qty)}';
  }
  final last = s[s.length - 1];
  if ('aeiouáéó'.contains(last)) return '${s}s';
  if (last == 'z') return '${s.substring(0, s.length - 1)}ces';
  if (s.endsWith('ón')) return '${s.substring(0, s.length - 2)}ones';
  return '${s}es';
}
