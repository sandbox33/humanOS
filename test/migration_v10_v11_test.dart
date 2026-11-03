import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-10 database exactly as B5 created it
/// (`drift_schemas/drift_schema_v10.json`), with invented test rows.
File v10Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v10.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 10');
  db.execute(
    'INSERT INTO goals (title, target_cents, saved_cents, priority, status, created_at) '
    "VALUES ('Meta de prueba', 12000, 3000, 0, 'activo', '2026-10-30T10:00:00')",
  );
  db.execute(
    'INSERT INTO expenses (date, category, amount_cents, planned, impulse, created_at) '
    "VALUES ('2026-10-30', 'Prueba', 350, 1, 0, '2026-10-30T10:00:00')",
  );
  db.execute(
    'INSERT INTO schedule_blocks (kind, start_clock, days_mask, alarm, status, created_at) '
    "VALUES ('dormir', '22:00', 127, 1, 'activo', '2026-11-03T10:00:00')",
  );
  db.execute("INSERT INTO app_classes (package, category, updated_at) VALUES ('test.juego', 'ocio', '2026-11-03T10:00:00')");
  db.execute("INSERT INTO app_usage_days (date, package, minutes) VALUES ('2026-11-03', 'test.juego', 30)");
  db.execute("INSERT INTO dns_domains (domain, list, created_at) VALUES ('b.example.com', 'bloquear', '2026-11-03T10:00:00')");
  db.execute("INSERT INTO receipt_links (line_key, food_id, updated_at) VALUES ('frejol', 4, '2026-11-03T10:00:00')");
  db.execute(
    'INSERT INTO pay_weeks (paid_on, amount_cents, normal_minutes, overtime_minutes, created_at) '
    "VALUES ('2026-11-03', 20000, 2400, 0, '2026-11-03T18:00:00')",
  );
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig11'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 10 → 11 adds the empty day-close tables and keeps every row', () async {
    final file = v10Database(dir);
    final plain = raw.sqlite3.open(file.path);
    final before = tableRowCounts(plain);
    plain.close();

    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    expect((await db.select(db.goals).getSingle()).savedCents, 3000);
    expect((await db.select(db.expenses).getSingle()).amountCents, 350);
    expect((await db.select(db.scheduleBlocks).getSingle()).startClock, '22:00');
    expect((await db.select(db.appUsageDays).getSingle()).minutes, 30);
    expect((await db.select(db.appClasses).getSingle()).category, 'ocio');
    expect((await db.select(db.dnsDomains).getSingle()).domain, 'b.example.com');
    expect((await db.select(db.receiptLinks).getSingle()).foodId, 4);
    expect((await db.select(db.payWeeks).getSingle()).amountCents, 20000);
    // No category and no close are preloaded.
    expect(await db.select(db.dayCloses).get(), isEmpty);
    expect(await db.select(db.interactionCategories).get(), isEmpty);
    expect(await db.select(db.dayCloseInteractions).get(), isEmpty);

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });

  test('mood and energy stay between 1 and 5', () async {
    final db = UserDb(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db.customStatement("INSERT INTO day_closes (date, mood, energy, updated_at) VALUES ('2026-11-03', 6, 3, '2026-11-03')"),
      throwsA(anything),
    );
    await db.customStatement("INSERT INTO day_closes (date, mood, energy, updated_at) VALUES ('2026-11-03', 5, 1, '2026-11-03')");
    expect((await db.select(db.dayCloses).getSingle()).honestyYes, isNull);
    expect(db.exportOrder.map((t) => t.actualTableName).toSet(), db.allTables.map((t) => t.actualTableName).toSet());
  });
}
