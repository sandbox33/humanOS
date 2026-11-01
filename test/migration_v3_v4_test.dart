import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-3 database exactly as Phase 2 created it
/// (`drift_schemas/drift_schema_v3.json`), with invented test rows.
File v3Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v3.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 3');
  db.execute("INSERT INTO app_settings (key, value) VALUES ('accent', 'orange'), ('crt_headers', '0')");
  db.execute(
    'INSERT INTO work_entries (date, label, kind, minutes, created_at) '
    "VALUES ('2026-10-02', 'Prueba', 'estable', 450, '2026-10-02T17:00:00')",
  );
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig4'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 3 → 4 adds settings.updated_at and keeps every value', () async {
    final file = v3Database(dir);
    final plain = raw.sqlite3.open(file.path);
    final before = tableRowCounts(plain);
    plain.close();

    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    final rows = {for (final r in await db.select(db.appSettings).get()) r.key: r};
    expect(rows['accent']!.value, 'orange');
    expect(rows['crt_headers']!.value, '0');
    // The date of an old value is unknown: it stays NULL, never invented.
    expect(rows.values.map((r) => r.updatedAt), everyElement(isNull));
    expect((await db.select(db.workEntries).getSingle()).minutes, 450);

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);

    // From now on every change records when it happened.
    final repo = SettingsRepository(db, now: () => DateTime(2026, 10, 31, 20, 5));
    await repo.set(SettingKey.theme, HosThemeId.grimorio.code);
    final theme = await (db.select(db.appSettings)..where((t) => t.key.equals(SettingKey.theme))).getSingle();
    expect(theme.value, 'grimorio');
    expect(theme.updatedAt, '2026-10-31T20:05:00.000');
  });
}
