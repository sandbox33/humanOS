/// Accent-insensitive text helpers for Spanish search.
library;

const _fold = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e',
  'ê': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o',
  'ö': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n',
  'ç': 'c',
};

/// Lowercase without accents ("Plátano" → "platano").
String foldText(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_fold[ch] ?? ch);
  }
  return buffer.toString();
}

/// FTS5 query: every word as a prefix term, quotes stripped
/// ("plát" → `"plat"*`). Empty when the input has no letters or digits.
String ftsQuery(String input) {
  final words = RegExp(r'[\p{L}\p{N}]+', unicode: true)
      .allMatches(foldText(input))
      .map((m) => m.group(0)!)
      .where((w) => w.isNotEmpty)
      .toList();
  return words.map((w) => '"$w"*').join(' ');
}
