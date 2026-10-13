import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/status_widgets.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/nutrition_resolver.dart';
import '../../../data/user_db.dart';
import '../../indice/presentation/catalog_search.dart';
import '../../registro/domain/intake.dart';
import '../domain/pantry_model.dart';

/// DESPENSA: stock with the best option now, purchases (receipt OCR),
/// cooked batches with food-safety timing, and the cheapest plan.
class DespensaScreen extends StatelessWidget {
  const DespensaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: HosPage(
        title: 'DESPENSA',
        bottom: TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'STOCK'),
            Tab(text: 'COMPRAS'),
            Tab(text: 'COCIDOS'),
            Tab(text: 'PLAN'),
          ],
        ),
        body: TabBarView(children: [
          _StockTab(),
          _PurchasesTab(),
          _CookedTab(),
          _PlanTab(),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------------- stock

/// Adds a food or product to the pantry (grams, price paid, expiry).
Future<void> addStock(BuildContext context, WidgetRef ref, {int? purchaseId}) async {
  final choice = await pickFood(context, title: 'Añadir a despensa', allowRecipes: false);
  if (choice == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StockSheet(choice: choice, purchaseId: purchaseId),
  );
}

class _StockSheet extends ConsumerStatefulWidget {
  const _StockSheet({this.choice, this.row, this.purchaseId});
  final FoodChoice? choice;
  final PantryItemRow? row;
  final int? purchaseId;

  @override
  ConsumerState<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<_StockSheet> {
  late double _grams = widget.row?.gramsRemaining ?? 1000;
  double? _pricePaid;
  late double? _pricePerKg = widget.row?.priceUsdPerKg;
  late DateTime? _expires =
      widget.row?.expiresOn == null ? null : DateTime.tryParse(widget.row!.expiresOn!);

  Future<void> _save() async {
    final repo = ref.read(pantryRepositoryProvider);
    final today = isoDate(ref.read(todayProvider));
    final paid = _pricePaid;
    final perKg = paid != null && _grams > 0 ? paid / _grams * 1000 : _pricePerKg;
    final expires = _expires == null ? null : isoDate(_expires!);
    final row = widget.row;
    if (row == null) {
      final choice = widget.choice!;
      await repo.addItem(
        foodId: choice.foodId,
        barcode: choice.foodId == null ? choice.barcode : null,
        grams: _grams,
        priceUsdPerKg: perKg,
        purchasedOn: today,
        expiresOn: expires,
        purchaseId: widget.purchaseId,
      );
    } else {
      await repo.updateItem(row, grams: _grams, price: perKg, expiresOn: expires);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final resolver = ref.watch(nutritionResolverProvider);
    final row = widget.row;
    final name = row == null
        ? widget.choice!.name
        : resolver.resolve(foodId: row.foodId, barcode: row.barcode).name;
    final today = ref.watch(todayProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            ValueStepper(
              value: _grams,
              unit: 'g',
              max: 50000,
              steps: const [50, 250],
              onChanged: (v) => setState(() => _grams = v),
              onTapValue: () async {
                final v = await askNumber(context, title: 'Gramos', initial: _grams, unit: 'g', decimals: 0);
                if (v != null && v >= 0) setState(() => _grams = v);
              },
            ),
            DataLine(
              'Precio',
              _pricePaid != null
                  ? '${fmtUsd(_pricePaid)} pagados'
                  : (_pricePerKg == null ? sinDato : '${fmtUsd(_pricePerKg)} / kg'),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await askNumber(context, title: 'Precio pagado', unit: 'USD', decimals: 2);
                    if (v != null && v >= 0) setState(() => _pricePaid = v);
                  },
                  child: const Text('PAGADO'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await askNumber(context, title: 'Precio por kg', initial: _pricePerKg, unit: 'USD/kg', decimals: 2);
                    if (v != null && v >= 0) {
                      setState(() {
                        _pricePerKg = v;
                        _pricePaid = null;
                      });
                    }
                  },
                  child: const Text('POR KG'),
                ),
              ),
            ]),
            DataLine('Vence', _expires == null ? 'sin fecha' : fmtDay(_expires!)),
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expires ?? addDays(today, 7),
                  firstDate: addDays(today, -30),
                  lastDate: addDays(today, 730),
                );
                if (picked != null) setState(() => _expires = picked);
              },
              child: const Text('FECHA DE VENCIMIENTO'),
            ),
            const SizedBox(height: 12),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
            if (row != null)
              TextButton(
                onPressed: () async {
                  final ok = await confirm(context, title: 'Quitar', message: 'Quitar $name de la despensa.', accept: 'QUITAR');
                  if (!ok) return;
                  await ref.read(pantryRepositoryProvider).deleteItem(row.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('QUITAR DE LA DESPENSA'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockTab extends ConsumerWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockViewProvider);
    final best = ref.watch(bestOptionsProvider);
    final gap = ref.watch(todayGapProvider);
    return Stack(children: [
      PanelList(children: [
        TerminalPanel(
          label: 'Mejor opción ahora',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (gap != null)
                Note('Falta hoy: ${fmtNum(gap.kcal, unit: 'kcal')} y ${fmtNum(gap.proteinG, unit: 'g')} de proteína.'),
              if (best.isEmpty) const Note('Añade alimentos con gramos para ver sugerencias.'),
              for (final s in best.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(s.candidate.name, style: Theme.of(context).textTheme.titleMedium)),
                        ConfidenceChip.of(s.confidence),
                      ]),
                      Text(explainScore(s), style: Theme.of(context).textTheme.bodySmall),
                      for (final note in s.notesEs) Note(note),
                    ],
                  ),
                ),
            ],
          ),
        ),
        TerminalPanel(
          label: 'Stock',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stock.isEmpty) const Note('La despensa está vacía.'),
              for (final s in stock)
                InkWell(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _StockSheet(row: s.row),
                  ),
                  child: DataLine(
                    s.food.name,
                    '${fmtNum(s.row.gramsRemaining, unit: 'g')}'
                    '${s.row.priceUsdPerKg == null ? '' : ' · ${fmtUsd(s.row.priceUsdPerKg)}/kg'}'
                    '${s.daysToExpiry == null ? '' : (s.daysToExpiry! < 0 ? ' · VENCIDO' : ' · ${s.daysToExpiry} d')}',
                  ),
                ),
            ],
          ),
        ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          heroTag: 'stock',
          tooltip: 'Añadir a despensa',
          onPressed: () => addStock(context, ref),
          child: const Icon(Icons.add),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------- purchases

