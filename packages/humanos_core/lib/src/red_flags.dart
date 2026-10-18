/// Red-flag detector for free text (assistant, BUZÓN, notes). Chest pain,
/// fainting, blood, breathing difficulty or heat stroke always route to
/// "busca atención médica", before any other answer. The app never
/// diagnoses.
library;

import 'text_es.dart';

enum RedFlagKind {
  chestPain('dolor en el pecho'),
  fainting('desmayo'),
  blood('sangre'),
  breathing('dificultad para respirar'),
  heatStroke('golpe de calor');

  const RedFlagKind(this.labelEs);
  final String labelEs;
}

/// Folded patterns per kind. Matched on word boundaries.
const Map<RedFlagKind, List<String>> _patterns = {
  RedFlagKind.chestPain: [
    r'dolor (en|de|del) (el )?pecho',
    r'(opresion|presion|apreton) (en|del) (el )?pecho',
    r'me duele el pecho',
    r'pecho apretado',
  ],
  RedFlagKind.fainting: [
    r'desmay\w*',
    r'perdi el (conocimiento|sentido)',
    r'me (desvaneci|desmaye)',
  ],
  RedFlagKind.blood: [r'sangr\w*', r'(vomito|heces|orina|tos) con sangre'],
  RedFlagKind.breathing: [
    r'dificultad para respirar',
    r'no puedo respirar',
    r'me falta el aire',
    r'falta de aire',
    r'me ahogo',
  ],
  RedFlagKind.heatStroke: [r'golpe de calor', r'insolacion', r'deje de sudar'],
};

final Map<RedFlagKind, List<RegExp>> _compiled = {
  for (final e in _patterns.entries)
    e.key: [for (final p in e.value) RegExp('\\b$p\\b')],
};

/// The fixed answer. Ecuador's emergency number is ECU 911.
const String redFlagMessageEs =
    'Lo que describes puede ser serio. Busca atención médica ahora. Si es '
    'una emergencia, llama al 911 (ECU 911). Esta app no puede evaluarlo.';

class RedFlagResult {
  const RedFlagResult(this.kinds);
  final List<RedFlagKind> kinds;

  bool get any => kinds.isNotEmpty;
  String? get messageEs => any ? redFlagMessageEs : null;
}

/// Kinds of red flag found in [text] (empty when none).
RedFlagResult detectRedFlags(String text) {
  final folded = normalizeEs(text);
  final kinds = <RedFlagKind>[
    for (final e in _compiled.entries)
      if (e.value.any((r) => r.hasMatch(folded))) e.key,
  ];
  return RedFlagResult(List.unmodifiable(kinds));
}
