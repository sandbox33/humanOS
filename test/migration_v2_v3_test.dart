import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-2 database exactly as Phase 1 created it
/// (`drift_schemas/drift_schema_v2.json`), with invented test rows.
File v2Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v2.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 2');
  db.execute(
    'INSERT INTO profile (id, name, birth_year, height_cm, sex, target_weight_kg) '
    "VALUES (1, 'Persona de prueba', 1990, 175, 'male', 75)",
  );
  db.execute(
    'INSERT INTO work_templates (label, kind, start_clock, end_clock, heat_exposure, status, sort_order, created_at) '
    "VALUES ('Prueba', 'estable', '08:00', '16:00', 0, 'activo', 0, '2026-10-01T00:00:00')",
  );
  db.execute(
    'INSERT INTO work_entries (date, label, kind, minutes, created_at, template_id) '
    "VALUES ('2026-10-02', 'Prueba', 'estable', 450, '2026-10-02T17:00:00', 1)",
  );
  db.execute("INSERT INTO daily_logs (date, work_effort, heat_minutes, intake_complete) VALUES ('2026-10-02', 'HIGH', 90, 1)");
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig3'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 2 → 3 adds the context and alarm tables and keeps every row', () async {
    final file = v2Database(dir);
    final plain = raw.sqlite3.open(file.path);
    final before = tableRowCounts(plain);
    plain.close();

    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    expect((await db.select(db.workEntries).getSingle()).minutes, 450);
    expect((await db.select(db.dailyLogs).getSingle()).heatMinutes, 90);
    for (final table in [db.zones, db.contextEvents, db.modeCorrections, db.stateCheckins, db.eventReminders, db.morningAlarms]) {
      expect(await db.select(table).get(), isEmpty, reason: table.actualTableName);
    }

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });
}
