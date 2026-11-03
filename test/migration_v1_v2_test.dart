import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Builds a schema-1 database exactly as HumanOS v3.0 created it, from the
/// exported schema (`drift_schemas/drift_schema_v1.json`), and fills it
/// with invented test rows.
File v1Database(
  Directory dir, {
  String shiftStart = '08:00',
  String shiftEnd = '16:30',
  String lunchStart = '12:00',
}) {
  final schema = jsonDecode(File('drift_schemas/drift_schema_v1.json').readAsStringSync()) as Map<String, dynamic>;
  final file = File('${dir.path}/user.sqlite');
  final db = raw.sqlite3.open(file.path);
  for (final table in schema['fixed_sql'] as List<dynamic>) {
    for (final stmt in (table as Map<String, dynamic>)['sql'] as List<dynamic>) {
      db.execute((stmt as Map<String, dynamic>)['sql'] as String);
    }
  }
  db.execute('PRAGMA user_version = 1');
  db.execute(
    'INSERT INTO profile (id, name, birth_year, height_cm, sex, target_weight_kg, shift_start, shift_end, lunch_start) '
    "VALUES (1, 'Persona de prueba', 1990, 175, 'male', 75, ?, ?, ?)",
    [shiftStart, shiftEnd, lunchStart],
  );
  db.execute(
    'INSERT INTO assumptions (key, value, title_es, explain_es) VALUES '
    "('lunch_duration_min', 45, 't', 'e'), ('sweat_na_mmol_l', 40, 't', 'e'), "
    "('hydration_goal_fraction', 0.8, 't', 'e'), ('protein_g_per_kg', 2.0, 't', 'e')",
  );
  db.execute(
    'INSERT INTO daily_logs (date, work_effort, heat_hours, fluids_l, sweat_pre_kg, intake_complete) VALUES '
    "('2026-10-01', 'HIGH', 2.5, 3.1, 70.2, 1), ('2026-10-02', 'OFF', NULL, NULL, NULL, 0), "
    "('2026-10-03', 'LOW', 0, NULL, NULL, 0)",
  );
  db.execute("INSERT INTO purchases (id, date, store, total_usd) VALUES (1, '2026-10-01', 'tienda', 12.345)");
  db.execute(
    'INSERT INTO pantry_items (id, food_id, grams_remaining, price_usd_per_kg, purchase_id) VALUES (1, 3, 800, 3.5, 1)',
  );
  db.execute("INSERT INTO meals (id, date, block) VALUES (1, '2026-10-01', 'LUNCH')");
  db.execute('INSERT INTO meal_items (meal_id, food_id, grams, pantry_item_id) VALUES (1, 3, 150, 1)');
  db.execute(
    'INSERT INTO habits (alias, icon, weight, is_minimum, metric, target, source) VALUES '
    "('H2O', 'water', 2, 0, 'min', 80, 'hydration_pct'), ('P100', 'protein', 3, 1, 'min', 100, 'protein_g')",
  );
  db.execute(
    "INSERT INTO attributes (date, attr, value) VALUES ('2026-10-01', 'FUERZA', 104), ('2026-10-01', 'RESISTENCIA', 50)",
  );
  db.close();
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('humanos-mig'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('schema 1 → 2 keeps every row and matches a fresh schema', () async {
    final file = v1Database(dir);
    final before = fileRowCountsPlain(file);
    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    await db.validateDatabaseSchema();

    final profile = await db.select(db.profile).getSingle();
    expect(profile.name, 'Persona de prueba');

    final template = await db.select(db.workTemplates).getSingle();
    expect(template.label, 'Trabajo');
    expect(template.startClock, '08:00');
    expect(template.endClock, '16:30');
    expect(template.breakStart, '12:00');
    expect(template.breakMinutes, 45);
    expect(template.daysMask, 0x7F);
    expect(template.heatExposure, isTrue);

    final entries = (await db.select(db.workEntries).get())..sort((a, b) => a.date.compareTo(b.date));
    expect(entries.map((e) => e.date), ['2026-10-01', '2026-10-03']);
    expect(entries.first.minutes, 510 - 45);
    expect(entries.first.startTs, '2026-10-01T08:00:00');
    expect(entries.first.endTs, '2026-10-01T16:30:00');
    expect(entries.first.earnedCents, isNull, reason: 'unknown earnings stay unknown');
    expect(entries.first.templateId, template.id);

    final logs = (await db.select(db.dailyLogs).get())..sort((a, b) => a.date.compareTo(b.date));
    expect(logs, hasLength(3));
    expect(logs.first.heatMinutes, 150);
    expect(logs.first.workEffort, 'HIGH');
    expect(logs.first.intakeComplete, isTrue);
    expect(logs[2].heatMinutes, 0);
    expect(logs[1].heatMinutes, isNull);

    expect((await db.select(db.purchases).getSingle()).totalCents, 1235);
    expect((await db.select(db.pantryItems).getSingle()).priceCentsPerKg, 350);
    expect(await db.select(db.mealItems).get(), hasLength(1));

    final keys = {for (final a in await db.select(db.assumptionRows).get()) a.key: a.value};
    expect(keys.containsKey('sweat_na_mmol_l'), isFalse);
    expect(keys.containsKey('hydration_goal_fraction'), isFalse);
    expect(keys['protein_g_per_kg'], 2.0, reason: 'edited values survive');

    final h2o = (await db.select(db.habits).get()).firstWhere((h) => h.alias == 'H2O');
    expect(h2o.source, 'hydration_ack');
    expect(h2o.target, 2);
    expect(await db.select(db.attributes).get(), hasLength(2));

    final after = <String, int>{};
    for (final t in before.keys) {
      final row = await db.customSelect('SELECT count(*) AS n FROM "$t"').getSingle();
      after[t] = row.data['n'] as int;
    }
    expect(migrationLosses(before, after), isEmpty);
  });

  test('a night shift becomes a template that crosses midnight', () async {
    final file = v1Database(dir, shiftStart: '22:00', shiftEnd: '06:00', lunchStart: '02:00');
    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    final entry = (await db.select(db.workEntries).get()).first;
    expect(entry.startTs, '2026-10-01T22:00:00');
    expect(entry.endTs, '2026-10-02T06:00:00');
    expect(entry.minutes, 480 - 45);
  });

  test('a profile without a valid shift creates no template', () async {
    final file = v1Database(dir, shiftStart: 'xx', shiftEnd: '16:00');
    final db = UserDb(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.select(db.workTemplates).get(), isEmpty);
    expect(await db.select(db.workEntries).get(), isEmpty);
    expect(await db.select(db.dailyLogs).get(), hasLength(3));
  });

  test('row losses are detected, intended shrinks are not', () {
    expect(migrationLosses({'a': 3, 'assumptions': 10}, {'a': 3, 'assumptions': 5}), isEmpty);
    expect(migrationLosses({'a': 3}, {'a': 2}), ['a']);
    expect(migrationLosses({'a': 3}, const {}), ['a']);
    expect(migrationLosses({'a': 3}, {'a': 4}), isEmpty);
  });
}

Map<String, int> fileRowCountsPlain(File file) {
  final db = raw.sqlite3.open(file.path);
  try {
    return tableRowCounts(db);
  } finally {
    db.close();
  }
}
