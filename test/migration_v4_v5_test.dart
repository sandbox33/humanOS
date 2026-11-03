import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-4 database exactly as Phase 4 created it
/// (`drift_schemas/drift_schema_v4.json`), with invented test rows.
File v4Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v4.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 4');
  db.execute("INSERT INTO app_settings (key, value, updated_at) VALUES ('theme', 'grimorio', '2026-10-31T20:05:00')");
  db.execute(
    'INSERT INTO work_entries (date, label, kind, minutes, earned_cents, created_at) '
    "VALUES ('2026-10-02', 'Prueba', 'eventual', 240, 1600, '2026-10-02T17:00:00')",
  );
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig5'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 4 → 5 adds empty finance tables and keeps every row', () async {
    final file = v4Database(dir);
    final plain = raw.sqlite3.open(file.path);
    final before = tableRowCounts(plain);
    plain.close();

    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    expect((await db.select(db.workEntries).getSingle()).earnedCents, 1600);
    expect((await db.select(db.appSettings).getSingle()).updatedAt, '2026-10-31T20:05:00');
    // Nothing is preloaded: no categories, no goals.
    final added = <TableInfo<Table, Object?>>[db.expenseCategories, db.expenses, db.goals, db.purchasePauses];
    for (final table in added) {
      expect(await db.select(table).get(), isEmpty, reason: table.actualTableName);
    }

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });

  test('the encrypted backup covers every table, finance included', () async {
    final db = UserDb(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.exportOrder.map((t) => t.actualTableName).toSet(), db.allTables.map((t) => t.actualTableName).toSet());
    final order = db.exportOrder.map((t) => t.actualTableName).toList();
    expect(order.indexOf('expense_categories'), lessThan(order.indexOf('expenses')));
  });

  test('money columns refuse non-positive amounts and unknown statuses', () async {
    final db = UserDb(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db.customStatement(
        "INSERT INTO expenses (date, category, amount_cents, created_at) VALUES ('2026-10-02', 'X', 0, '2026-10-02T10:00:00')",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement("INSERT INTO goals (title, status, created_at) VALUES ('X', 'otro', '2026-10-02T10:00:00')"),
      throwsA(anything),
    );
  });
}
