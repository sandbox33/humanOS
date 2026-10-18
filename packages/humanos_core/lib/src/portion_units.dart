/// Portion units: the user logs in units ("3 huevos", "2 cucharadas de
/// miel"), the database stores grams. Every unit carries its source and can
/// be edited by the user (a user value overrides the reference one).
///
/// Also the Tier 0 parser for food logged by text: "comí 3 huevos",
/// "2 cdas de miel", "media arepa", "250 g de arroz".
library;

import 'format_es.dart';
import 'text_es.dart';

/// One `portion_units` row (reference) or a user override.
class PortionUnit {
  const PortionUnit({
    required this.foodId,
    required this.unitEs,
    required this.grams,
    required this.source,
    this.userEdited = false,
  });

  final int foodId;

  /// Singular Spanish unit: "unidad", "cucharada", "unidad mediana".
  final String unitEs;
  final double grams;
  final String source;
  final bool userEdited;
}

/// Grams for [qty] of [unit]. Null when the quantity is not positive.
double? gramsForUnits(double qty, PortionUnit unit) {
  if (!qty.isFinite || qty <= 0 || unit.grams <= 0) return null;
  return qty * unit.grams;
}

/// "3 unidades (150 g)", "1 cucharada (21 g)", "½ unidad (25 g)".
String formatUnits(double qty, PortionUnit unit) {
  final grams = gramsForUnits(qty, unit);
  final q = _formatQty(qty);
  final fraction = (qty - 0.5).abs() < 1e-9 || (qty - 0.25).abs() < 1e-9;
  final label = fraction ? unit.unitEs : pluralizeEs(unit.unitEs, qty);
  if (grams == null) return '$q $label';
  return '$q $label (${formatWhole(grams)} g)';
}

String _formatQty(double qty) {
  if ((qty - 0.5).abs() < 1e-9) return '½';
  if ((qty - 0.25).abs() < 1e-9) return '¼';
  if ((qty - qty.roundToDouble()).abs() < 1e-9) return qty.round().toString();
  return formatDecimal(qty, decimals: 2).replaceFirst(RegExp(r',?0+$'), '');
}

/// The unit to use for a food: the user's edited value first, then the
/// first reference unit. Null when the food has no units (log in grams).
PortionUnit? preferredUnit(List<PortionUnit> units) {
  if (units.isEmpty) return null;
  for (final u in units) {
    if (u.userEdited) return u;
  }
  return units.first;
}

/// Kind of unit typed by the user.
enum TypedUnit {
  grams,
  unit,
  tablespoon,
  teaspoon,
  cup,
  slice,
  small,
  medium,
  large,
}

const Map<String, TypedUnit> _unitWords = {
  'g': TypedUnit.grams,
  'gr': TypedUnit.grams,
  'grs': TypedUnit.grams,
  'gramo': TypedUnit.grams,
  'gramos': TypedUnit.grams,
  'unidad': TypedUnit.unit,
  'unidades': TypedUnit.unit,
  'u': TypedUnit.unit,
  'cucharada': TypedUnit.tablespoon,
  'cucharadas': TypedUnit.tablespoon,
  'cda': TypedUnit.tablespoon,
  'cdas': TypedUnit.tablespoon,
  'cucharadita': TypedUnit.teaspoon,
  'cucharaditas': TypedUnit.teaspoon,
  'cdta': TypedUnit.teaspoon,
  'cdtas': TypedUnit.teaspoon,
  'taza': TypedUnit.cup,
  'tazas': TypedUnit.cup,
  'rebanada': TypedUnit.slice,
  'rebanadas': TypedUnit.slice,
  'tajada': TypedUnit.slice,
  'tajadas': TypedUnit.slice,
  'pequeno': TypedUnit.small,
  'pequena': TypedUnit.small,
  'pequenos': TypedUnit.small,
  'pequenas': TypedUnit.small,
  'chico': TypedUnit.small,
  'mediano': TypedUnit.medium,
  'mediana': TypedUnit.medium,
  'medianos': TypedUnit.medium,
  'medianas': TypedUnit.medium,
  'grande': TypedUnit.large,
  'grandes': TypedUnit.large,
};

/// Words that start a food log ("comí", "desayuné", "me comí").
const Set<String> _logVerbs = {
  'comi',
  'me',
  'desayune',
  'almorce',
  'cene',
  'meriende',
  'tome',
  'bebi',
  'registra',
  'registrar',
  'anota',
  'anotar',
  'agrega',
  'agregar',
  'log',
};

