import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A schema-11 database exactly as B6 created it
/// (`drift_schemas/drift_schema_v11.json`), with invented test rows.
File v11Database(Directory dir) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v11.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 11');
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
  db.execute("INSERT INTO day_closes (date, mood, energy, updated_at) VALUES ('2026-11-03', 4, 3, '2026-11-03T21:00:00')");
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig12'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 11 → 12 adds the empty token tables and keeps every row', () async {
    final file = v11Database(dir);
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
    expect((await db.select(db.dayCloses).getSingle()).mood, 4);
    // Tokens are off and no rule is preloaded.
    expect(await db.select(db.tokenEarnRules).get(), isEmpty);
    expect(await db.select(db.tokenCostRules).get(), isEmpty);
    expect(await db.select(db.tokenDays).get(), isEmpty);

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });

  test('rules need positive tokens and minutes', () async {
    final db = UserDb(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db.customStatement("INSERT INTO token_cost_rules (category, tokens, per_minutes) VALUES ('ocio', 1, 0)"),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement("INSERT INTO token_earn_rules (source, tokens) VALUES ('entreno', 0)"),
      throwsA(anything),
    );
    expect(db.exportOrder.map((t) => t.actualTableName).toSet(), db.allTables.map((t) => t.actualTableName).toSet());
  });
}
