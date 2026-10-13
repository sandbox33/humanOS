import 'package:humanos_core/humanos_core.dart';

/// What a search result points to.
enum CatalogKind { food, product, recipe }

class CatalogHit {
  const CatalogHit({
    required this.kind,
    required this.title,
    this.foodId,
    this.barcode,
    this.recipeId,
    this.subtitle,
    this.kcal100g,
  });

  final CatalogKind kind;
  final String title;
  final int? foodId;
  final String? barcode;
  final int? recipeId;
  final String? subtitle;
  final double? kcal100g;
}

class FoodProperties {
  const FoodProperties({
    required this.macroDominant,
    required this.energyDensityKcalG,
    required this.inhibitsNonHemeIron,
    required this.confidence,
    this.gi,
    this.giRef,
    this.glPer100g,
    this.resistantStarchNote,
    this.diaas,
    this.diaasRef,
    this.limitingAa,
    this.leucineG100g,
    this.nova,
    this.novaSource,
    this.gastricHeuristic,
    this.antinutrientNote,
    this.allergens,
    this.nrf93Per100kcal,
    this.ironHeme,
  });

  final String macroDominant;
  final double energyDensityKcalG;
  final bool inhibitsNonHemeIron;
  final Confidence confidence;
  final double? gi;
  final String? giRef;
  final double? glPer100g;
  final String? resistantStarchNote;
  final double? diaas;
  final String? diaasRef;
  final String? limitingAa;
  final double? leucineG100g;
  final int? nova;
  final String? novaSource;
  final double? gastricHeuristic;
  final String? antinutrientNote;
  final String? allergens;
  final double? nrf93Per100kcal;
  final bool? ironHeme;
}

class NutrientValue {
  const NutrientValue({
    required this.fdcId,
    required this.nameEs,
    required this.unit,
    required this.category,
    required this.amountPer100g,
  });

  final int fdcId;
  final String nameEs;
  final String unit;
  final String category;
  final double amountPer100g;
}

class SourceRecord {
  const SourceRecord({
    required this.code,
    required this.name,
    required this.license,
    required this.url,
    required this.version,
  });

  final String code;
  final String name;
  final String license;
  final String url;
  final String version;
}

class FoodRecord {
  const FoodRecord({
    required this.id,
    required this.nameEs,
    required this.group,
    required this.ripeness,
    required this.sourceRef,
    required this.source,
    this.nameEn,
    this.state,
    this.proxyOf,
  });

  final int id;
  final String nameEs;
  final String? nameEn;
  final String group;
  final String? state;
  final String ripeness;
  final String sourceRef;
  final SourceRecord source;
  final int? proxyOf;

  bool get isRaw => state == 'raw';

  bool get isBeverage => group == 'Bebidas';
}

class ProductRecord {
  const ProductRecord({
    required this.barcode,
    required this.name,
    this.brand,
    this.countries,
    this.nova,
    this.novaSource,
    this.nutriscore,
    this.additives,
    this.ingredients,
    this.kcal100g,
    this.protein100g,
    this.fat100g,
    this.carb100g,
    this.sugars100g,
    this.fiber100g,
    this.sodiumMg100g,
    this.fromCache = false,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String? countries;
  final int? nova;
  final String? novaSource;
  final String? nutriscore;
  final String? additives;
  final String? ingredients;
  final double? kcal100g;
  final double? protein100g;
  final double? fat100g;
  final double? carb100g;
  final double? sugars100g;
  final double? fiber100g;
  final double? sodiumMg100g;

  /// Came from the online lookup cache, not from the bundled database.
  final bool fromCache;

  String get displayName => brand == null ? name : '$name · $brand';
}

class RecipeItemRecord {
  const RecipeItemRecord({this.foodId, this.barcode, required this.grams});
  final int? foodId;
  final String? barcode;
  final double grams;
}

class RecipeRecord {
  const RecipeRecord({required this.id, required this.nameEs, required this.items});
  final int id;
  final String nameEs;
  final List<RecipeItemRecord> items;

  double get totalGrams => items.fold(0.0, (s, i) => s + i.grams);
}

class ExerciseRecord {
  const ExerciseRecord({
    required this.id,
    required this.nameEs,
    required this.equipment,
    required this.muscles,
    required this.failureSafe,
    required this.repMin,
    required this.repMax,
    required this.minIncrementKg,
    required this.tempo,
    required this.cueEs,
    this.substituteId,
  });

  final int id;
  final String nameEs;
  final String equipment;
  final String muscles;
  final bool failureSafe;
  final int repMin;
  final int repMax;
  final double minIncrementKg;
  final String tempo;
  final String cueEs;
  final int? substituteId;

  /// The load is machine assistance: progressing means less of it.
  bool get assisted => equipment == 'maquina_asistida';

  /// Reps are seconds held.
  bool get timed => equipment == 'carga_tiempo' || equipment == 'tiempo';

  ExerciseSpec toSpec() => ExerciseSpec(
        id: id,
        nameEs: nameEs,
        repMin: repMin,
        repMax: repMax,
        minIncrementKg: minIncrementKg,
        failureSafe: failureSafe,
        assisted: assisted,
        timed: timed,
      );
}
