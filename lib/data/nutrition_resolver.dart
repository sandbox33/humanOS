import 'package:humanos_core/humanos_core.dart';

import 'nutrients.dart';
import 'reference_db.dart';
import 'text_fold.dart';

/// User flags of a reference food.
class FoodFlags {
  const FoodFlags({this.excluded = false, this.triggersReflux = false});
  final bool excluded;
  final bool triggersReflux;
}

/// A meal item resolved to a name and per-100 g nutrient profile.
class ResolvedFood {
  const ResolvedFood({
    required this.name,
    required this.profile,
    required this.known,
    this.foodId,
    this.barcode,
    this.recipeId,
    this.isBeverage = false,
    this.isRaw = false,
    this.ironHeme,
    this.inhibitsNonHemeIron = false,
    this.flags = const FoodFlags(),
    this.nova,
    this.properties,
  });

  final String name;
  final NutrientProfile profile;

  /// False when the item points to data that is not installed.
  final bool known;
  final int? foodId;
  final String? barcode;
  final int? recipeId;
  final bool isBeverage;
  final bool isRaw;
  final bool? ironHeme;
  final bool inhibitsNonHemeIron;
  final FoodFlags flags;
  final int? nova;
  final FoodProperties? properties;

  /// Nutrients of [grams] for the interaction rules.
  NutrientItem toNutrientItem(double grams) => NutrientItem(
        name: name,
        grams: grams,
        ironMg: profile.forGrams(NutrientKey.iron, grams),
        vitaminCMg: profile.forGrams(NutrientKey.vitaminC, grams),
        calciumMg: profile.forGrams(NutrientKey.calcium, grams),
        fiberG: profile.forGrams(NutrientKey.fiber, grams),
        fatG: profile.forGrams(NutrientKey.fat, grams),
        ironHeme: ironHeme,
        inhibitsNonHemeIron: inhibitsNonHemeIron,
        isRaw: isRaw,
        triggersReflux: flags.triggersReflux,
      );
}

/// Resolves foods, packaged products and recipes. Works without a
/// reference database: unknown items keep their id and show "sin dato".
class NutritionResolver {
  NutritionResolver({
    this.reference,
    Map<String, ProductRecord> cachedProducts = const {},
    Map<int, FoodFlags> flags = const {},
  })  : _cached = cachedProducts,
        _flagsById = flags;

  final ReferenceDb? reference;
  final Map<String, ProductRecord> _cached;
  final Map<int, FoodFlags> _flagsById;
  final Map<int, ResolvedFood> _foodCache = {};
  final Map<String, ResolvedFood> _productCache = {};

  ResolvedFood resolve({int? foodId, String? barcode, int? recipeId}) {
    if (recipeId != null) return _recipe(recipeId);
    if (foodId != null) return _food(foodId);
    if (barcode != null) return _product(barcode);
    return const ResolvedFood(
      name: 'Elemento vacío',
      profile: NutrientProfile({}),
      known: false,
    );
  }

  ResolvedFood _food(int id) => _foodCache.putIfAbsent(id, () {
        final db = reference;
        final food = db?.food(id);
        if (db == null || food == null) {
          return ResolvedFood(
            name: 'Alimento #$id (base no instalada)',
            profile: const NutrientProfile({}),
            known: false,
            foodId: id,
          );
        }
        final props = db.properties(id);
        return ResolvedFood(
          name: food.nameEs,
          profile: db.profile(id) ?? const NutrientProfile({}),
          known: true,
          foodId: id,
          isBeverage: food.isBeverage,
          isRaw: food.isRaw,
          ironHeme: props?.ironHeme,
          inhibitsNonHemeIron: props?.inhibitsNonHemeIron ?? false,
          flags: _flagsById[id] ?? const FoodFlags(),
          nova: props?.nova,
          properties: props,
        );
      });

  ProductRecord? product(String barcode) =>
      reference?.product(barcode) ?? _cached[barcode];

  ResolvedFood _product(String barcode) =>
      _productCache.putIfAbsent(barcode, () {
        final product = this.product(barcode);
        if (product == null) {
          return ResolvedFood(
            name: 'Producto $barcode (sin datos)',
            profile: const NutrientProfile({}),
            known: false,
            barcode: barcode,
          );
        }
        final ingredients = foldText(product.ingredients ?? '');
        return ResolvedFood(
          name: product.displayName,
          profile: NutrientProfile.fromProduct(product),
          known: true,
          barcode: barcode,
          nova: product.nova,
          inhibitsNonHemeIron:
              RegExp(r'\b(cafe|te negro|te verde|cacao)\b').hasMatch(ingredients),
        );
      });

  ResolvedFood _recipe(int id) {
    final db = reference;
    final recipe = db?.recipe(id);
    if (db == null || recipe == null) {
      return ResolvedFood(
        name: 'Receta #$id (base no instalada)',
        profile: const NutrientProfile({}),
        known: false,
        recipeId: id,
      );
    }
    final parts = <(NutrientProfile, double)>[];
    var known = true;
    for (final item in recipe.items) {
      final part = item.foodId != null
          ? _food(item.foodId!)
          : _product(item.barcode ?? '');
      known = known && part.known;
      parts.add((part.profile, item.grams));
    }
    return ResolvedFood(
      name: recipe.nameEs,
      profile: NutrientProfile.mix(parts),
      known: known,
      recipeId: id,
    );
  }
}
