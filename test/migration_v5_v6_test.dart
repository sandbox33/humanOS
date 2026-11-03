import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-5 database exactly as Phase 5 created it
/// (`drift_schemas/drift_schema_v5.json`), with invented test rows.
File v5Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v5.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 5');
  db.execute(
    'INSERT INTO goals (title, target_cents, saved_cents, priority, status, created_at) '
    "VALUES ('Meta de prueba', 12000, 3000, 0, 'activo', '2026-10-30T10:00:00')",
  );
  db.execute(
    'INSERT INTO expenses (date, category, amount_cents, planned, impulse, created_at) '
    "VALUES ('2026-10-30', 'Prueba', 350, 1, 0, '2026-10-30T10:00:00')",
  );
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig6'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 5 → 6 adds the empty day schedule and keeps every row', () async {
    final file = v5Database(dir);
    final plain = raw.sqlite3.open(file.path);
    final before = tableRowCounts(plain);
    plain.close();

    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    expect((await db.select(db.goals).getSingle()).savedCents, 3000);
    expect((await db.select(db.expenses).getSingle()).amountCents, 350);
    // No block and no time is preloaded.
    expect(await db.select(db.scheduleBlocks).get(), isEmpty);
    expect(await db.select(db.scheduleAdjustments).get(), isEmpty);

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });

  test('blocks need at least one weekday and a known adjustment', () async {
    final db = UserDb(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db.customStatement(
        "INSERT INTO schedule_blocks (kind, start_clock, days_mask, created_at) VALUES ('ocio', '10:00', 0, '2026-11-03T10:00:00')",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO schedule_adjustments (date, action, created_at) VALUES ('2026-11-03', 'otra', '2026-11-03T10:00:00')",
      ),
      throwsA(anything),
    );
    expect(db.exportOrder.map((t) => t.actualTableName).toSet(), db.allTables.map((t) => t.actualTableName).toSet());
  });
}
