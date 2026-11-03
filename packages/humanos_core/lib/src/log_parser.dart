/// Phrase → one record of a fixed schema, for the local assistant.
///
/// The assistant never chats and never advises: it turns a phrase into a
/// record, the app shows it in a pre-filled form and nothing is written
/// until the user confirms. Rules come first ([parseByRules]); the
/// on-device model is asked only when they find nothing, and its JSON goes
/// through [validateLogJson] like any other input.
///
/// Schema (`accion` plus, per action):
/// * `work_entry`: `label`?, `minutes`?, `start`? and `end`? (`HH:MM`),
///   `rate_cents`? (per hour), `total_cents`?; needs minutes, start + end
///   or a total, and a rate needs hours;
/// * `weight`: `kg` (20–300);
/// * `food_log`: `food`, `grams`? (> 0), `quantity`? (> 0);
/// * `state`: `value` (1–5);
/// * `thermos`: `moment` (`antes` | `pausa`).
library;

import 'dart:convert';

import 'money.dart';
import 'text_es.dart';

enum LogAction {
  workEntry('work_entry', 'Trabajo'),
  weight('weight', 'Peso'),
  foodLog('food_log', 'Comida'),
  state('state', 'Estado'),
  thermos('thermos', 'Termo');

  const LogAction(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static LogAction? parse(Object? code) {
    for (final a in values) {
      if (a.code == code) return a;
    }
    return null;
  }
}

/// One record of the schema. [fields] hold only JSON scalars.
class LogIntent {
  const LogIntent(this.action, this.fields);

  final LogAction action;
  final Map<String, Object> fields;

  Map<String, Object> toJson() => {'accion': action.code, ...fields};

