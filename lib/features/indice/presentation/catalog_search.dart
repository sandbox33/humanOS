import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/reference_models.dart';
import '../../../data/text_fold.dart';
import '../../despensa/domain/pantry_model.dart';
import '../../registro/domain/product_lookup.dart';
import '../../registro/presentation/scanner_page.dart';

/// What the user picked in a search.
class FoodChoice {
  const FoodChoice({
    required this.name,
    this.foodId,
    this.barcode,
    this.recipeId,
    this.pantryItemId,
  });

  factory FoodChoice.fromHit(CatalogHit hit) => FoodChoice(
        name: hit.title,
        foodId: hit.foodId,
        barcode: hit.barcode,
        recipeId: hit.recipeId,
      );

  final String name;
  final int? foodId;
  final String? barcode;
  final int? recipeId;

  /// Picked from the pantry: logging it decrements that stock row.
  final int? pantryItemId;
}

/// Opens a search page and returns the chosen food, product or recipe.
Future<FoodChoice?> pickFood(
  BuildContext context, {
  required String title,
  bool pantryFirst = false,
  bool allowRecipes = true,
  bool allowProducts = true,
}) =>
    Navigator.of(context).push<FoodChoice>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => HosPage(
        title: title,
        body: CatalogSearchBody(
          pantryFirst: pantryFirst,
          allowRecipes: allowRecipes,
          allowProducts: allowProducts,
          onPick: (choice) => Navigator.of(context).pop(choice),
        ),
      ),
    ));

/// Search field and results: pantry stock (optional), then the catalogue
/// (accent-insensitive, Spanish synonyms included by the database).
class CatalogSearchBody extends ConsumerStatefulWidget {
  const CatalogSearchBody({
    super.key,
    required this.onPick,
    this.pantryFirst = false,
    this.allowRecipes = true,
    this.allowProducts = true,
  });

  final ValueChanged<FoodChoice> onPick;
  final bool pantryFirst;
  final bool allowRecipes;
  final bool allowProducts;

  @override
  ConsumerState<CatalogSearchBody> createState() => _CatalogSearchBodyState();
}

class _CatalogSearchBodyState extends ConsumerState<CatalogSearchBody> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final result = await lookupProduct(ref, code);
    if (!mounted) return;
    final product = result.product;
    if (product != null) {
      toast(context, result.messageEs);
      widget.onPick(FoodChoice(name: product.displayName, barcode: code));
      return;
    }
    final logAnyway = await confirm(
      context,
      title: 'Producto sin datos',
      message: '${result.messageEs}\n\n¿Usarlo igual? Sus nutrientes se '
          'mostrarán como "sin dato".',
      accept: 'USAR',
    );
    if (logAnyway && mounted) {
      widget.onPick(FoodChoice(name: 'Producto $code', barcode: code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = ref.watch(referenceDbProvider);
    final query = _query.trim();
    final hits = reference == null || query.isEmpty
        ? const <CatalogHit>[]
        : [
            for (final hit in reference.search(query))
              if ((widget.allowRecipes || hit.kind != CatalogKind.recipe) &&
                  (widget.allowProducts || hit.kind != CatalogKind.product))
                hit,
          ];
    final folded = foldText(query);
    final stock = widget.pantryFirst
        ? [
            for (final s in ref.watch(stockViewProvider))
              if (folded.isEmpty || foldText(s.food.name).contains(folded)) s,
          ]
        : const <StockView>[];

    Widget section(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('> $label', style: theme.textTheme.titleSmall),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'plátano, caraota, arroz, atún…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (widget.allowProducts)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear código',
                onPressed: _scan,
              ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 48),
            children: [
              if (reference == null)
                const Note(
                  'La base de alimentos no está instalada en este APK. Solo '
                  'puedes escanear productos.',
                  icon: Icons.info_outline,
                ),
              if (stock.isNotEmpty) ...[
                section('EN DESPENSA'),
                for (final s in stock)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.kitchen_outlined),
                      title: Text(s.food.name),
                      subtitle: Text('${fmtNum(s.row.gramsRemaining, unit: 'g')} disponibles'
                          '${s.daysToExpiry == null ? '' : ' · vence en ${s.daysToExpiry} d'}'),
                      onTap: () => widget.onPick(FoodChoice(
                        name: s.food.name,
                        foodId: s.row.foodId,
                        barcode: s.row.foodId == null ? s.row.barcode : null,
                        pantryItemId: s.row.id,
                      )),
                    ),
                  ),
              ],
              if (hits.isNotEmpty) section('CATÁLOGO'),
              for (final hit in hits)
                Card(
                  child: ListTile(
                    leading: Icon(switch (hit.kind) {
                      CatalogKind.food => Icons.eco_outlined,
                      CatalogKind.product => Icons.inventory_2_outlined,
                      CatalogKind.recipe => Icons.soup_kitchen_outlined,
                    }),
                    title: Text(hit.title),
                    subtitle: Text([
                      if (hit.subtitle != null) hit.subtitle!,
                      hit.kcal100g == null ? 'kcal: $sinDato' : '${fmtNum(hit.kcal100g)} kcal/100 g',
                    ].join(' · ')),
                    onTap: () => widget.onPick(FoodChoice.fromHit(hit)),
                  ),
                ),
              if (query.isNotEmpty && hits.isEmpty && stock.isEmpty && reference != null)
                Note('Sin resultados para "$query".'),
            ],
          ),
        ),
      ],
    );
  }
}
