/// TOX-CHECK: deterministic label scanner (no AI).
///
/// 1. Normalise the text: lower-case, strip accents, join lines, split on
///    commas, semicolons and parentheses.
/// 2. Match each ingredient exactly against `tox_terms`.
/// 3. Map each match to its level with the evidence reference.
/// 4. No match is GRIS ("sin datos"), never VERDE.
///
/// Fluoride in oral-care products up to the limit (1500 ppm) is VERDE for
/// adults with the note for children under 6; above the limit it becomes
/// ÁMBAR. The overall result is VERDE only when every ingredient matched
/// and all are VERDE.
library;

import 'assumptions.dart';
import 'text_es.dart';

enum ToxLevel {
  verde('verde', 'VERDE'),
  ambar('ambar', 'ÁMBAR'),
  rojo('rojo', 'ROJO'),
  gris('gris', 'GRIS');

  const ToxLevel(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static ToxLevel parse(String? code) =>
      ToxLevel.values.firstWhere((l) => l.code == code, orElse: () => gris);
}

/// `tox_items.applies_to`.
enum ToxScope {
  food('food'),
  cosmetic('cosmetic'),
  both('both');

  const ToxScope(this.code);
  final String code;

  static ToxScope parse(String? code) =>
      ToxScope.values.firstWhere((s) => s.code == code, orElse: () => both);
}

/// What is being scanned.
enum ProductKind {
  food('Alimento'),
  cosmetic('Cuidado personal'),
  oralCare('Pasta o enjuague dental');

  const ProductKind(this.labelEs);
  final String labelEs;

  bool accepts(ToxScope scope) => switch (scope) {
    ToxScope.both => true,
    ToxScope.food => this == ProductKind.food,
    ToxScope.cosmetic => this != ProductKind.food,
  };
}

/// One `tox_items` row.
class ToxItem {
  const ToxItem({
    required this.id,
    required this.nameEs,
    required this.level,
    required this.rationaleEs,
    required this.evidenceRef,
    required this.scope,
    this.noteChildrenEs,
  });

  final String id;
  final String nameEs;
  final ToxLevel level;
  final String rationaleEs;
  final String evidenceRef;
  final ToxScope scope;
  final String? noteChildrenEs;

  /// Fluoride compounds (sodium fluoride, monofluorophosphate, stannous
  /// fluoride, amine fluorides).
  bool get isFluoride => id.contains('fluor');
}

/// `tox_terms` + `tox_items`, indexed for exact matching.
class ToxDictionary {
  ToxDictionary({
    required Map<String, List<String>> termToIds,
    required this.items,
  }) : _termToIds = {
         for (final e in termToIds.entries) normalizeEs(e.key): e.value,
       };

  final Map<String, List<String>> _termToIds;

  /// `tox_items` by id.
  final Map<String, ToxItem> items;

  int get termCount => _termToIds.length;
  int get itemCount => items.length;

  ToxItem? item(String id) => items[id];