  @override
  bool operator ==(Object other) =>
      other is LogIntent &&
      other.action == action &&
      other.fields.length == fields.length &&
      fields.entries.every((e) => other.fields[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    action,
    Object.hashAllUnordered(
      fields.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => jsonEncode(toJson());
}

class LogValidation {
  const LogValidation(this.intent, this.problemsEs);

  /// The record when every rule of the schema holds.
  final LogIntent? intent;
  final List<String> problemsEs;

  bool get ok => intent != null && problemsEs.isEmpty;
}

const _allowed = {
  LogAction.workEntry: {
    'label',
    'minutes',
    'start',
    'end',
    'rate_cents',
    'total_cents',
  },
  LogAction.weight: {'kg'},
  LogAction.foodLog: {'food', 'grams', 'quantity'},
  LogAction.state: {'value'},
  LogAction.thermos: {'moment'},
};

final _clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.round();
  return null;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Checks [json] against the schema. Unknown actions, unknown fields, wrong
/// types and out-of-range values are problems; nothing is guessed.
LogValidation validateLogJson(Object? json) {
  if (json is! Map) {
    return const LogValidation(null, ['La respuesta no es un objeto JSON.']);
  }
  final action = LogAction.parse(json['accion']);
  if (action == null) return const LogValidation(null, ['Acción desconocida.']);
  final problems = <String>[];
  final fields = <String, Object>{};
  for (final entry in json.entries) {
    final key = entry.key;
    if (key == 'accion' || entry.value == null) continue;
    if (key is! String || !_allowed[action]!.contains(key)) {
      problems.add('Campo no permitido: $key.');
    }
  }
  void text(String key, {bool required = false}) {
    final v = json[key];
    if (v == null) {
      if (required) problems.add('Falta $key.');
      return;
    }
    if (v is! String || v.trim().isEmpty) {
      problems.add('$key debe ser texto.');
      return;
    }
    fields[key] = v.trim();
  }

  void integer(String key, int min, int max, {bool required = false}) {
    final raw = json[key];
    if (raw == null) {
      if (required) problems.add('Falta $key.');
      return;
    }
    final v = _int(raw);
    if (v == null || v < min || v > max) {
      problems.add('$key fuera de rango.');
      return;
    }
    fields[key] = v;
  }

  void number(String key, double min, double max, {bool required = false}) {
    final raw = json[key];
    if (raw == null) {
      if (required) problems.add('Falta $key.');
      return;
    }
    final v = _num(raw);
    if (v == null || v < min || v > max) {
      problems.add('$key fuera de rango.');
      return;
    }
    fields[key] = v;
  }

  switch (action) {
    case LogAction.workEntry:
      text('label');
      integer('minutes', 1, 24 * 60);
      for (final key in ['start', 'end']) {
        final v = json[key];
        if (v == null) continue;
        if (v is String && _clock.hasMatch(v)) {
          fields[key] = v;
        } else {
          problems.add('$key debe ser HH:MM.');
        }
      }
      integer('rate_cents', 0, 1000000);
      integer('total_cents', 0, 100000000);
      final hasRange = fields.containsKey('start') && fields.containsKey('end');
      if (fields.containsKey('start') != fields.containsKey('end')) {
        problems.add('Faltan inicio y fin juntos.');
      }
      final hasHours = fields.containsKey('minutes') || hasRange;
      if (!hasHours && !fields.containsKey('total_cents')) {
        problems.add('Faltan las horas o el total.');
      }
      if (fields.containsKey('rate_cents') && !hasHours) {
        problems.add('Una tarifa necesita horas.');
      }
    case LogAction.weight:
      number('kg', 20, 300, required: true);
    case LogAction.foodLog:
      text('food', required: true);
      number('grams', 0.1, 5000);
      number('quantity', 0.1, 100);
    case LogAction.state:
      integer('value', 1, 5, required: true);
    case LogAction.thermos:
      final v = json['moment'];
      if (v == 'antes' || v == 'pausa') {
        fields['moment'] = v as String;
      } else {
        problems.add('El momento del termo es «antes» o «pausa».');
      }
  }
  return LogValidation(
    problems.isEmpty ? LogIntent(action, fields) : null,
    problems,
  );
}

/// The first balanced `{…}` of a model's output, decoded; null when there
/// is none or it is not JSON.
Object? extractJsonObject(String output) {
  final start = output.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  for (var i = start; i < output.length; i++) {
    final c = output[i];
    if (inString) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') inString = true;
    if (c == '{') depth++;
    if (c == '}' && --depth == 0) {
      try {
        return jsonDecode(output.substring(start, i + 1));
      } on FormatException {
        return null;
      }
    }
  }
  return null;
}

// ------------------------------------------------------------------ rules

/// Lower-case and diacritic folding that keeps every index, so a match in
/// the folded text slices the user's own spelling from the original.
String _fold(String text) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunaeiouun';
  final out = StringBuffer();
  for (final unit in text.split('')) {
    final i = from.indexOf(unit);
    final lower = unit.toLowerCase();
    out.write(i >= 0 ? to[i] : (lower.length == 1 ? lower : unit));
  }
  return out.toString();
}

const _numberWord =
    r'(?:\d+(?:[.,]\d+)?|un|una|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|media|medio)';

double? _quantity(String token) => parseQuantityEs(token);

String _two(int v) => v.toString().padLeft(2, '0');

/// Start and end of group [g] of [m] in [text] (Dart gives only the whole
/// match's offsets; the group is the first equal slice inside the match).
({int start, int end}) _groupSpan(String text, RegExpMatch m, int g) {
  final value = m.group(g)!;
  final start = text.indexOf(value, m.start);
  return (start: start, end: start + value.length);
}

/// Minutes of "4 horas", "4,5 h", "cuatro horas y media", "3h30",
/// "media hora", "45 min"; null when no duration is found.
int? _duration(String t) {
  final compact = RegExp(r'\b(\d{1,2})\s*h\s*(\d{2})\b').firstMatch(t);
  if (compact != null) {
    return int.parse(compact.group(1)!) * 60 + int.parse(compact.group(2)!);
  }
  if (RegExp(r'\bmedia hora\b').hasMatch(t)) return 30;
  final hours = RegExp(
    '\\b($_numberWord)\\s*(?:h|hr|hrs|hora|horas)\\b(?:\\s*y\\s*(media|cuarto|\\d{1,2}\\s*(?:min|minutos)))?',
  ).firstMatch(t);
  if (hours != null) {
    final h = _quantity(hours.group(1)!);
    if (h == null) return null;
    var minutes = (h * 60).round();
    final extra = hours.group(2);
    if (extra == 'media') minutes += 30;
    if (extra == 'cuarto') minutes += 15;
    final m = extra == null ? null : RegExp(r'\d+').firstMatch(extra);
    if (m != null) minutes += int.parse(m.group(0)!);
    return minutes;
  }
  final mins = RegExp(r'\b(\d{1,3})\s*(?:min|minutos)\b').firstMatch(t);
  return mins == null ? null : int.parse(mins.group(1)!);
}

/// "de 8 a 4" (08:00–16:00), "de 22 a 6" (across midnight), "de 7:30 a
/// 15:45". A short end before the start that fits the afternoon is read
/// as afternoon; the form shows it for confirmation.
({String start, String end, int from, int to})? _range(String t) {
  final m = RegExp(
    r'\bde\s+(\d{1,2})(?::(\d{2}))?\s*(?:am|pm)?\s+(?:a|hasta)\s+(?:las\s+)?(\d{1,2})(?::(\d{2}))?\b',
  ).firstMatch(t);
  if (m == null) return null;
  var sh = int.parse(m.group(1)!), eh = int.parse(m.group(3)!);
  final sm = int.parse(m.group(2) ?? '0'), em = int.parse(m.group(4) ?? '0');
  if (sh > 23 || eh > 24 || sm > 59 || em > 59) return null;
  if (eh == 24) eh = 0;
  final start = sh * 60 + sm;
  var end = eh * 60 + em;
  if (end <= start && end + 12 * 60 > start && end + 12 * 60 < 24 * 60) {
    end += 12 * 60;
    eh += 12;
  }
  return (
    start: '${_two(sh)}:${_two(sm)}',
    end: '${_two(eh % 24)}:${_two(em)}',
    from: m.start,
    to: m.end,
  );
}

/// "a 4,10", "a $5 la hora", "5 dólares por hora" → cents per hour.
int? _rate(String t) {
  final perHour = RegExp(
    r'\$?\s*(\d+(?:[.,]\d{1,2})?)\s*(?:usd|dolares?|\$)?\s*(?:la hora|por hora|/h|x hora|c/h)\b',
  ).firstMatch(t);
  if (perHour != null) return parseCents(perHour.group(1)!);
  final at = RegExp(
    r'\ba\s+\$?\s*(\d+(?:[.,]\d{1,2})?)\s*(?:usd|dolares?)?(?:\s|$)',
  ).firstMatch('$t ');
  return at == null ? null : parseCents(at.group(1)!);
}

/// "gané 20", "me pagaron $35,50", "un trabajo de 20 dólares" → cents.
int? _total(String t) {
  final paid = RegExp(
    r'\b(?:gane|cobre|me pagaron|pagaron|me dieron|total)\s+(?:de\s+)?\$?\s*(\d+(?:[.,]\d{1,2})?)',
  ).firstMatch(t);
  if (paid != null) return parseCents(paid.group(1)!);
  final amount = RegExp(
    r'(?:\$\s*(\d+(?:[.,]\d{1,2})?)|\b(\d+(?:[.,]\d{1,2})?)\s*(?:usd|dolares?)\b)(?!\s*(?:la hora|por hora|/h))',
  ).firstMatch(t);
  if (amount == null) return null;
  return parseCents(amount.group(1) ?? amount.group(2)!);
}

const _workWords =
    r'\b(?:trabaje|trabajo|trabajamos|turno|jornada|chamba|chambee|hice|horas?|cobre|gane|me pagaron)\b';

LogIntent? _work(String original, String t) {
  if (!RegExp(_workWords).hasMatch(t)) return null;
  final range = _range(t);
  final rest = range == null
      ? t
      : t.replaceRange(range.from, range.to, ' ' * (range.to - range.from));
  final minutes = range == null ? _duration(rest) : null;
  final total = RegExp(r'\b(?:la hora|por hora|/h|x hora)\b').hasMatch(rest)
      ? null
      : _total(rest);
  final rate = total == null && (minutes != null || range != null)
      ? _rate(rest)
      : null;
  if (minutes == null && range == null && total == null) return null;
  final fields = <String, Object>{
    'minutes': ?minutes,
    if (range != null) 'start': range.start,
    if (range != null) 'end': range.end,
    'rate_cents': ?rate,
    'total_cents': ?total,
  };
  final label = RegExp(
    r'\b(?:horas?(?:\s+y\s+(?:media|cuarto))?|h|turno|trabajo|jornada|chamba)\s+(?:de|en)\s+(?:(?:el|la|los|las)\s+)?(?!\d)([a-z][a-z ]{1,40}?)(?=\s+(?:a|de|por|hasta|y|con)\s|\s*[,.]|$)',
  ).firstMatch(t);
  if (label != null) {
    final span = _groupSpan(t, label, 1);
    final text = original.substring(span.start, span.end).trim();
    if (text.isNotEmpty) fields['label'] = text;
  }
  return LogIntent(LogAction.workEntry, fields);
}

LogIntent? _weight(String t) {
  final m = RegExp(
    r'\b(?:peso|pese|pesaba|bascula|estoy en|marque)\b[^\d]{0,15}(\d{2,3}(?:[.,]\d{1,2})?)\s*(kg|kilos?|kilogramos?)?',
  ).firstMatch(t);
  final unitOnly = RegExp(
    r'\b(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|kilos?|kilogramos?)\b',
  ).firstMatch(t);
  final raw = m?.group(1) ?? unitOnly?.group(1);
  if (raw == null) return null;
  if (m != null &&
      m.group(2) == null &&
      unitOnly == null &&
      !RegExp(r'\b(?:peso|pese|pesaba|bascula)\b').hasMatch(t)) {
    return null;
  }
  final kg = double.parse(raw.replaceAll(',', '.'));
  if (kg < 20 || kg > 300) return null;
  return LogIntent(LogAction.weight, {'kg': kg});
}

LogIntent? _state(String t) {
  final numeric = RegExp(
    r'\b(?:me siento|estado|animo|energia|estoy)\s+(?:en\s+|un\s+|como\s+)?([1-5])\b(?:\s*(?:de|/)\s*5)?',
  ).firstMatch(t);
  if (numeric != null) {
    return LogIntent(LogAction.state, {'value': int.parse(numeric.group(1)!)});
  }
  final words = RegExp(
    r'\b(?:me siento|estoy|ando)\s+(muy mal|fatal|mal|regular|normal|muy bien|bien|excelente)\b',
  ).firstMatch(t);
  if (words == null) return null;
  const values = {
    'muy mal': 1,
    'fatal': 1,
    'mal': 2,
    'regular': 3,
    'normal': 3,
    'bien': 4,
    'muy bien': 5,
    'excelente': 5,
  };
  return LogIntent(LogAction.state, {'value': values[words.group(1)]!});
}

LogIntent? _thermos(String t) {
  if (!RegExp(r'\btermo\b').hasMatch(t)) return null;
  if (RegExp(r'\b(?:pausa|almuerzo|receso|descanso)\b').hasMatch(t)) {
    return const LogIntent(LogAction.thermos, {'moment': 'pausa'});
  }
  if (RegExp(r'\b(?:antes|manana|entrar|salir de casa)\b').hasMatch(t)) {
    return const LogIntent(LogAction.thermos, {'moment': 'antes'});
  }
  // The moment stays for the form to ask.
  return const LogIntent(LogAction.thermos, {});
}

LogIntent? _food(String original, String t) {
  final m = RegExp(
    r'\b(?:me comi|comi|desayune|almorce|cene|merende|me tome|tome|bebi)\s+(.+?)\s*[.!]*$',
  ).firstMatch(t);
  if (m == null) return null;
  final span = _groupSpan(t, m, 1);
  var from = span.start;
  final body = t.substring(from, span.end);
  final grams = RegExp(
    r'^(\d+(?:[.,]\d+)?)\s*(?:g|gr|grs|gramos)\s+(?:de\s+)?',
  ).firstMatch(body);
  final qty = RegExp('^($_numberWord)\\s+(?:de\\s+)?').firstMatch(body);
  final fields = <String, Object>{};
  if (grams != null) {
    fields['grams'] = double.parse(grams.group(1)!.replaceAll(',', '.'));
    from += grams.end;
  } else if (qty != null && _quantity(qty.group(1)!) != null) {
    fields['quantity'] = _quantity(qty.group(1)!)!;
    from += qty.end;
  }
  final food = original.substring(from, span.end).trim();
  if (food.isEmpty) return null;
  fields['food'] = food;
  return LogIntent(LogAction.foodLog, fields);
}

/// Deterministic parser. Null when no rule matches (then, and only then,
/// the model may be asked). A record may miss fields; the form asks.
LogIntent? parseByRules(String text) {
  final original = text.trim();
  if (original.isEmpty) return null;
  final t = _fold(original);
  return _thermos(t) ??
      _weight(t) ??
      _state(t) ??
      _food(original, t) ??
      _work(original, t);
}