class _PurchasesTab extends ConsumerWidget {
  const _PurchasesTab();

  Future<void> _newPurchase(BuildContext context, WidgetRef ref) async {
    final store = await askText(context, title: 'Tienda', hint: 'Mercado, supermercado…');
    if (store == null || !context.mounted) return;
    final total = await askNumber(context, title: 'Total pagado', unit: 'USD', decimals: 2);
    if (!context.mounted) return;
    String? text;
    final scan = await confirm(
      context,
      title: 'Recibo',
      message: '¿Fotografiar el recibo? El texto se lee en el teléfono (sin '
          'internet) y queda guardado con la compra.',
      accept: 'FOTOGRAFIAR',
    );
    if (scan) text = await _readReceipt();
    final id = await ref.read(pantryRepositoryProvider).addPurchase(
          date: isoDate(ref.read(todayProvider)),
          store: store.isEmpty ? null : store,
          totalUsd: total,
          rawText: text,
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PurchasePage(purchaseId: id),
    ));
  }

  static Future<String?> _readReceipt() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null) return null;
    final recognizer = TextRecognizer();
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      return result.text.trim().isEmpty ? null : result.text;
    } finally {
      await recognizer.close();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider).value ?? const <PurchaseRow>[];
    return Stack(children: [
      PanelList(children: [
        if (purchases.isEmpty)
          const Note('Registra una compra para llevar precios y llenar la despensa.'),
        for (final p in purchases)
          Card(
            child: ListTile(
              title: Text('${fmtDay(parseIsoDate(p.date))} · ${p.store ?? 'sin tienda'}'),
              subtitle: Text(p.totalUsd == null ? 'total: $sinDato' : 'total: ${fmtUsd(p.totalUsd)}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _PurchasePage(purchaseId: p.id),
              )),
            ),
          ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          heroTag: 'purchase',
          tooltip: 'Nueva compra',
          onPressed: () => _newPurchase(context, ref),
          child: const Icon(Icons.receipt_long),
        ),
      ),
    ]);
  }
}

