import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/user_db.dart';
import '../../indice/presentation/catalog_search.dart';
import '../data/meals_repository.dart';
import '../domain/intake.dart';

/// Message for the outcome of a pantry decrement (warnings never block).
String? stockMessage(StockResult result) {
  if (result.insufficient) {
    return 'Stock insuficiente: había ${fmtNum(result.availableG, unit: 'g')} y '
        'usaste ${fmtNum(result.requestedG, unit: 'g')}. Se registró igual; '
        'la despensa quedó en ${fmtNum(result.remainingG, unit: 'g')}.';
  }
  if (result.remainingG != null) {
    return 'Registrado. Quedan ${fmtNum(result.remainingG, unit: 'g')} en la despensa.';
  }
  return null;
}

/// Grams, meal block and pantry source for a chosen food, then logs it.
Future<void> showAddItemSheet(
  BuildContext context, {
  required FoodChoice choice,
  required String date,
  required MealBlock block,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddItemSheet(choice: choice, date: date, initialBlock: block),
    );

class AddItemSheet extends ConsumerStatefulWidget {
  const AddItemSheet({
    super.key,
    required this.choice,
    required this.date,
    required this.initialBlock,
  });

  final FoodChoice choice;
  final String date;
  final MealBlock initialBlock;

  @override
  ConsumerState<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<AddItemSheet> {
  late MealBlock _block = widget.initialBlock;
  double _grams = 100;
  List<PantryItemRow> _stock = const [];
  int? _pantryId;
  bool _saving = false;

  FoodChoice get _choice => widget.choice;

  @override
  void initState() {
    super.initState();
    final recipeId = _choice.recipeId;
    if (recipeId != null) {
      final recipe = ref.read(referenceDbProvider)?.recipe(recipeId);
      if (recipe != null && recipe.totalGrams > 0) _grams = recipe.totalGrams.roundToDouble();
    }
    _loadStock();
  }

  Future<void> _loadStock() async {
    if (_choice.recipeId != null) return;
    final rows = await ref.read(pantryRepositoryProvider).stockFor(
          foodId: _choice.foodId,
          barcode: _choice.foodId == null ? _choice.barcode : null,
        );
    if (!mounted) return;
    setState(() {
      _stock = rows;
      _pantryId = _choice.pantryItemId ?? (rows.isEmpty ? null : rows.first.id);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await ref.read(mealsRepositoryProvider).addItem(
          date: widget.date,
          block: _block,
          grams: _grams,
          foodId: _choice.foodId,
          barcode: _choice.foodId == null ? _choice.barcode : null,
          recipeId: _choice.recipeId,
          pantryItemId: _pantryId,
        );
    navigator.pop();
    final message = stockMessage(result);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final food = ref.watch(nutritionResolverProvider).resolve(
          foodId: _choice.foodId,
          barcode: _choice.foodId == null ? _choice.barcode : null,
          recipeId: _choice.recipeId,
        );
    final p = food.profile;
    Widget stockOption(int? id, String label) {
      final selected = _pantryId == id;
      return ListTile(
        dense: true,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        title: Text(label),
        onTap: () => setState(() => _pantryId = id),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(food.name, style: theme.textTheme.titleLarge),
            if (!food.known)
              const Note(
                'Sin datos nutricionales: se registrará y sus nutrientes se '
                'mostrarán como "sin dato".',
                icon: Icons.info_outline,
              ),
            ValueStepper(
              value: _grams,
              unit: 'g',
              min: 1,
              max: 3000,
              steps: const [10, 50],
              onChanged: (v) => setState(() => _grams = v),
              onTapValue: () async {
                final value = await askNumber(context, title: 'Gramos', initial: _grams, unit: 'g', decimals: 0);
                if (value != null && value > 0) setState(() => _grams = value);
              },
            ),
            const SizedBox(height: 8),
            DataLine('Energía', fmtNum(p.forGrams(NutrientKey.energy, _grams), unit: 'kcal')),
            DataLine('Proteína', fmtNum(p.forGrams(NutrientKey.protein, _grams), decimals: 1, unit: 'g')),
            DataLine('Carbohidratos', fmtNum(p.forGrams(NutrientKey.carbs, _grams), decimals: 1, unit: 'g')),
            DataLine('Grasa', fmtNum(p.forGrams(NutrientKey.fat, _grams), decimals: 1, unit: 'g')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in MealBlock.values)
                  ChoiceChip(
                    label: Text(b.labelEs),
                    selected: b == _block,
                    onSelected: (_) => setState(() => _block = b),
                  ),
              ],
            ),
            if (_stock.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('> DESCONTAR DE LA DESPENSA', style: theme.textTheme.titleSmall),
              for (final row in _stock)
                stockOption(
                  row.id,
                  '${fmtNum(row.gramsRemaining, unit: 'g')} disponibles'
                  '${row.expiresOn == null ? '' : ' · vence ${row.expiresOn}'}',
                ),
              stockOption(null, 'No descontar'),
            ],
            const SizedBox(height: 12),
            BigButton(
              label: 'Registrar',
              icon: Icons.check,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
