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

/// First-launch seed: profile, every assumption of the catalogue, the
/// habits (discreet aliases) and the three meal templates. Runs inside one
/// transaction and only when the profile row does not exist yet. Missing
/// assumptions (new catalogue keys after an update) are added on every
/// launch without touching edited values.
Future<void> seedIfNeeded(UserDb db) async {
  await db.transaction(() async {
    final existing = await db.select(db.profile).getSingleOrNull();
    if (existing == null) {
      await db.into(db.profile).insert(ProfileCompanion.insert(
            id: const Value(1),
            name: 'Abraham Fuenmayor',
            birthYear: 2001,
            heightCm: 171,
            sex: Sex.male.code,
            targetWeightKg: 72,
          ));
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
        b.insertAll(db.mealTemplates, [
          MealTemplatesCompanion.insert(nameEs: 'Desayuno taller'),
          MealTemplatesCompanion.insert(nameEs: 'Almuerzo taller'),
          MealTemplatesCompanion.insert(nameEs: 'Cena'),
        ]);
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