class _PurchasePage extends ConsumerWidget {
  const _PurchasePage({required this.purchaseId});
  final int purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchase = (ref.watch(purchasesProvider).value ?? const <PurchaseRow>[])
        .where((p) => p.id == purchaseId)
        .firstOrNull;
    final stock = ref.watch(stockViewProvider).where((s) => s.row.purchaseId == purchaseId).toList();
    return HosPage(
      title: 'COMPRA',
      subtitle: purchase == null ? null : '${purchase.date} · ${purchase.store ?? ''}',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Productos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stock.isEmpty) const Note('Añade lo que compraste, con gramos y precio.'),
              for (final s in stock)
                DataLine(s.food.name, '${fmtNum(s.row.gramsRemaining, unit: 'g')} · ${fmtUsd(s.row.priceUsdPerKg)}/kg'),
              const SizedBox(height: 8),
              BigButton(
                label: 'Añadir producto',
                icon: Icons.add,
                onPressed: () => addStock(context, ref, purchaseId: purchaseId),
              ),
            ],
          ),
        ),
        if (purchase?.rawText != null)
          TerminalPanel(
            label: 'Texto del recibo',
            child: SelectableText(purchase!.rawText!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- cooked

class _CookedTab extends ConsumerWidget {
  const _CookedTab();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final choice = await pickFood(context, title: 'Lote cocinado', allowProducts: false);
    if (choice == null || !context.mounted) return;
    final grams = await askNumber(context, title: 'Gramos del lote', unit: 'g', decimals: 0);
    await ref.read(pantryRepositoryProvider).addBatch(
          foodId: choice.foodId,
          recipeId: choice.recipeId,
          grams: grams,
          cookedAt: ref.read(clockProvider)(),
          heatExposed: false,
          refrigerated: false,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(openBatchesProvider).value ?? const <CookedBatchRow>[];
    final resolver = ref.watch(nutritionResolverProvider);
    final params = SafetyParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
    final now = ref.watch(clockProvider)();
    final repo = ref.read(pantryRepositoryProvider);
    final states = <(CookedBatchRow, CookedBatchState)>[
      for (final b in batches)
        (
          b,
          evaluateCookedBatch(
            name: _batchName(resolver, b),
            cookedAt: DateTime.tryParse(b.cookedAt) ?? now,
            now: now,
            heatExposed: b.heatExposed,
            refrigerated: b.refrigerated,
            params: params,
          ),
        ),
    ]..sort((x, y) => x.$2.deadline.compareTo(y.$2.deadline));
    return Stack(children: [
      PanelList(children: [
        if (states.isEmpty)
          const Note('Sin lotes abiertos. Registra lo que cocinas para saber hasta cuándo es seguro.'),
        for (final (row, state) in states)
          TerminalPanel(
            label: state.name,
            trailing: _SafetyBadge(state.level),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(state.messageEs),
                DataLine('Cocinado hace', formatHoursMinutes(state.hoursElapsed * 60)),
                DataLine('Límite', '${fmtShortDay(state.deadline)} ${fmtTime(state.deadline)}'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('EN LA NEVERA'),
                  value: row.refrigerated,
                  onChanged: (v) => repo.setBatchStorage(row.id, refrigerated: v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('EXPUESTO AL CALOR DEL TALLER'),
                  value: row.heatExposed,
                  onChanged: (v) => repo.setBatchStorage(row.id, heatExposed: v),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => repo.closeBatch(row.id, eaten: true, at: ref.read(clockProvider)()),
                      child: const Text('COMIDO'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => repo.closeBatch(row.id, eaten: false, at: ref.read(clockProvider)()),
                      child: const Text('DESCARTADO'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          heroTag: 'cooked',
          tooltip: 'Nuevo lote',
          onPressed: () => _add(context, ref),
          child: const Icon(Icons.soup_kitchen_outlined),
        ),
      ),
    ]);
  }

  static String _batchName(NutritionResolver resolver, CookedBatchRow b) =>
      resolver.resolve(foodId: b.foodId, recipeId: b.recipeId).name;
}

class _SafetyBadge extends StatelessWidget {
  const _SafetyBadge(this.level);
  final SafetyLevel level;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (level) {
      SafetyLevel.ok => ('OK', HosColors.phosphor),
      SafetyLevel.warn => ('PRONTO', HosColors.amber),
      SafetyLevel.discard => ('DESCARTAR', HosColors.alert),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
      child: Text(text, style: TextStyle(fontFamily: HosFonts.display, fontSize: 22, color: color)),
    );
  }
}

// ------------------------------------------------------------------ plan

class _PlanTab extends ConsumerStatefulWidget {
  const _PlanTab();

  @override
  ConsumerState<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends ConsumerState<_PlanTab> {
  DietPlan? _plan;
  bool _wholeDay = false;

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final stock = {for (final s in ref.watch(stockViewProvider)) s.key: s};
    return PanelList(children: [
      const Note(
        'Plan más barato con lo que hay en la despensa: cubre la energía y la '
        'proteína que faltan sin pasar el límite de sodio (más lo que sudaste '
        'hoy). Solo usa alimentos con precio y datos.',
      ),
      Row(children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('LO QUE FALTA HOY'),
            selected: !_wholeDay,
            onSelected: (_) => setState(() => _wholeDay = false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Text('DÍA COMPLETO'),
            selected: _wholeDay,
            onSelected: (_) => setState(() => _wholeDay = true),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      BigButton(
        label: 'Calcular plan',
        icon: Icons.calculate_outlined,
        onPressed: () => setState(() => _plan = planForToday(ref, wholeDay: _wholeDay)),
      ),
      if (plan != null)
        TerminalPanel(
          label: 'Plan',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(plan.messageEs),
              for (final entry in plan.gramsByKey.entries)
                if (entry.value >= 1)
                  DataLine(stock[entry.key]?.food.name ?? entry.key, fmtNum(entry.value, unit: 'g')),
              if (plan.status == DietStatus.optimal) ...[
                const Divider(),
                DataLine('Costo', fmtUsd(plan.costUsd), emphasis: true),
                DataLine('Energía', fmtNum(plan.kcal, unit: 'kcal')),
                DataLine('Proteína', fmtNum(plan.proteinG, unit: 'g')),
                DataLine('Sodio', '${plan.sodiumPartial ? '≥ ' : ''}${fmtNum(plan.sodiumMg, unit: 'mg')}'),
                DataLine('Grasa', fmtNum(plan.fatG, unit: 'g')),
              ],
              for (final b in plan.bindingEs) Note(b),
              if (plan.excludedEs.isNotEmpty) Note('No usados: ${plan.excludedEs.join('; ')}.'),
            ],
          ),
        ),
    ]);
  }
}