  /// The item for an already-normalised [term] that applies to [kind].
  ToxItem? lookup(String term, ProductKind kind) {
    final ids = _termToIds[term];
    if (ids == null) return null;
    for (final id in ids) {
      final item = items[id];
      if (item != null && kind.accepts(item.scope)) return item;
    }
    return null;
  }
}

/// Function names printed before an ingredient ("conservante (benzoato de
/// sodio)"); alone they are not ingredients and are skipped.
const Set<String> _functionWords = {
  'ingredientes',
  'ingredients',
  'ingrediente',
  'contiene',
  'contains',
  'composicion',
  'conservante',
  'conservantes',
  'preservante',
  'preservantes',
  'colorante',
  'colorantes',
  'color',
  'emulsionante',
  'emulsionantes',
  'emulsificante',
  'emulsificantes',
  'estabilizante',
  'estabilizantes',
  'espesante',
  'espesantes',
  'antioxidante',
  'antioxidantes',
  'acidulante',
  'acidulantes',
  'regulador de acidez',
  'edulcorante',
  'edulcorantes',
  'resaltador de sabor',
  'potenciador del sabor',
  'saborizante',
  'saborizantes',
  'aromatizante',
  'humectante',
  'gelificante',
  'leudante',
  'leudantes',
  'agua',
};

/// Concentrations printed next to an ingredient ("1450 ppm f", "70 %",
/// "0,32 %"), removed before matching.
final RegExp _concentration = RegExp(
  r'\d+(?:[.,]\d+)*\s*(?:%|ppm(?:\s*(?:de\s+)?(?:f|fluor|fluoruro))?)',
);

/// Splits a label into normalised ingredient strings.
List<String> splitIngredients(String text) {
  var t = text.replaceAll(RegExp(r'-\s*\n\s*'), '').replaceAll('\n', ' ');
  t = normalizeEs(t);
  t = t.replaceFirst(
    RegExp(r'^(ingredientes|ingredients|composicion|contiene)\s*:\s*'),
    '',
  );
  final parts = t.split(RegExp(r'[,;()\[\]]|\.\s|:'));
  final out = <String>[];
  for (final raw in parts) {
    var p = raw
        .replaceAll(_concentration, '')
        .replaceAll(RegExp(r'[*•·]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    p = p.replaceAll(RegExp(r'^(y|and|e)\s+'), '');
    p = p.replaceAll(RegExp(r'[.\-]+$'), '').trim();
    if (p.isEmpty || p.length < 2) continue;
    if (_functionWords.contains(p)) continue;
    out.add(p);
  }
  return out;
}

/// Largest "NNNN ppm" value in [text], or null.
/// "1.450" and "1,450" are read as 1450 (thousands separator); "1,5"
/// as 1.5.
double? parsePpm(String text) {
  double? best;
  for (final m in RegExp(
    r'(\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?)\s*ppm',
  ).allMatches(normalizeEs(text))) {
    final raw = m.group(1)!;
    final thousands = RegExp(r'^\d{1,3}(?:[.,]\d{3})+$').hasMatch(raw);
    final v = double.parse(
      thousands
          ? raw.replaceAll(RegExp(r'[.,]'), '')
          : raw.replaceAll(',', '.'),
    );
    if (best == null || v > best) best = v;
  }
  return best;
}

class IngredientResult {
  const IngredientResult({
    required this.text,
    required this.level,
    this.item,
    this.noteEs,
  });

  /// Normalised ingredient as read from the label.
  final String text;
  final ToxLevel level;
  final ToxItem? item;

  /// Extra note (children, ppm above the limit, concentration unknown).
  final String? noteEs;

  Map<String, Object?> toJson() => {
    'text': text,
    'level': level.code,
    'tox_id': item?.id,
    'note': noteEs,
  };
}

class ToxScanResult {
  const ToxScanResult({
    required this.kind,
    required this.ingredients,
    required this.overall,
    required this.fluoridePpm,
  });

  final ProductKind kind;
  final List<IngredientResult> ingredients;
  final ToxLevel overall;
  final double? fluoridePpm;

  int count(ToxLevel level) =>
      ingredients.where((i) => i.level == level).length;

  int get unknownCount => count(ToxLevel.gris);

  String get summaryEs {
    if (ingredients.isEmpty) {
      return 'No se leyeron ingredientes. Corrige el texto o escanea de '
          'nuevo.';
    }
    final parts = <String>[
      for (final level in ToxLevel.values)
        if (count(level) > 0) '${count(level)} ${level.labelEs}',
    ];
    final head = switch (overall) {
      ToxLevel.rojo =>
        'ROJO: al menos un ingrediente está prohibido o '
            'clasificado como de alto riesgo para este tipo de producto.',
      ToxLevel.ambar =>
        'ÁMBAR: hay ingredientes permitidos con límite o '
            'con evidencia en discusión.',
      ToxLevel.verde =>
        'VERDE: todos los ingredientes reconocidos y sin '
            'alertas.',
      ToxLevel.gris =>
        unknownCount == ingredients.length
            ? 'GRIS: ningún ingrediente está en el diccionario (sin datos).'
            : 'GRIS: hay ingredientes sin datos, así que no se puede dar '
                  'VERDE.',
    };
    return '$head ${parts.join(' · ')}.';
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'overall': overall.code,
    'fluoride_ppm': fluoridePpm,
    'ingredients': [for (final i in ingredients) i.toJson()],
  };
}

/// Scans [text] for a product of [kind].
ToxScanResult toxCheck(
  String text, {
  required ProductKind kind,
  required ToxDictionary dictionary,
  required Assumptions assumptions,
}) {
  final limit = assumptions[A.fluorideToothpasteMaxPpm];
  final ppm = parsePpm(text);
  final results = <IngredientResult>[];
  final seen = <String>{};
  for (final ingredient in splitIngredients(text)) {
    if (!seen.add(ingredient)) continue;
    final item = dictionary.lookup(ingredient, kind);
    if (item == null) {
      results.add(IngredientResult(text: ingredient, level: ToxLevel.gris));
      continue;
    }
    if (item.isFluoride && kind == ProductKind.oralCare) {
      if (ppm != null && ppm > limit) {
        results.add(
          IngredientResult(
            text: ingredient,
            level: ToxLevel.ambar,
            item: item,
            noteEs:
                'Indica ${ppm.round()} ppm de flúor: supera ${limit.round()} '
                'ppm, el límite de los cosméticos en la UE. Úsala solo si '
                'te la indicó tu odontólogo.',
          ),
        );
        continue;
      }
      results.add(
        IngredientResult(
          text: ingredient,
          level: item.level,
          item: item,
          noteEs: [
            if (ppm == null)
              'La etiqueta no indica los ppm de flúor.'
            else
              '${ppm.round()} ppm de flúor (límite ${limit.round()} ppm).',
            ?item.noteChildrenEs,
          ].join(' '),
        ),
      );
      continue;
    }
    results.add(
      IngredientResult(
        text: ingredient,
        level: item.level,
        item: item,
        noteEs: item.noteChildrenEs,
      ),
    );
  }

  ToxLevel overall;
  if (results.any((r) => r.level == ToxLevel.rojo)) {
    overall = ToxLevel.rojo;
  } else if (results.any((r) => r.level == ToxLevel.ambar)) {
    overall = ToxLevel.ambar;
  } else if (results.isNotEmpty &&
      results.every((r) => r.level == ToxLevel.verde)) {
    overall = ToxLevel.verde;
  } else {
    overall = ToxLevel.gris;
  }
  return ToxScanResult(
    kind: kind,
    ingredients: List.unmodifiable(results),
    overall: overall,
    fluoridePpm: ppm,
  );
}
