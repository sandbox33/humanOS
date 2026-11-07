// Checks docs/expediente/expediente.json against the version 2 format of
// docs/expediente/ESQUEMA.md. Pure Dart (no Flutter imports) so it can also
// run with the plain Dart SDK.
import 'dart:convert';
import 'dart:io';

typedef Json = Map<String, Object?>;

Json readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Json;

const _topKeys = {
  'esquema',
  'proyecto',
  'actualizado',
  'estado',
  'objetivo',
  'fases',
  'tareas',
  'ideas',
  'decisiones',
  'riesgos',
  'briefs',
  'mapa',
  'incidentes',
  'deuda',
  'invariantes',
  'estudio',
  'contradicciones',
  'siguiente_paso',
};

/// Keys of every item, as in ESQUEMA.md.
const _itemKeys = <String, Set<String>>{
  'fases': {'id', 'nombre', 'estado', 'estimado_dias', 'inicio', 'fin', 'bloqueada_por'},
  'tareas': {'id', 'fase', 'titulo', 'estado', 'creada', 'cerrada'},
  'ideas': {'id', 'titulo', 'detalle', 'estado', 'creada', 'motivo'},
  'decisiones': {'id', 'fecha', 'decision', 'motivo', 'reemplaza', 'vigente'},
  'riesgos': {'id', 'riesgo', 'impacto', 'mitigacion'},
  'briefs': {'archivo', 'estado', 'reemplazado_por'},
  'nodos': {'id', 'tipo', 'nombre', 'archivo', 'descripcion', 'fuente', 'confianza', 'evidencia'},
  'aristas': {'de', 'a', 'tipo', 'detalle', 'fuente', 'confianza'},
  'incidentes': {
    'id',
    'nodo',
    'sintoma',
    'causa_raiz',
    'estado',
    'veces',
    'primera',
    'ultima',
    'evidencia',
    'fuente',
    'confianza',
  },
  'deuda': {'id', 'nodo', 'tipo', 'descripcion', 'tamano', 'creada', 'estado', 'fuente', 'confianza'},
  'invariantes': {'id', 'regla', 'cumple', 'evidencia', 'fuente', 'confianza'},
  'estudio': {'id', 'nodo', 'pregunta', 'respuesta_ref', 'orden'},
};

const _idPrefix = <String, String>{
  'fases': 'F',
  'tareas': 'T',
  'ideas': 'I',
  'decisiones': 'D',
  'riesgos': 'R',
  'nodos': 'N',
  'incidentes': 'X',
  'deuda': 'K',
  'invariantes': 'V',
  'estudio': 'E',
  'contradicciones': 'C',
};

const _fuentes = {'hechos', 'claude', 'altair'};
const _confianzas = {'verificado', 'inferido'};

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// `archivo:línea` (or a line range), as `respuesta_ref` asks.
final _fileLine = RegExp(r'^[\w./-]+\.[\w]+:\d+(-\d+)?$');

/// Evidence the schema accepts: archivo:línea, a commit or a run id.
final _evidence = RegExp(r'[\w./-]+\.[\w]+:\d+|\bcommit [0-9a-f]{7,40}\b|\brun \d{6,}\b');

bool _isDate(Object? v) => v is String && _date.hasMatch(v) && DateTime.tryParse(v) != null;

bool _isText(Object? v) => v is String && v.isNotEmpty;

