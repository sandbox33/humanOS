import 'package:drift/drift.dart';

import 'migrations/v10_to_v11.dart';
import 'migrations/v1_to_v2.dart';
import 'migrations/v2_to_v3.dart';
import 'migrations/v3_to_v4.dart';
import 'migrations/v4_to_v5.dart';
import 'migrations/v5_to_v6.dart';
import 'migrations/v6_to_v7.dart';
import 'migrations/v7_to_v8.dart';
import 'migrations/v8_to_v9.dart';
import 'migrations/v9_to_v10.dart';
import 'tables/close_tables.dart';
import 'tables/context_tables.dart';
import 'tables/dns_tables.dart';
import 'tables/finance_tables.dart';
import 'tables/food_tables.dart';
import 'tables/habit_tables.dart';
import 'tables/pantry_plan_tables.dart';
import 'tables/pay_tables.dart';
import 'tables/profile_tables.dart';
import 'tables/schedule_tables.dart';
import 'tables/screen_tables.dart';
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
  // Schema v5
  Expenses,
  ExpenseCategories,
  Goals,
  PurchasePauses,
  // Schema v6
  ScheduleBlocks,
  ScheduleAdjustments,
  // Schema v7
  AppClasses,
  AppUsageDays,
  // Schema v8
  DnsDomains,
  // Schema v9
  FoodHandlingFlags,
  ReceiptLinks,
  // Schema v10
  PayWeeks,
  CashCounts,
  // Schema v11
  DayCloses,
  InteractionCategories,
  DayCloseInteractions,
])
class UserDb extends _$UserDb {
  UserDb(super.e);

  /// Bump only together with a new migration step and a new file in
  /// `drift_schemas/`.
  static const currentSchema = 11;

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
              case 3:
                await migrateV3ToV4(m, this);
              case 4:
                await migrateV4ToV5(m, this);
              case 5:
                await migrateV5ToV6(m, this);
              case 6:
                await migrateV6ToV7(m, this);
              case 7:
                await migrateV7ToV8(m, this);
              case 8:
                await migrateV8ToV9(m, this);
              case 9:
                await migrateV9ToV10(m, this);
              case 10:
                await migrateV10ToV11(m, this);
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
        expenseCategories,
        expenses,
        goals,
        purchasePauses,
        scheduleBlocks,
        scheduleAdjustments,
        appClasses,
        appUsageDays,
        dnsDomains,
        foodHandlingFlags,
        receiptLinks,
        payWeeks,
        cashCounts,
        dayCloses,
        interactionCategories,
        dayCloseInteractions,
      ];
}
