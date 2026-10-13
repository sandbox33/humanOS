import 'dart:convert';

import 'package:http/http.dart' as http;

import 'reference_models.dart';

/// Live Open Food Facts lookup by barcode — the only network call of the
/// app, used for products missing from the bundled database.
class OffClient {
  OffClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _fields =
      'code,product_name,product_name_es,brands,countries_tags,nova_group,'
      'nutriscore_grade,additives_tags,ingredients_text,ingredients_text_es,nutriments';

  /// Returns the raw JSON of the product, or null when OFF does not know it.
  Future<String?> fetchJson(String barcode) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$barcode.json',
      {'fields': _fields},
    );
    final response = await _client.get(uri, headers: {
      'User-Agent': 'HumanOS/3.0 (app personal; https://github.com/sandbox33/humanOS)',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw OffException('Open Food Facts respondió ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['status'] != 1) return null;
    return body;
  }
}

class OffException implements Exception {
  const OffException(this.message);
  final String message;
  @override
  String toString() => message;
}

double? _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

double? _bounded(Object? value, double max) {
  final v = _num(value);
  if (v == null || v < 0 || v > max) return null;
  return v;
}

/// Parses an OFF API v2 answer. Label values per 100 g are kept as given;
/// implausible ones become null.
ProductRecord? parseOffProduct(String json, {bool fromCache = true}) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) return null;
  final product = decoded['product'];
  if (product is! Map<String, dynamic>) return null;
  final code = (decoded['code'] ?? product['code'])?.toString();
  final name = ((product['product_name_es'] as String?)?.trim().isNotEmpty ?? false)
      ? product['product_name_es'] as String
      : product['product_name'] as String?;
  if (code == null || name == null || name.trim().isEmpty) return null;
  final n = product['nutriments'];
  final nutriments = n is Map<String, dynamic> ? n : const <String, dynamic>{};
  final sodiumG = _bounded(nutriments['sodium_100g'], 40);
  final nova = _num(product['nova_group'])?.round();
  final tags = product['countries_tags'];
  final additives = product['additives_tags'];
  final ingredients =
      ((product['ingredients_text_es'] as String?)?.trim().isNotEmpty ?? false)
          ? product['ingredients_text_es'] as String
          : product['ingredients_text'] as String?;
  return ProductRecord(
    barcode: code,
    name: name.trim(),
    brand: (product['brands'] as String?)?.trim(),
    countries: tags is List ? tags.join(',') : null,
    nova: nova != null && nova >= 1 && nova <= 4 ? nova : null,
    novaSource: nova != null ? 'off' : null,
    nutriscore: product['nutriscore_grade'] as String?,
    additives: additives is List ? additives.join(',') : null,
    ingredients: ingredients,
    kcal100g: _bounded(nutriments['energy-kcal_100g'], 900),
    protein100g: _bounded(nutriments['proteins_100g'], 100),
    fat100g: _bounded(nutriments['fat_100g'], 100),
    carb100g: _bounded(nutriments['carbohydrates_100g'], 100),
    sugars100g: _bounded(nutriments['sugars_100g'], 100),
    fiber100g: _bounded(nutriments['fiber_100g'], 100),
    sodiumMg100g: sodiumG == null ? null : sodiumG * 1000,
    fromCache: fromCache,
  );
}