/// Every rule [e] breaks, as readable messages (empty when it is valid).
List<String> validateExpediente(Json e) {
  final errors = <String>[];
  void check(bool ok, String message) {
    if (!ok) errors.add(message);
  }

  void oneOf(Object? value, Set<String> allowed, String where) =>
      check(value is String && allowed.contains(value), '$where: "$value" no está en $allowed');

  check(e.keys.toSet().containsAll(_topKeys), 'faltan claves: ${_topKeys.difference(e.keys.toSet())}');
  check(e.keys.toSet().difference(_topKeys).isEmpty, 'claves de más: ${e.keys.toSet().difference(_topKeys)}');
  check(e['esquema'] == 2, 'esquema debe ser 2');
  check(_isText(e['proyecto']), 'proyecto vacío');
  check(_isDate(e['actualizado']), 'actualizado no es AAAA-MM-DD');
  oneOf(e['estado'], {'activo', 'pausado', 'congelado', 'terminado'}, 'estado');
  check(e['objetivo'] is String, 'objetivo no es texto');
  check(_isText(e['siguiente_paso']), 'siguiente_paso vacío');

  List<Json> items(Object? list, String section) {
    if (list is! List<Object?>) {
      errors.add('$section no es una lista');
      return const [];
    }
    final out = <Json>[];
    final keys = _itemKeys[section];
    for (final (i, item) in list.indexed) {
      if (item is! Json) {
        errors.add('$section[$i] no es un objeto');
        continue;
      }
      if (keys != null && !(item.keys.toSet().containsAll(keys) && keys.containsAll(item.keys))) {
        errors.add('$section[$i]: claves ${item.keys.toSet()} distintas de $keys');
      }
      out.add(item);
    }
    return out;
  }

  Set<String> ids(List<Json> list, String section) {
    final seen = <String>{};
    for (final item in list) {
      final id = item['id'];
      final prefix = _idPrefix[section]!;
      check(id is String && RegExp('^$prefix\\d+\$').hasMatch(id), '$section: id "$id" no es $prefix<número>');
      check(seen.add('$id'), '$section: id repetido "$id"');
    }
    return seen;
  }

  void provenance(Json item, String where, {String? evidenceField}) {
    oneOf(item['fuente'], _fuentes, '$where.fuente');
    oneOf(item['confianza'], _confianzas, '$where.confianza');
    if (item['confianza'] != 'verificado') return;
    if (evidenceField == null) return;
    final value = item[evidenceField];
    if (value is List<Object?>) {
      check(value.isNotEmpty, '$where: verificado sin evidencia');
      for (final ev in value) {
        check(ev is String && _evidence.hasMatch(ev), '$where: evidencia "$ev" no es archivo:línea, commit ni run');
      }
    } else {
      check(value is String && _evidence.hasMatch(value), '$where: verificado sin evidencia en $evidenceField');
    }
  }

  // Plan: phases, tasks, ideas, decisions, risks, briefs.
  final fases = items(e['fases'], 'fases');
  final faseIds = ids(fases, 'fases');
  for (final f in fases) {
    final where = 'fases ${f['id']}';
    oneOf(f['estado'], {'pendiente', 'en_curso', 'bloqueada', 'hecha'}, '$where.estado');
    check(f['estimado_dias'] == null || f['estimado_dias'] is int, '$where.estimado_dias');
    check(f['inicio'] == null || _isDate(f['inicio']), '$where.inicio');
    check(f['fin'] == null || _isDate(f['fin']), '$where.fin');
    check(f['estado'] != 'hecha' || f['fin'] != null, '$where: hecha sin fin');
    final deps = f['bloqueada_por'];
    check(deps is List<Object?> && deps.every(faseIds.contains), '$where.bloqueada_por');
  }
  final tareas = items(e['tareas'], 'tareas');
  ids(tareas, 'tareas');
  for (final t in tareas) {
    final where = 'tareas ${t['id']}';
    check(faseIds.contains(t['fase']), '$where: fase "${t['fase']}" no existe');
    oneOf(t['estado'], {'pendiente', 'en_curso', 'hecha', 'descartada'}, '$where.estado');
    check(_isDate(t['creada']), '$where.creada');
    check(t['cerrada'] == null || _isDate(t['cerrada']), '$where.cerrada');
    check(t['estado'] != 'hecha' || t['cerrada'] != null, '$where: hecha sin cerrada');
  }
  final ideas = items(e['ideas'], 'ideas');
  ids(ideas, 'ideas');
  for (final i in ideas) {
    oneOf(i['estado'], {'nueva', 'aceptada', 'descartada', 'hecha'}, 'ideas ${i['id']}.estado');
    check(_isDate(i['creada']), 'ideas ${i['id']}.creada');
  }
  final decisiones = items(e['decisiones'], 'decisiones');
  final decisionIds = ids(decisiones, 'decisiones');
  for (final d in decisiones) {
    check(_isDate(d['fecha']), 'decisiones ${d['id']}.fecha');
    check(d['reemplaza'] == null || decisionIds.contains(d['reemplaza']), 'decisiones ${d['id']}.reemplaza');
    check(d['vigente'] is bool, 'decisiones ${d['id']}.vigente');
  }
  final riesgos = items(e['riesgos'], 'riesgos');
  ids(riesgos, 'riesgos');
  for (final r in riesgos) {
    oneOf(r['impacto'], {'alto', 'medio', 'bajo'}, 'riesgos ${r['id']}.impacto');
  }
  for (final b in items(e['briefs'], 'briefs')) {
    oneOf(b['estado'], {'vigente', 'reemplazado', 'ejecutado'}, 'briefs ${b['archivo']}.estado');
    check(
      b['estado'] != 'reemplazado' || b['reemplazado_por'] is String,
      'briefs ${b['archivo']}: sin reemplazado_por',
    );
  }

  // Map: nodes and one-to-one edges.
  final mapa = e['mapa'];
  var nodeIds = <String>{};
  if (mapa is Json) {
    final nodos = items(mapa['nodos'], 'nodos');
    nodeIds = ids(nodos, 'nodos');
    for (final n in nodos) {
      oneOf(n['tipo'], {'disparador', 'job', 'modulo', 'dato', 'externo'}, 'nodos ${n['id']}.tipo');
      check(n['archivo'] == null || n['archivo'] is String, 'nodos ${n['id']}.archivo');
      provenance(n, 'nodos ${n['id']}', evidenceField: 'evidencia');
    }
    for (final (i, a) in items(mapa['aristas'], 'aristas').indexed) {
      final where = 'aristas[$i] ${a['de']}→${a['a']}';
      check(a['de'] is String && nodeIds.contains(a['de']), '$where: de no es un nodo');
      check(a['a'] is String && nodeIds.contains(a['a']), '$where: a no es un nodo');
      oneOf(a['tipo'], {'dispara', 'llama', 'produce', 'consume'}, '$where.tipo');
      provenance(a, where, evidenceField: 'detalle');
    }
  } else {
    errors.add('mapa no es un objeto');
  }

  // Audit: incidents, debt, invariants, study path.
  final incidentes = items(e['incidentes'], 'incidentes');
  ids(incidentes, 'incidentes');
  for (final x in incidentes) {
    final where = 'incidentes ${x['id']}';
    check(nodeIds.contains(x['nodo']), '$where: nodo "${x['nodo']}" no existe');
    oneOf(x['estado'], {'abierto', 'resuelto', 'recurrente'}, '$where.estado');
    final veces = x['veces'];
    check(veces is int && veces >= 1, '$where.veces');
    check(_isDate(x['primera']) && _isDate(x['ultima']), '$where: primera/ultima');
    check('${x['primera']}'.compareTo('${x['ultima']}') <= 0, '$where: primera después de ultima');
    provenance(x, where, evidenceField: 'evidencia');
  }
  final deuda = items(e['deuda'], 'deuda');
  ids(deuda, 'deuda');
  for (final k in deuda) {
    final where = 'deuda ${k['id']}';
    check(nodeIds.contains(k['nodo']), '$where: nodo "${k['nodo']}" no existe');
    oneOf(k['tipo'], {'prueba_faltante', 'duplicado', 'valor_fijo', 'sin_doc', 'fragil', 'otro'}, '$where.tipo');
    oneOf(k['tamano'], {'S', 'M', 'L'}, '$where.tamano');
    oneOf(k['estado'], {'abierta', 'pagada'}, '$where.estado');
    check(_isDate(k['creada']), '$where.creada');
    provenance(k, where, evidenceField: 'descripcion');
  }
  final invariantes = items(e['invariantes'], 'invariantes');
  ids(invariantes, 'invariantes');
  for (final v in invariantes) {
    check(v['cumple'] is bool, 'invariantes ${v['id']}.cumple no es true/false');
    provenance(v, 'invariantes ${v['id']}', evidenceField: 'evidencia');
  }
  final estudio = items(e['estudio'], 'estudio');
  ids(estudio, 'estudio');
  final orders = <Object?>{};
  for (final s in estudio) {
    final where = 'estudio ${s['id']}';
    check(nodeIds.contains(s['nodo']), '$where: nodo "${s['nodo']}" no existe');
    final ref = s['respuesta_ref'];
    check(ref is String && _fileLine.hasMatch(ref), '$where.respuesta_ref "$ref" no es archivo:línea');
    check(s['orden'] is int && orders.add(s['orden']), '$where.orden repetido o no entero');
  }
  final contradicciones = e['contradicciones'];
  if (contradicciones is List<Object?>) {
    ids([
      for (final c in contradicciones)
        if (c is Json) c,
    ], 'contradicciones');
  } else {
    errors.add('contradicciones no es una lista');
  }
  return errors;
}

/// IDs and briefs of [v1] that [v2] lost (stable IDs: nothing is deleted).
List<String> missingFromV1(Json v1, Json v2) {
  final missing = <String>[];
  for (final section in ['fases', 'tareas', 'ideas', 'decisiones', 'riesgos']) {
    Set<Object?> idsOf(Json e) => {
      for (final item in (e[section] as List<Object?>?) ?? const <Object?>[]) (item as Json)['id'],
    };
    missing.addAll([for (final id in idsOf(v1).difference(idsOf(v2))) '$section $id']);
  }
  Set<Object?> briefsOf(Json e) => {
    for (final b in (e['briefs'] as List<Object?>?) ?? const <Object?>[]) (b as Json)['archivo'],
  };
  missing.addAll([for (final b in briefsOf(v1).difference(briefsOf(v2))) 'briefs $b']);
  return missing;
}

/// Money signs and clock times anywhere in the text (public repository).
List<String> privacyFindings(Json e) {
  final pattern = RegExp(r'[$€£]|\bUSD\b|\b\d{1,2}:\d{2}\b');
  return [for (final m in pattern.allMatches(jsonEncode(e))) m.group(0)!];
}
