import 'package:drift/drift.dart';

import 'tables/food_tables.dart';
import 'tables/habit_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/training_tables.dart';

export 'tables/food_tables.dart';
export 'tables/habit_tables.dart';
export 'tables/profile_tables.dart';
export 'tables/training_tables.dart';

part 'user_db.g.dart';

/// The read-write user database (`user.sqlite`). Never overwritten except
/// by a user-initiated encrypted import.
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
])
class UserDb extends _$UserDb {
  UserDb(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
      ];
}
