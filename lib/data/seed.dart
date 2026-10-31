import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import 'user_db.dart';

/// Habit sources filled automatically from other data.
abstract final class HabitSource {
  static const proteinG = 'protein_g';
  static const weighIn = 'weigh_in';
  static const sober = 'sober';
  static const screenMinutes = 'screen_min';
  static const hydrationPct = 'hydration_pct';
  static const big3 = 'big3';
  static const sleepHours = 'sleep_h';
}

/// First-launch seed: every assumption of the catalogue, the habits
/// (discreet aliases) and three meal templates. No personal data: the
/// profile is entered by the user on the first screen. Habits and templates
/// are inserted once, when there are none; missing assumptions (new
/// catalogue keys after an update) are added on every launch without
/// touching edited values.
Future<void> seedIfNeeded(UserDb db) async {
  await db.transaction(() async {
    final anyHabit = await (db.select(db.habits)..limit(1)).getSingleOrNull();
    if (anyHabit == null) {
      await db.batch((b) {
        b.insertAll(db.habits, [
          HabitsCompanion.insert(
            alias: 'P100',
            icon: 'protein',
            weight: 3,
            isMinimum: true,
            metric: const Value('min'),
            target: const Value(100),
            source: const Value(HabitSource.proteinG),
          ),
          HabitsCompanion.insert(
            alias: 'BÁSCULA',
            icon: 'scale',
            weight: 2,
            isMinimum: true,
            source: const Value(HabitSource.weighIn),
          ),
          HabitsCompanion.insert(
            alias: 'CLARO',
            icon: 'shield',
            weight: 3,
            isMinimum: true,
            source: const Value(HabitSource.sober),
          ),
          HabitsCompanion.insert(
            alias: 'VISOR',
            icon: 'screen',
            weight: 1,
            isMinimum: false,
            metric: const Value('max'),
            target: const Value(60),
            source: const Value(HabitSource.screenMinutes),
          ),
          HabitsCompanion.insert(
            alias: 'H2O',
            icon: 'water',
            weight: 2,
            isMinimum: false,
            metric: const Value('min'),
            target: const Value(80),
            source: const Value(HabitSource.hydrationPct),
          ),
          HabitsCompanion.insert(
            alias: 'B3',
            icon: 'spine',
            weight: 1,
            isMinimum: false,
            source: const Value(HabitSource.big3),
          ),
          HabitsCompanion.insert(
            alias: 'NOCHE',
            icon: 'moon',
            weight: 2,
            isMinimum: false,
            metric: const Value('min'),
            target: const Value(7),
            source: const Value(HabitSource.sleepHours),
          ),
        ]);
        b.insertAll(
          db.mealTemplates,
          [
            MealTemplatesCompanion.insert(nameEs: 'Desayuno'),
            MealTemplatesCompanion.insert(nameEs: 'Almuerzo'),
            MealTemplatesCompanion.insert(nameEs: 'Cena'),
          ],
          mode: InsertMode.insertOrIgnore,
        );
      });
    }
    final stored = {
      for (final row in await db.select(db.assumptionRows).get()) row.key,
    };
    final missing =
        assumptionCatalog.where((def) => !stored.contains(def.key)).toList();
    if (missing.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(db.assumptionRows, [
          for (final def in missing)
            AssumptionRowsCompanion.insert(
              key: def.key,
              value: def.value,
              titleEs: def.titleEs,
              explainEs: def.explainEs,
              source: Value(def.source),
            ),
        ]);
      });
    }
  });
}
