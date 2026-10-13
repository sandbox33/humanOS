import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/off_client.dart';
import '../../../data/reference_models.dart';
import '../../../services/services.dart';
import 'intake.dart';

/// Result of resolving a scanned barcode.
class ProductLookup {
  const ProductLookup({this.product, required this.messageEs, this.online = false});
  final ProductRecord? product;
  final String messageEs;

  /// Fetched now from Open Food Facts (show the ODbL attribution).
  final bool online;
}

/// Local database first, then the offline cache of earlier lookups, and
/// only then Open Food Facts — the app's single network call.
Future<ProductLookup> lookupProduct(WidgetRef ref, String barcode) async {
  final code = barcode.trim();
  final local = ref.read(referenceDbProvider)?.product(code);
  if (local != null) {
    return ProductLookup(product: local, messageEs: 'Producto de la base local.');
  }
  final pantry = ref.read(pantryRepositoryProvider);
  final cached = await pantry.cachedProduct(code);
  if (cached != null) {
    return ProductLookup(
      product: cached,
      messageEs: 'Guardado de una búsqueda anterior en Open Food Facts.',
    );
  }
  try {
    final json = await ref.read(offClientProvider).fetchJson(code);
    if (json == null) {
      return const ProductLookup(messageEs: 'Open Food Facts no conoce este código.');
    }
    final product = parseOffProduct(json, fromCache: false);
    if (product == null) {
      return const ProductLookup(messageEs: 'Open Food Facts respondió sin datos útiles.');
    }
    await pantry.cacheProduct(code, json, ref.read(clockProvider)());
    return ProductLookup(
      product: product,
      online: true,
      messageEs: 'Datos de Open Food Facts (licencia ODbL), guardados para usarlos sin conexión.',
    );
  } on Object catch (e) {
    return ProductLookup(messageEs: 'Sin conexión o error de Open Food Facts: $e');
  }
}
