import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos_core/humanos_core.dart';

import 'support/fixtures.dart';

void main() {
  late UserDb db;

  setUp(() => db = memoryUserDb());
  tearDown(() => db.close());

  test('first launch seeds habits, templates and assumptions, never a profile', () async {
    await seedIfNeeded(db);
    expect(await db.select(db.profile).getSingleOrNull(), isNull,
        reason: 'the app ships no personal data: the user enters the profile');

    final habits = await db.select(db.habits).get();
    expect(habits.where((h) => h.isMinimum).map((h) => h.alias), ['P100', 'BÁSCULA', 'CLARO']);
    expect(habits, hasLength(7));

    final templates = await db.select(db.mealTemplates).get();
    expect(templates.map((t) => t.nameEs), ['Desayuno', 'Almuerzo', 'Cena']);

    final assumptions = await db.select(db.assumptionRows).get();
    expect(assumptions, hasLength(assumptionCatalog.length));
    expect(assumptions.every((a) => a.explainEs.isNotEmpty), isTrue);

    expect(await db.select(db.bodyMetrics).get(), isEmpty);
    expect(await db.select(db.appSettings).get(), isEmpty);
  });

  test('a second launch keeps edited values and does not duplicate habits', () async {
    await seedIfNeeded(db);
    await (db.update(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg)))
        .write(const AssumptionRowsCompanion(value: Value(2.0)));
    await seedIfNeeded(db);
    final row = await (db.select(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg)))
        .getSingle();
    expect(row.value, 2.0);
    expect(await db.select(db.habits).get(), hasLength(7));
  });

  test('an existing install keeps its profile and habits untouched', () async {
    await insertTestProfile(db);
    await db.into(db.habits).insert(HabitsCompanion.insert(
          alias: 'PROPIO',
          icon: 'check',
          weight: 1,
          isMinimum: false,
        ));
    await seedIfNeeded(db);
    expect((await db.select(db.profile).getSingle()).name, 'Persona de prueba');
    expect((await db.select(db.habits).get()).map((h) => h.alias), ['PROPIO']);
  });
}
