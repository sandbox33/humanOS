import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';

/// A meal with its items.
class MealEntry {
  const MealEntry(this.meal, this.items);
  final MealRow meal;
  final List<MealItemRow> items;

  MealBlock get block => MealBlock.parse(meal.block);
}

/// Outcome of logging an item from the pantry. Low stock never blocks.
class StockResult {
  const StockResult({this.availableG, this.requestedG, this.remainingG});
  final double? availableG;
  final double? requestedG;
  final double? remainingG;

  bool get insufficient =>
      availableG != null && requestedG != null && requestedG! > availableG! + 1e-9;
}

class MealsRepository {
  MealsRepository(this._db);
  final UserDb _db;

  Stream<List<MealEntry>> watchDay(String date) {
    final query = _db.select(_db.meals).join([
      leftOuterJoin(_db.mealItems, _db.mealItems.mealId.equalsExp(_db.meals.id)),
    ])
      ..where(_db.meals.date.equals(date))
      ..orderBy([OrderingTerm.asc(_db.meals.id), OrderingTerm.asc(_db.mealItems.id)]);
    return query.watch().map(_group);
  }

  Future<List<MealEntry>> dayEntries(String date) async {
    final query = _db.select(_db.meals).join([
      leftOuterJoin(_db.mealItems, _db.mealItems.mealId.equalsExp(_db.meals.id)),
    ])
      ..where(_db.meals.date.equals(date));
    return _group(await query.get());
  }

  /// Every item between two dates (inclusive), grouped by day.
  Future<Map<String, List<MealItemRow>>> itemsBetween(String from, String to) async {
    final query = _db.select(_db.meals).join([
      innerJoin(_db.mealItems, _db.mealItems.mealId.equalsExp(_db.meals.id)),
    ])
      ..where(_db.meals.date.isBetweenValues(from, to));
    final result = <String, List<MealItemRow>>{};
    for (final row in await query.get()) {
      final meal = row.readTable(_db.meals);
      (result[meal.date] ??= []).add(row.readTable(_db.mealItems));
    }
    return result;
  }

  /// Live items between two dates (inclusive), grouped by day.
  Stream<Map<String, List<MealItemRow>>> watchItemsBetween(String from, String to) {
    final query = _db.select(_db.meals).join([
      innerJoin(_db.mealItems, _db.mealItems.mealId.equalsExp(_db.meals.id)),
    ])
      ..where(_db.meals.date.isBetweenValues(from, to));
    return query.watch().map((rows) {
      final result = <String, List<MealItemRow>>{};
      for (final row in rows) {
        final meal = row.readTable(_db.meals);
        (result[meal.date] ??= []).add(row.readTable(_db.mealItems));
      }
      return result;
    });
  }

  List<MealEntry> _group(List<TypedResult> rows) {
    final meals = <int, MealRow>{};
    final items = <int, List<MealItemRow>>{};
    for (final row in rows) {
      final meal = row.readTable(_db.meals);
      meals[meal.id] = meal;
      final item = row.readTableOrNull(_db.mealItems);
      (items[meal.id] ??= []);
      if (item != null) items[meal.id]!.add(item);
    }
    return [for (final m in meals.values) MealEntry(m, items[m.id] ?? const [])];
  }

