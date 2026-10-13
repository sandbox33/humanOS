import 'package:humanos_core/humanos_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'nutrients.dart';
import 'reference_models.dart';
import 'text_fold.dart';

export 'reference_models.dart';

/// Read-only access to `reference.sqlite` (built by the ETL).
///
/// Queries are small and fast (FTS5 over ~20 k names), so they run
/// synchronously; callers wrap them in providers.
class ReferenceDb {
  ReferenceDb._(this._db);

  /// Opens an installed copy read-only.
  factory ReferenceDb.open(String path) =>
      ReferenceDb._(sqlite3.open(path, mode: OpenMode.readOnly));

  /// Wraps an already opened database (tests).
  factory ReferenceDb.fromDatabase(Database db) => ReferenceDb._(db);

  final Database _db;
  final Map<String, SourceRecord> _sources = {};

  int get userVersion => _db.userVersion;

  void close() => _db.close();

  Iterable<Row> _select(String sql, [List<Object?> args = const []]) =>
      _db.select(sql, args);

  static double? _d(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _i(Object? v) => v == null ? null : (v as num).toInt();

  // ------------------------------------------------------------ sources
  List<SourceRecord> sources() => [
        for (final r in _select(
            'SELECT code, name, license, url, version FROM sources ORDER BY id'))
          SourceRecord(
            code: r['code'] as String,
            name: r['name'] as String,
            license: r['license'] as String,
            url: r['url'] as String,
            version: r['version'] as String,
          ),
      ];

  SourceRecord _source(int id) {
    final key = '$id';
    final cached = _sources[key];
    if (cached != null) return cached;
    final r = _select(
        'SELECT code, name, license, url, version FROM sources WHERE id = ?',
        [id]).first;
    return _sources[key] = SourceRecord(
      code: r['code'] as String,
      name: r['name'] as String,
      license: r['license'] as String,
      url: r['url'] as String,
      version: r['version'] as String,
    );
  }

  // ------------------------------------------------------------- search
  /// Foods, recipes and packaged products matching [query] (accent and
  /// case insensitive, prefix per word).
  List<CatalogHit> search(String query, {int limit = 40}) {
    final match = ftsQuery(query);
    if (match.isEmpty) return const [];
    final hits = <CatalogHit>[];

    final folded = foldText(query).trim();
    for (final r in _select('SELECT id, name_es FROM recipes ORDER BY id')) {
      final name = r['name_es'] as String;
      if (foldText(name).contains(folded)) {
        hits.add(CatalogHit(
          kind: CatalogKind.recipe,
          title: name,
          recipeId: r['id'] as int,
          subtitle: 'Receta',
        ));
      }
    }

    final ids = <int>[];
    for (final r in _select(
        'SELECT food_id FROM food_names_fts WHERE food_names_fts MATCH ? '
        'ORDER BY rank LIMIT 300',
        [match])) {
      final id = int.parse('${r['food_id']}');
      if (!ids.contains(id)) ids.add(id);
      if (ids.length >= limit) break;
    }
    if (ids.isNotEmpty) {
      final rows = {
        for (final r in _select(
            'SELECT f.id, f.canonical_name_es, f.food_group, '
            'p.energy_density_kcal_g FROM foods f '
            'JOIN food_properties p ON p.food_id = f.id '
            'WHERE f.id IN (${List.filled(ids.length, '?').join(',')})',
            ids))
          r['id'] as int: r,
      };
      for (final id in ids) {
        final r = rows[id];
        if (r == null) continue;
        final density = _d(r['energy_density_kcal_g']);
        hits.add(CatalogHit(
          kind: CatalogKind.food,
          title: r['canonical_name_es'] as String,
          foodId: id,
          subtitle: r['food_group'] as String,
          kcal100g: density == null ? null : density * 100,
        ));
      }
    }

    final barcodes = [
      for (final r in _select(
          'SELECT barcode FROM products_fts WHERE products_fts MATCH ? '
          'ORDER BY rank LIMIT ?',
          [match, limit ~/ 2]))
        '${r['barcode']}',
    ];
    if (barcodes.isNotEmpty) {
      final rows = {
        for (final r in _select(
            'SELECT barcode, name, brand, kcal_100g FROM products WHERE barcode IN '
            '(${List.filled(barcodes.length, '?').join(',')})',
            barcodes))
          r['barcode'] as String: r,
      };
      for (final code in barcodes) {
        final r = rows[code];
        if (r == null) continue;
        final brand = r['brand'] as String?;
        hits.add(CatalogHit(
          kind: CatalogKind.product,
          title: r['name'] as String,
          barcode: code,
          subtitle: brand == null ? 'Producto' : 'Producto · $brand',
          kcal100g: _d(r['kcal_100g']),
        ));
      }
    }
    return hits;
  }

  // -------------------------------------------------------------- foods
  FoodRecord? food(int id) {
    final rows = _select(
        'SELECT id, source_id, source_ref, canonical_name_es, canonical_name_en, '
        'food_group, state, ripeness, proxy_of FROM foods WHERE id = ?',
        [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return FoodRecord(
      id: r['id'] as int,
      nameEs: r['canonical_name_es'] as String,
      nameEn: r['canonical_name_en'] as String?,
      group: r['food_group'] as String,
      state: r['state'] as String?,
      ripeness: r['ripeness'] as String,
      sourceRef: r['source_ref'] as String,
      source: _source(r['source_id'] as int),
      proxyOf: _i(r['proxy_of']),
    );
  }

  /// Names for many foods at once (missing ids are absent).
  Map<int, String> foodNames(Iterable<int> ids) {
    final list = ids.toSet().toList();
    final result = <int, String>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      for (final r in _select(
          'SELECT id, canonical_name_es FROM foods WHERE id IN '
          '(${List.filled(chunk.length, '?').join(',')})',
          chunk)) {
        result[r['id'] as int] = r['canonical_name_es'] as String;
      }
    }
    return result;
  }

  List<String> names(int foodId) => [
        for (final r in _select(
            'SELECT name FROM food_names WHERE food_id = ? ORDER BY is_primary DESC, name',
            [foodId]))
          r['name'] as String,
      ];

  FoodProperties? properties(int foodId) {
    final rows =
        _select('SELECT * FROM food_properties WHERE food_id = ?', [foodId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final heme = _i(r['iron_heme']);
    return FoodProperties(
      macroDominant: r['macro_dominant'] as String,
      energyDensityKcalG: _d(r['energy_density_kcal_g'])!,
      inhibitsNonHemeIron: (_i(r['inhibits_nonheme_iron']) ?? 0) == 1,
      confidence: Confidence.parse(r['confidence'] as String?),
      gi: _d(r['gi']),
      giRef: r['gi_ref'] as String?,
      glPer100g: _d(r['gl_per_100g']),
      resistantStarchNote: r['resistant_starch_note'] as String?,
      diaas: _d(r['diaas']),
      diaasRef: r['diaas_ref'] as String?,
      limitingAa: r['limiting_aa'] as String?,
      leucineG100g: _d(r['leucine_g_100g']),
      nova: _i(r['nova']),
      novaSource: r['nova_source'] as String?,
      gastricHeuristic: _d(r['gastric_heuristic']),
      antinutrientNote: r['antinutrient_note'] as String?,
      allergens: r['allergens'] as String?,
      nrf93Per100kcal: _d(r['nrf93_per_100kcal']),
      ironHeme: heme == null ? null : heme == 1,
    );
  }

  /// Full per-100 g nutrient list of a food, grouped by category.
  List<NutrientValue> nutrients(int foodId) => [
        for (final r in _select(
            'SELECT n.fdc_nutrient_id, n.name_es, n.unit, n.category, '
            'fn.amount_per_100g FROM food_nutrients fn '
            'JOIN nutrients n ON n.id = fn.nutrient_id '
            'WHERE fn.food_id = ? ORDER BY n.category, n.name_es',
            [foodId]))
          NutrientValue(
            fdcId: r['fdc_nutrient_id'] as int,
            nameEs: r['name_es'] as String,
            unit: r['unit'] as String,
            category: r['category'] as String,
            amountPer100g: _d(r['amount_per_100g'])!,
          ),
      ];

  /// Nutrient catalogue (every nutrient present in the database).
  List<(int, String, String, String)> nutrientCatalog() => [
        for (final r in _select(
            'SELECT fdc_nutrient_id, name_es, unit, category FROM nutrients '
            'ORDER BY category, name_es'))
          (
            r['fdc_nutrient_id'] as int,
            r['name_es'] as String,
            r['unit'] as String,
            r['category'] as String,
          ),
      ];

  NutrientProfile? profile(int foodId) => profiles([foodId])[foodId];

  /// Per-100 g profiles for many foods in one pass.
  Map<int, NutrientProfile> profiles(Iterable<int> foodIds) {
    final list = foodIds.toSet().toList();
    final values = <int, Map<int, double>>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      for (final r in _select(
          'SELECT food_id, nutrient_id, amount_per_100g FROM food_nutrients '
          'WHERE food_id IN (${List.filled(chunk.length, '?').join(',')})',
          chunk)) {
        (values[r['food_id'] as int] ??= {})[r['nutrient_id'] as int] =
            _d(r['amount_per_100g'])!;
      }
    }
    return {
      for (final id in list)
        if (values.containsKey(id)) id: NutrientProfile(values[id]!),
    };
  }

  // ----------------------------------------------------------- products
  ProductRecord? product(String barcode) {
    final rows =
        _select('SELECT * FROM products WHERE barcode = ?', [barcode]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ProductRecord(
      barcode: r['barcode'] as String,
      name: r['name'] as String,
      brand: r['brand'] as String?,
      countries: r['countries'] as String?,
      nova: _i(r['nova']),
      novaSource: r['nova_source'] as String?,
      nutriscore: r['nutriscore'] as String?,
      additives: r['additives'] as String?,
      ingredients: r['ingredients_text'] as String?,
      kcal100g: _d(r['kcal_100g']),
      protein100g: _d(r['protein_100g']),
      fat100g: _d(r['fat_100g']),
      carb100g: _d(r['carb_100g']),
      sugars100g: _d(r['sugars_100g']),
      fiber100g: _d(r['fiber_100g']),
      sodiumMg100g: _d(r['sodium_mg_100g']),
    );
  }

  // ------------------------------------------------------------ recipes
  List<RecipeRecord> recipes() => [
        for (final r in _select('SELECT id, name_es FROM recipes ORDER BY id'))
          RecipeRecord(
            id: r['id'] as int,
            nameEs: r['name_es'] as String,
            items: _recipeItems(r['id'] as int),
          ),
      ];

  RecipeRecord? recipe(int id) {
    final rows = _select('SELECT id, name_es FROM recipes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return RecipeRecord(
      id: id,
      nameEs: rows.first['name_es'] as String,
      items: _recipeItems(id),
    );
  }

  List<RecipeItemRecord> _recipeItems(int recipeId) => [
        for (final r in _select(
            'SELECT food_id, barcode, grams FROM recipe_items WHERE recipe_id = ?',
            [recipeId]))
          RecipeItemRecord(
            foodId: _i(r['food_id']),
            barcode: r['barcode'] as String?,
            grams: _d(r['grams'])!,
          ),
      ];

  // ---------------------------------------------------------- exercises
  List<ExerciseRecord> exercises() => [
        for (final r in _select('SELECT * FROM exercises ORDER BY id'))
          ExerciseRecord(
            id: r['id'] as int,
            nameEs: r['name_es'] as String,
            equipment: r['equipment'] as String,
            muscles: r['muscles'] as String,
            failureSafe: (r['failure_safe'] as int) == 1,
            repMin: r['rep_min'] as int,
            repMax: r['rep_max'] as int,
            minIncrementKg: _d(r['min_increment_kg'])!,
            tempo: r['tempo'] as String,
            cueEs: r['cue_es'] as String,
            substituteId: _i(r['substitute_id']),
          ),
      ];

  /// Template code (`A`, `B`, `BASELINE`) → exercise ids in order.
  Map<String, List<int>> templates() {
    final result = <String, List<int>>{};
    for (final r in _select(
        'SELECT template, exercise_id FROM exercise_templates ORDER BY template, position')) {
      (result[r['template'] as String] ??= []).add(r['exercise_id'] as int);
    }
    return result;
  }
}
