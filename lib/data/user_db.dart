import 'package:drift/drift.dart';

import 'migrations/v1_to_v2.dart';
import 'migrations/v2_to_v3.dart';
import 'tables/context_tables.dart';
import 'tables/food_tables.dart';
import 'tables/habit_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/training_tables.dart';
import 'tables/work_tables.dart';

export 'tables/context_tables.dart';
export 'tables/food_tables.dart';
export 'tables/habit_tables.dart';
export 'tables/profile_tables.dart';
export 'tables/training_tables.dart';
export 'tables/work_tables.dart';

part 'user_db.g.dart';

/// The read-write user database (`user.sqlite`, encrypted). Never
/// overwritten except by a user-initiated restore. Migrations go step by
/// step; `deleteAllTables` is never used.
@DriftDatabase(tables: [
  Profile,
  AssumptionRows,
  BodyMetrics,
  DailyLogs,
  AppSettings,
  Purchases,
  PantryItems,
  ProductsCache,
  MealTemplates,
  MealTemplateItems,
  Meals,
  MealItems,
  CookedBatches,
  FoodUserFlags,
  Sessions,
  Sets,
  PersonalRecords,
  Readiness,
  TelemetrySamples,
  Habits,
  HabitLogs,
  StreakState,
  Attributes,
  // Schema v2
  WorkEntries,
  WorkTemplates,
  // Schema v3
  Zones,
  ContextEvents,
  ModeCorrections,
  StateCheckins,
  EventReminders,
  MorningAlarms,
])
class UserDb extends _$UserDb {
  UserDb(super.e);

  /// Bump only together with a new migration step and a new file in
  /// `drift_schemas/`.
  static const currentSchema = 3;

  @override
  int get schemaVersion => currentSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          for (var version = from; version < to; version++) {
            switch (version) {
              case 1:
                await migrateV1ToV2(m, this);
              case 2:
                await migrateV2ToV3(m, this);
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Every table in dependency order (parents first) for export/import.
  List<TableInfo<Table, Object?>> get exportOrder => [
        profile,
        assumptionRows,
        appSettings,
        bodyMetrics,
        dailyLogs,
        purchases,
        pantryItems,
        productsCache,
        mealTemplates,
        mealTemplateItems,
        meals,
        mealItems,
        cookedBatches,
        foodUserFlags,
        sessions,
        sets,
        personalRecords,
        readiness,
        telemetrySamples,
        habits,
        habitLogs,
        streakState,
        attributes,
        workTemplates,
        workEntries,
        zones,
        contextEvents,
        modeCorrections,
        stateCheckins,
        eventReminders,
        morningAlarms,
      ];
}
