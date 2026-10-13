import 'reference_models.dart';

/// Nutrients the app reasons about, mapped to FDC nutrient ids in order of
/// preference (SR Legacy and Foundation Foods use different ids for the same
/// quantity). The ids are identifiers, not nutrient values.
enum NutrientKey {
  energy([1008, 2048, 2047], 'Energía', 'kcal'),
  protein([1003], 'Proteína', 'g'),
  fat([1004, 1085], 'Grasa', 'g'),
  carbs([1005, 1050], 'Carbohidratos', 'g'),
  fiber([1079, 2033], 'Fibra', 'g'),
  sugars([2000, 1063], 'Azúcares', 'g'),
  saturatedFat([1258], 'Grasa saturada', 'g'),
  sodium([1093], 'Sodio', 'mg'),
  potassium([1092], 'Potasio', 'mg'),
  iron([1089], 'Hierro', 'mg'),
  calcium([1087], 'Calcio', 'mg'),
  vitaminC([1162], 'Vitamina C', 'mg'),
  leucine([1213], 'Leucina', 'g');

  const NutrientKey(this.fdcIds, this.labelEs, this.unit);

  final List<int> fdcIds;
  final String labelEs;
  final String unit;
}

/// Per-100 g values of one food. A missing value is unknown, never zero.
class NutrientProfile {
  const NutrientProfile(this.byFdcId);

  /// Builds the profile of a packaged product from its label fields.
  factory NutrientProfile.fromProduct(ProductRecord product) {
    final values = <int, double>{};
    void put(int id, double? v) {
      if (v != null) values[id] = v;
    }

    put(1008, product.kcal100g);
    put(1003, product.protein100g);
    put(1004, product.fat100g);
    put(1005, product.carb100g);
    put(2000, product.sugars100g);
    put(1079, product.fiber100g);
    put(1093, product.sodiumMg100g);
    return NutrientProfile(values);
  }

  final Map<int, double> byFdcId;

  double? per100g(NutrientKey key) {
    for (final id in key.fdcIds) {
      final value = byFdcId[id];
      if (value != null) return value;
    }
    return null;
  }

  double? forGrams(NutrientKey key, double grams) {
    final value = per100g(key);
    return value == null ? null : value * grams / 100;
  }

  /// Weighted mix of several profiles (a recipe): unknown in any part makes
  /// the whole unknown for that nutrient.
  static NutrientProfile mix(List<(NutrientProfile, double)> parts) {
    final totalGrams = parts.fold(0.0, (s, p) => s + p.$2);
    if (totalGrams <= 0) return const NutrientProfile({});
    final ids = <int>{for (final p in parts) ...p.$1.byFdcId.keys};
    final result = <int, double>{};
    for (final id in ids) {
      var sum = 0.0;
      var complete = true;
      for (final (profile, grams) in parts) {
        final v = profile.byFdcId[id];
        if (v == null) {
          complete = false;
          break;
        }
        sum += v * grams / 100;
      }
      if (complete) result[id] = sum / totalGrams * 100;
    }
    return NutrientProfile(result);
  }
}

/// Running totals for a meal or a day. Keeps track of which items had no
/// data, so a sum is shown as a floor ("≥") instead of an exact value.
class NutrientTotals {
  final Map<NutrientKey, double> _sums = {};
  final Map<NutrientKey, List<String>> _missing = {};
  int _items = 0;

  void add(String name, NutrientProfile profile, double grams) {
    _items++;
    for (final key in NutrientKey.values) {
      final value = profile.forGrams(key, grams);
      if (value == null) {
        (_missing[key] ??= []).add(name);
      } else {
        _sums[key] = (_sums[key] ?? 0) + value;
      }
    }
  }

  int get itemCount => _items;

  /// Sum of the known values, or null when no item had data.
  double? value(NutrientKey key) => _sums[key];

  /// Some item lacked data: the total is a floor.
  bool isPartial(NutrientKey key) => (_missing[key] ?? const []).isNotEmpty;

  List<String> missingIn(NutrientKey key) => _missing[key] ?? const [];
}
