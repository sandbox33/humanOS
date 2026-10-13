import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos_core/humanos_core.dart';

import 'support/fixtures.dart';

void main() {
  late UserDb db;

  setUp(() => db = memoryUserDb());
  tearDown(() => db.close());

  test('first launch seeds profile, habits, templates and assumptions', () async {
    await seedIfNeeded(db);
    final profile = await db.select(db.profile).getSingle();
    expect(profile.birthYear, 2001);
    expect(profile.heightCm, 171);
    expect(profile.targetWeightKg, 72);
    expect(profile.shiftStart, '07:00');

    final habits = await db.select(db.habits).get();
    expect(habits.where((h) => h.isMinimum).map((h) => h.alias), ['P100', 'BÁSCULA', 'CLARO']);
    expect(habits, hasLength(7));

    final templates = await db.select(db.mealTemplates).get();
    expect(templates.map((t) => t.nameEs), ['Desayuno taller', 'Almuerzo taller', 'Cena']);

    final assumptions = await db.select(db.assumptionRows).get();
    expect(assumptions, hasLength(assumptionCatalog.length));
    expect(assumptions.every((a) => a.explainEs.isNotEmpty), isTrue);

    final weights = await db.select(db.bodyMetrics).get();
    expect(weights, isEmpty, reason: 'the day-1 weight is entered by the user');
    final prefill = await (db.select(db.appSettings)
          ..where((t) => t.key.equals(SettingKey.weightPrefill)))
        .getSingle();
    expect(prefill.value, '65');
  });

  test('a second launch keeps edited values', () async {
    await seedIfNeeded(db);
    await (db.update(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg)))
        .write(const AssumptionRowsCompanion(value: Value(2.0)));
    await seedIfNeeded(db);
    final row = await (db.select(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg)))
        .getSingle();
    expect(row.value, 2.0);
    expect(await db.select(db.habits).get(), hasLength(7));
  });
}