  Future<int> _mealFor(String date, MealBlock block, {int? templateId}) async {
    final existing = await (_db.select(_db.meals)
          ..where((t) => t.date.equals(date) & t.block.equals(block.code))
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing.id;
    return _db.into(_db.meals).insert(MealsCompanion.insert(
          date: date,
          block: block.code,
          templateId: Value(templateId),
        ));
  }

  /// Logs an item. When it comes from the pantry the stock is decremented
  /// (never below zero); insufficient stock is reported, not refused.
  Future<StockResult> addItem({
    required String date,
    required MealBlock block,
    required double grams,
    int? foodId,
    String? barcode,
    int? recipeId,
    int? pantryItemId,
  }) {
    return _db.transaction(() async {
      final mealId = await _mealFor(date, block);
      await _db.into(_db.mealItems).insert(MealItemsCompanion.insert(
            mealId: mealId,
            grams: grams,
            foodId: Value(foodId),
            barcode: Value(barcode),
            recipeId: Value(recipeId),
            pantryItemId: Value(pantryItemId),
          ));
      if (pantryItemId == null) return const StockResult();
      final pantry = await (_db.select(_db.pantryItems)
            ..where((t) => t.id.equals(pantryItemId)))
          .getSingleOrNull();
      if (pantry == null) return const StockResult();
      final remaining = pantry.gramsRemaining - grams;
      final clamped = remaining < 0 ? 0.0 : remaining;
      await (_db.update(_db.pantryItems)..where((t) => t.id.equals(pantryItemId)))
          .write(PantryItemsCompanion(gramsRemaining: Value(clamped)));
      return StockResult(
        availableG: pantry.gramsRemaining,
        requestedG: grams,
        remainingG: clamped,
      );
    });
  }

  /// Changes the grams of a logged item. Pantry stock follows the change
  /// (never below zero); insufficient stock is reported, not refused.
  Future<StockResult> updateItemGrams(MealItemRow item, double grams) {
    return _db.transaction(() async {
      await (_db.update(_db.mealItems)..where((t) => t.id.equals(item.id)))
          .write(MealItemsCompanion(grams: Value(grams)));
      final pantryId = item.pantryItemId;
      if (pantryId == null) return const StockResult();
      final pantry = await (_db.select(_db.pantryItems)
            ..where((t) => t.id.equals(pantryId)))
          .getSingleOrNull();
      if (pantry == null) return const StockResult();
      final extra = grams - item.grams;
      final remaining = pantry.gramsRemaining - extra;
      final clamped = remaining < 0 ? 0.0 : remaining;
      await (_db.update(_db.pantryItems)..where((t) => t.id.equals(pantryId)))
          .write(PantryItemsCompanion(gramsRemaining: Value(clamped)));
      return StockResult(
        availableG: pantry.gramsRemaining,
        requestedG: extra > 0 ? extra : 0,
        remainingG: clamped,
      );
    });
  }

  /// Deletes an item; grams taken from the pantry go back to it.
  Future<void> removeItem(MealItemRow item) {
    return _db.transaction(() async {
      await (_db.delete(_db.mealItems)..where((t) => t.id.equals(item.id))).go();
      final pantryId = item.pantryItemId;
      if (pantryId != null) {
        final pantry = await (_db.select(_db.pantryItems)
              ..where((t) => t.id.equals(pantryId)))
            .getSingleOrNull();
        if (pantry != null) {
          await (_db.update(_db.pantryItems)..where((t) => t.id.equals(pantryId)))
              .write(PantryItemsCompanion(
                  gramsRemaining: Value(pantry.gramsRemaining + item.grams)));
        }
      }
      final left = await (_db.select(_db.mealItems)
            ..where((t) => t.mealId.equals(item.mealId)))
          .get();
      if (left.isEmpty) {
        await (_db.delete(_db.meals)..where((t) => t.id.equals(item.mealId))).go();
      }
    });
  }

  Stream<List<MealTemplateRow>> watchTemplates() =>
      (_db.select(_db.mealTemplates)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Future<List<MealTemplateItemRow>> templateItems(int templateId) =>
      (_db.select(_db.mealTemplateItems)..where((t) => t.templateId.equals(templateId)))
          .get();

  /// Copies a template's items into a block (without touching the pantry).
  Future<int> applyTemplate(int templateId, String date, MealBlock block) {
    return _db.transaction(() async {
      final items = await templateItems(templateId);
      if (items.isEmpty) return 0;
      final mealId = await _mealFor(date, block, templateId: templateId);
      for (final item in items) {
        await _db.into(_db.mealItems).insert(MealItemsCompanion.insert(
              mealId: mealId,
              grams: item.grams,
              foodId: Value(item.foodId),
              barcode: Value(item.barcode),
              recipeId: Value(item.recipeId),
            ));
      }
      return items.length;
    });
  }

  /// Replaces a template's items with the items of a logged block.
  Future<int> saveAsTemplate(int templateId, List<MealItemRow> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.mealTemplateItems)
            ..where((t) => t.templateId.equals(templateId)))
          .go();
      for (final item in items) {
        await _db.into(_db.mealTemplateItems).insert(MealTemplateItemsCompanion.insert(
              templateId: Value(templateId),
              grams: item.grams,
              foodId: Value(item.foodId),
              barcode: Value(item.barcode),
              recipeId: Value(item.recipeId),
            ));
      }
      return items.length;
    });
  }

  /// Copies yesterday's meals into [date] ("repetir ayer"). The copies are
  /// not linked to the pantry.
  Future<int> repeatDay({required String from, required String to}) {
    return _db.transaction(() async {
      final source = await dayEntries(from);
      var copied = 0;
      for (final entry in source) {
        if (entry.items.isEmpty) continue;
        final mealId = await _mealFor(to, entry.block);
        for (final item in entry.items) {
          await _db.into(_db.mealItems).insert(MealItemsCompanion.insert(
                mealId: mealId,
                grams: item.grams,
                foodId: Value(item.foodId),
                barcode: Value(item.barcode),
                recipeId: Value(item.recipeId),
              ));
          copied++;
        }
      }
      return copied;
    });
  }
}