/// A food logged by text, before resolving the food name against the
/// reference database.
class TextIntake {
  const TextIntake({
    required this.quantity,
    required this.unit,
    required this.foodQuery,
  });

  final double quantity;

  /// Null when the text gave only a count ("3 huevos" = 3 units).
  final TypedUnit? unit;

  /// Normalised words that name the food ("huevos", "miel", "arroz").
  final String foodQuery;

  bool get isGrams => unit == TypedUnit.grams;
}

/// Parses "comí 3 huevos", "2 cdas de miel", "media arepa mediana",
/// "250 g de arroz", "un plátano grande". Null when no quantity and food
/// are found.
TextIntake? parseTextIntake(String text) {
  var tokens = tokenizeEs(text);
  while (tokens.isNotEmpty && _logVerbs.contains(tokens.first)) {
    tokens = tokens.sublist(1);
  }
  if (tokens.isEmpty) return null;

  double? qty;
  var i = 0;
  // "1 y media", "dos y medio" → 1.5, 2.5
  final first = parseQuantityEs(tokens[0]);
  if (first != null) {
    qty = first;
    i = 1;
    if (tokens.length > 2 &&
        tokens[1] == 'y' &&
        (tokens[2] == 'media' || tokens[2] == 'medio')) {
      qty = qty + 0.5;
      i = 3;
    }
  }
  // "media docena de huevos"
  if (i < tokens.length && tokens[i] == 'docena') {
    qty = (qty ?? 1) * 12;
    i++;
  }
  // "250g" written together
  final glued = RegExp(r'^(\d+(?:[.,]\d+)?)(g|gr|grs)$').firstMatch(tokens[0]);
  if (qty == null && glued != null) {
    qty = double.parse(glued.group(1)!.replaceAll(',', '.'));
    tokens = ['g', ...tokens.sublist(1)];
    i = 0;
  }
  if (qty == null) return null;

  TypedUnit? unit;
  if (i < tokens.length && _unitWords.containsKey(tokens[i])) {
    unit = _unitWords[tokens[i]];
    i++;
  }
  if (i < tokens.length && tokens[i] == 'de') i++;
  final rest = <String>[];
  for (var k = i; k < tokens.length; k++) {
    final t = tokens[k];
    final size = _unitWords[t];
    if (size == TypedUnit.small ||
        size == TypedUnit.medium ||
        size == TypedUnit.large) {
      unit ??= size;
      continue;
    }
    if (t == 'de' && rest.isEmpty) continue;
    rest.add(t);
  }
  if (rest.isEmpty) return null;
  return TextIntake(quantity: qty, unit: unit, foodQuery: rest.join(' '));
}

/// Resolves a [TextIntake] against the units of the matched food. Returns
/// grams and the unit used, or null when the unit cannot be converted
/// without inventing a weight.
({double grams, PortionUnit? unit})? resolveIntake(
  TextIntake intake,
  List<PortionUnit> units,
) {
  if (intake.isGrams) return (grams: intake.quantity, unit: null);
  if (units.isEmpty) return null;
  PortionUnit? pick(bool Function(String u) test) {
    for (final u in units) {
      if (test(foldDiacritics(u.unitEs))) return u;
    }
    return null;
  }

  final PortionUnit? chosen = switch (intake.unit) {
    TypedUnit.tablespoon => pick((u) => u.startsWith('cucharada')),
    TypedUnit.teaspoon => pick((u) => u.startsWith('cucharadita')),
    TypedUnit.cup => pick((u) => u.startsWith('taza')),
    TypedUnit.slice => pick(
      (u) => u.startsWith('rebanada') || u.startsWith('tajada'),
    ),
    TypedUnit.small => pick((u) => u.contains('pequen') || u.contains('chic')),
    TypedUnit.medium => pick((u) => u.contains('median')),
    TypedUnit.large => pick((u) => u.contains('grande')),
    TypedUnit.unit || null =>
      pick((u) => u.startsWith('unidad') && !u.contains(' ')) ??
          pick((u) => u.contains('median')) ??
          pick((u) => u.startsWith('unidad')),
    TypedUnit.grams => null,
  };
  if (chosen == null) return null;
  final grams = gramsForUnits(intake.quantity, chosen);
  if (grams == null) return null;
  return (grams: grams, unit: chosen);
}
