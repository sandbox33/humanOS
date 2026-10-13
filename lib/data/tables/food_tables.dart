import 'package:drift/drift.dart';

@DataClassName('PurchaseRow')
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get store => text().nullable()();
  RealColumn get totalUsd => real().nullable()();
  TextColumn get rawText => text().nullable()();
}

@DataClassName('PantryItemRow')
class PantryItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get foodId => integer().nullable()();
  TextColumn get barcode => text().nullable()();
  RealColumn get gramsRemaining =>
      real().check(gramsRemaining.isBiggerOrEqualValue(0))();
  RealColumn get priceUsdPerKg => real().nullable()();
  TextColumn get purchasedOn => text().nullable()();
  TextColumn get expiresOn => text().nullable()();
  IntColumn get purchaseId => integer().nullable().references(Purchases, #id)();

  @override
  List<String> get customConstraints =>
      const ['CHECK (food_id IS NOT NULL OR barcode IS NOT NULL)'];
}

/// Open Food Facts answers fetched online, kept for offline reuse.
@DataClassName('ProductCacheRow')
class ProductsCache extends Table {
  TextColumn get barcode => text()();
  TextColumn get json => text()();
  TextColumn get fetchedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {barcode};
}

@DataClassName('MealTemplateRow')
class MealTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nameEs => text().unique()();
}

@DataClassName('MealTemplateItemRow')
class MealTemplateItems extends Table {
  IntColumn get templateId => integer()
      .nullable()
      .references(MealTemplates, #id, onDelete: KeyAction.cascade)();
  IntColumn get foodId => integer().nullable()();
  TextColumn get barcode => text().nullable()();
  IntColumn get recipeId => integer().nullable()();
  RealColumn get grams => real().check(grams.isBiggerThanValue(0))();
}

@DataClassName('MealRow')
class Meals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get block => text().check(block.isIn(const [
        'BREAKFAST',
        'MID_MORNING',
        'LUNCH',
        'AFTERNOON',
        'DINNER',
        'POST_WORKOUT',
      ]))();
  IntColumn get templateId => integer().nullable()();
}

/// Ids + grams only: no JSON ingredient blobs (CP3).
@DataClassName('MealItemRow')
class MealItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get mealId =>
      integer().references(Meals, #id, onDelete: KeyAction.cascade)();
  IntColumn get foodId => integer().nullable()();
  TextColumn get barcode => text().nullable()();
  IntColumn get recipeId => integer().nullable()();
  RealColumn get grams => real().check(grams.isBiggerThanValue(0))();
  IntColumn get pantryItemId => integer().nullable()();

  @override
  List<String> get customConstraints => const [
        'CHECK (food_id IS NOT NULL OR barcode IS NOT NULL OR recipe_id IS NOT NULL)',
      ];
}

@DataClassName('CookedBatchRow')
class CookedBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get foodId => integer().nullable()();
  IntColumn get recipeId => integer().nullable()();
  RealColumn get grams => real().nullable()();
  TextColumn get cookedAt => text()();
  BoolColumn get heatExposed => boolean().withDefault(const Constant(false))();
  BoolColumn get refrigerated => boolean().withDefault(const Constant(false))();
  TextColumn get closedAt => text().nullable()();
  TextColumn get outcome =>
      text().nullable().check(outcome.isIn(const ['eaten', 'discarded']))();
}

/// User flags for reference foods (the reference DB is read-only).
@DataClassName('FoodUserFlagRow')
class FoodUserFlags extends Table {
  IntColumn get foodId => integer()();
  BoolColumn get userExcluded => boolean().withDefault(const Constant(false))();
  BoolColumn get userTriggerReflux =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {foodId};
}
