import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/status_widgets.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/nutrients.dart';
import '../../../data/nutrition_resolver.dart';
import '../../../data/reference_models.dart';
import '../../registro/domain/intake.dart';
import '../../registro/domain/product_lookup.dart';
import 'catalog_search.dart';

/// ÍNDICE: the reference catalogue with its data, sources and user flags.
class IndiceScreen extends StatelessWidget {
  const IndiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HosPage(
      title: 'ÍNDICE',
      subtitle: 'Datos por 100 g · "sin dato" cuando la fuente no lo trae',
      body: CatalogSearchBody(
        onPick: (choice) => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => detailPageFor(choice),
        )),
      ),
    );
  }
}

Widget detailPageFor(FoodChoice choice) {
  if (choice.foodId != null) return FoodDetailPage(foodId: choice.foodId!);
  if (choice.recipeId != null) return RecipeDetailPage(recipeId: choice.recipeId!);
  return ProductDetailPage(barcode: choice.barcode ?? '');
}

const _macroLabels = {
  'carb_sugar': 'AZÚCARES',
  'carb_starch': 'ALMIDÓN',
  'fiber': 'FIBRA',
  'protein': 'PROTEÍNA',
  'fat': 'GRASA',
  'mixed': 'MIXTO',
};

const _stateLabels = {'raw': 'CRUDO', 'cooked': 'COCIDO', 'prepared': 'PREPARADO'};
const _ripenessLabels = {'green': 'VERDE', 'ripe': 'MADURO'};

