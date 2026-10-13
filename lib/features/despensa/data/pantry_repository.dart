import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/nutrition_resolver.dart';
import '../../../data/off_client.dart';
import '../../../data/reference_models.dart';
import '../../../data/user_db.dart';

class PantryRepository {
  PantryRepository(this._db);
  final UserDb _db;

  Stream<List<PantryItemRow>> watchStock() => (_db.select(_db.pantryItems)
        ..where((t) => t.gramsRemaining.isBiggerThanValue(0))
        ..orderBy([(t) => OrderingTerm.asc(t.expiresOn), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<List<PantryItemRow>> stockFor({int? foodId, String? barcode}) {
    final query = _db.select(_db.pantryItems)
      ..where((t) => t.gramsRemaining.isBiggerThanValue(0));
    if (foodId != null) {
      query.where((t) => t.foodId.equals(foodId));
    } else if (barcode != null) {
      query.where((t) => t.barcode.equals(barcode));
    } else {
      return Future.value(const []);
    }
    query.orderBy([(t) => OrderingTerm.asc(t.expiresOn)]);
    return query.get();
  }

  Future<int> addItem({
    int? foodId,
    String? barcode,
    required double grams,
    double? priceUsdPerKg,
    String? purchasedOn,
    String? expiresOn,
    int? purchaseId,
  }) =>
      _db.into(_db.pantryItems).insert(PantryItemsCompanion.insert(
            gramsRemaining: grams,
            foodId: Value(foodId),
            barcode: Value(barcode),
            priceUsdPerKg: Value(priceUsdPerKg),
            purchasedOn: Value(purchasedOn),
            expiresOn: Value(expiresOn),
            purchaseId: Value(purchaseId),
          ));

  Future<void> updateItem(PantryItemRow item, {double? grams, double? price, String? expiresOn}) =>
      (_db.update(_db.pantryItems)..where((t) => t.id.equals(item.id))).write(
        PantryItemsCompanion(
          gramsRemaining: grams == null ? const Value.absent() : Value(grams < 0 ? 0 : grams),
          priceUsdPerKg: price == null ? const Value.absent() : Value(price),
          expiresOn: expiresOn == null ? const Value.absent() : Value(expiresOn),
        ),
      );

  Future<void> deleteItem(int id) =>
      (_db.delete(_db.pantryItems)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------- purchases
  Stream<List<PurchaseRow>> watchPurchases() => (_db.select(_db.purchases)
        ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Future<int> addPurchase({
    required String date,
    String? store,
    double? totalUsd,
    String? rawText,
  }) =>
      _db.into(_db.purchases).insert(PurchasesCompanion.insert(
            date: date,
            store: Value(store),
            totalUsd: Value(totalUsd),
            rawText: Value(rawText),
          ));

  Future<List<PantryItemRow>> purchaseItems(int purchaseId) =>
      (_db.select(_db.pantryItems)..where((t) => t.purchaseId.equals(purchaseId))).get();

  // ------------------------------------------------------- cooked batches
  Stream<List<CookedBatchRow>> watchOpenBatches() => (_db.select(_db.cookedBatches)
        ..where((t) => t.closedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.cookedAt)]))
      .watch();

  Future<int> addBatch({
    int? foodId,
    int? recipeId,
    double? grams,
    required DateTime cookedAt,
    required bool heatExposed,
    required bool refrigerated,
  }) =>
      _db.into(_db.cookedBatches).insert(CookedBatchesCompanion.insert(
            cookedAt: cookedAt.toIso8601String(),
            foodId: Value(foodId),
            recipeId: Value(recipeId),
            grams: Value(grams),
            heatExposed: Value(heatExposed),
            refrigerated: Value(refrigerated),
          ));

  Future<void> setBatchStorage(int id, {bool? heatExposed, bool? refrigerated}) =>
      (_db.update(_db.cookedBatches)..where((t) => t.id.equals(id))).write(
        CookedBatchesCompanion(
          heatExposed: heatExposed == null ? const Value.absent() : Value(heatExposed),
          refrigerated: refrigerated == null ? const Value.absent() : Value(refrigerated),
        ),
      );

  Future<void> closeBatch(int id, {required bool eaten, required DateTime at}) =>
      (_db.update(_db.cookedBatches)..where((t) => t.id.equals(id))).write(
        CookedBatchesCompanion(
          closedAt: Value(at.toIso8601String()),
          outcome: Value(eaten ? 'eaten' : 'discarded'),
        ),
      );

  // ------------------------------------------------------------ flags
  Stream<Map<int, FoodFlags>> watchFlags() => _db.select(_db.foodUserFlags).watch().map(
        (rows) => {
          for (final r in rows)
            r.foodId: FoodFlags(excluded: r.userExcluded, triggersReflux: r.userTriggerReflux),
        },
      );

  Future<void> setFlags(int foodId, {required bool excluded, required bool reflux}) =>
      _db.into(_db.foodUserFlags).insertOnConflictUpdate(FoodUserFlagsCompanion(
            foodId: Value(foodId),
            userExcluded: Value(excluded),
            userTriggerReflux: Value(reflux),
          ));

  // ------------------------------------------------------ product cache
  Stream<Map<String, ProductRecord>> watchCachedProducts() =>
      _db.select(_db.productsCache).watch().map((rows) {
        final result = <String, ProductRecord>{};
        for (final r in rows) {
          final product = parseOffProduct(r.json);
          if (product != null) result[r.barcode] = product;
        }
        return result;
      });

  Future<void> cacheProduct(String barcode, String json, DateTime at) =>
      _db.into(_db.productsCache).insertOnConflictUpdate(ProductsCacheCompanion.insert(
            barcode: barcode,
            json: json,
            fetchedAt: at.toIso8601String(),
          ));

  Future<ProductRecord?> cachedProduct(String barcode) async {
    final row = await (_db.select(_db.productsCache)
          ..where((t) => t.barcode.equals(barcode)))
        .getSingleOrNull();
    return row == null ? null : parseOffProduct(row.json);
  }
}

/// Days until expiry for a pantry row (null when no date).
int? daysToExpiry(PantryItemRow item, DateTime today) {
  final text = item.expiresOn;
  if (text == null || text.isEmpty) return null;
  try {
    return daysBetween(today, parseIsoDate(text));
  } on FormatException {
    return null;
  }
}