class FoodDetailPage extends ConsumerWidget {
  const FoodDetailPage({super.key, required this.foodId});
  final int foodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(referenceDbProvider);
    final food = db?.food(foodId);
    if (db == null || food == null) {
      return const HosPage(title: 'ALIMENTO', body: Center(child: Text('No está en la base instalada.')));
    }
    final props = db.properties(foodId);
    final names = db.names(foodId).where((n) => n != food.nameEs).toList();
    final nutrients = db.nutrients(foodId);
    final flags = ref.watch(foodFlagsProvider).value?[foodId] ?? const FoodFlags();
    final byCategory = <String, List<NutrientValue>>{};
    for (final n in nutrients) {
      (byCategory[n.category] ??= []).add(n);
    }
    final present = {for (final n in nutrients) n.fdcId};
    final missing = [
      for (final key in NutrientKey.values)
        if (!key.fdcIds.any(present.contains)) key,
    ];
    final theme = Theme.of(context);
    return HosPage(
      title: 'ALIMENTO',
      body: PanelList(children: [
        Text(food.nameEs, style: theme.textTheme.headlineMedium),
        if (food.nameEn != null) Text(food.nameEn!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Tag(food.group.toUpperCase()),
          if (_stateLabels[food.state] != null) Tag(_stateLabels[food.state]!),
          if (_ripenessLabels[food.ripeness] != null) Tag(_ripenessLabels[food.ripeness]!),
          if (props != null) Tag('DOMINA: ${_macroLabels[props.macroDominant] ?? props.macroDominant}'),
          if (props?.nova != null) Tag('NOVA ${props!.nova}'),
          if (props != null) ConfidenceChip.of(props.confidence),
        ]),
        if (names.isNotEmpty) Note('También: ${names.join(', ')}'),
        if (props != null)
          TerminalPanel(
            label: 'Propiedades',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DataLine('Densidad energética', '${fmtNum(props.energyDensityKcalG, decimals: 2)} kcal/g'),
                DataLine('NRF9.3 por 100 kcal', fmtNum(props.nrf93Per100kcal, decimals: 1)),
                DataLine('Índice glucémico', props.gi == null ? sinDato : '${fmtNum(props.gi)} (${props.giRef ?? 'sin referencia'})'),
                DataLine('Carga glucémica / 100 g', fmtNum(props.glPer100g, decimals: 1)),
                DataLine(
                  'DIAAS',
                  props.diaas == null
                      ? sinDato
                      : '${fmtNum(props.diaas, decimals: 2)}'
                          '${props.limitingAa == null ? '' : ' · limita ${props.limitingAa}'}',
                ),
                DataLine('Leucina', fmtNum(props.leucineG100g, decimals: 2, unit: 'g/100 g')),
                DataLine(
                  'Hierro',
                  props.ironHeme == null ? sinDato : (props.ironHeme! ? 'hemo (animal)' : 'no hemo (vegetal)'),
                ),
                if (props.inhibitsNonHemeIron)
                  const Note('Contiene polifenoles que reducen la absorción del hierro vegetal.'),
                if (props.novaSource != null) Note('NOVA según: ${props.novaSource}'),
                if (props.resistantStarchNote != null) Note(props.resistantStarchNote!),
                if (props.antinutrientNote != null) Note(props.antinutrientNote!),
                if (props.allergens != null) Note('Alérgenos: ${props.allergens}'),
              ],
            ),
          ),
        TerminalPanel(
          label: 'Nutrientes por 100 g',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(entry.key.toUpperCase(), style: theme.textTheme.labelLarge),
                ),
                for (final n in entry.value)
                  DataLine(n.nameEs, fmtNum(n.amountPer100g, decimals: n.amountPer100g < 10 ? 2 : 1, unit: n.unit)),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final key in missing) DataLine(key.labelEs, sinDato),
              ],
            ],
          ),
        ),
        TerminalPanel(
          label: 'Fuente',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataLine('Base', food.source.name),
              DataLine('Registro', food.sourceRef),
              DataLine('Versión', food.source.version),
              DataLine('Licencia', food.source.license),
              Note(food.source.url),
              if (food.proxyOf != null) const Note('Valores tomados de un alimento equivalente (proxy).'),
            ],
          ),
        ),
        TerminalPanel(
          label: 'Tus marcas',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('EXCLUIR DE SUGERENCIAS'),
                value: flags.excluded,
                onChanged: (v) => ref
                    .read(pantryRepositoryProvider)
                    .setFlags(foodId, excluded: v, reflux: flags.triggersReflux),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ME DA REFLUJO'),
                value: flags.triggersReflux,
                onChanged: (v) => ref
                    .read(pantryRepositoryProvider)
                    .setFlags(foodId, excluded: flags.excluded, reflux: v),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class ProductDetailPage extends ConsumerStatefulWidget {
  const ProductDetailPage({super.key, required this.barcode});
  final String barcode;

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _looking = false;

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(nutritionResolverProvider).product(widget.barcode);
    final theme = Theme.of(context);
    if (product == null) {
      return HosPage(
        title: 'PRODUCTO',
        body: PanelList(children: [
          Note('El código ${widget.barcode} no está en la base local.'),
          FilledButton(
            onPressed: _looking
                ? null
                : () async {
                    setState(() => _looking = true);
                    final result = await lookupProduct(ref, widget.barcode);
                    if (!context.mounted) return;
                    setState(() => _looking = false);
                    toast(context, result.messageEs);
                  },
            child: const Text('BUSCAR EN OPEN FOOD FACTS'),
          ),
        ]),
      );
    }
    final p = NutrientProfile.fromProduct(product);
    return HosPage(
      title: 'PRODUCTO',
      body: PanelList(children: [
        Text(product.name, style: theme.textTheme.headlineMedium),
        if (product.brand != null) Text(product.brand!, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (product.nova != null) Tag('NOVA ${product.nova}'),
          if (product.nutriscore != null) Tag('NUTRI-SCORE ${product.nutriscore!.toUpperCase()}'),
          Tag(product.barcode),
        ]),
        TerminalPanel(
          label: 'Por 100 g (etiqueta)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final key in const [
                NutrientKey.energy,
                NutrientKey.protein,
                NutrientKey.fat,
                NutrientKey.carbs,
                NutrientKey.sugars,
                NutrientKey.fiber,
                NutrientKey.sodium,
              ])
                DataLine(key.labelEs, fmtNum(p.per100g(key), decimals: key == NutrientKey.energy ? 0 : 1, unit: key.unit)),
            ],
          ),
        ),
        if (product.ingredients != null)
          TerminalPanel(label: 'Ingredientes', child: Text(product.ingredients!)),
        if (product.additives != null) Note('Aditivos: ${product.additives}'),
        const Note('Datos de Open Food Facts (openfoodfacts.org), licencia ODbL.'),
      ]),
    );
  }
}

class RecipeDetailPage extends ConsumerWidget {
  const RecipeDetailPage({super.key, required this.recipeId});
  final int recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipe = ref.watch(referenceDbProvider)?.recipe(recipeId);
    final resolver = ref.watch(nutritionResolverProvider);
    if (recipe == null) {
      return const HosPage(title: 'RECETA', body: Center(child: Text('No está en la base instalada.')));
    }
    final whole = resolver.resolve(recipeId: recipeId);
    return HosPage(
      title: 'RECETA',
      body: PanelList(children: [
        Text(recipe.nameEs, style: Theme.of(context).textTheme.headlineMedium),
        TerminalPanel(
          label: 'Ingredientes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in recipe.items)
                DataLine(
                  resolver.resolve(foodId: item.foodId, barcode: item.barcode).name,
                  fmtNum(item.grams, decimals: item.grams < 10 ? 1 : 0, unit: 'g'),
                ),
            ],
          ),
        ),
        TerminalPanel(
          label: 'Por 100 g',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final key in NutrientKey.values)
                DataLine(key.labelEs, fmtNum(whole.profile.per100g(key), decimals: 1, unit: key.unit)),
              const Note('Si un ingrediente no tiene un dato, la receta tampoco lo tiene.'),
            ],
          ),
        ),
      ]),
    );
  }
}
