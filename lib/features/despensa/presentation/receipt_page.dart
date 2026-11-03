import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../indice/presentation/catalog_search.dart';
import '../../registro/domain/intake.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

/// One receipt line while the user reviews it.
class _Draft {
  _Draft(this.line) : grams = line.grams;

  final ReceiptLine line;
  double? grams;
  int? foodId;
  String? barcode;
  bool include = true;

  bool get linked => foodId != null || barcode != null;
}

/// RECIBO: the lines read from the photo, for the user to confirm or
/// correct. Each product name is linked to a food once (remembered for the
/// next receipt); confirmed lines go to the pantry with their price per kg.
class ReceiptLinesPage extends ConsumerStatefulWidget {
  const ReceiptLinesPage({super.key, required this.purchaseId, required this.receipt});

  final int purchaseId;
  final ParsedReceipt receipt;

  @override
  ConsumerState<ReceiptLinesPage> createState() => _ReceiptLinesPageState();
}

class _ReceiptLinesPageState extends ConsumerState<ReceiptLinesPage> {
  late final List<_Draft> _drafts = [for (final l in widget.receipt.lines) _Draft(l)];
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  /// Lines seen before are linked without asking.
  Future<void> _loadLinks() async {
    final db = ref.read(userDbProvider);
    final links = {for (final r in await db.select(db.receiptLinks).get()) r.lineKey: r};
    for (final d in _drafts) {
      final link = links[receiptKey(d.line.name)];
      if (link != null) {
        d.foodId = link.foodId;
        d.barcode = link.barcode;
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _link(_Draft d) async {
    final choice = await pickFood(
      context,
      title: 'Qué es «${d.line.name}»',
      allowRecipes: false,
      initialQuery: d.line.name.toLowerCase(),
    );
    if (choice == null || (choice.foodId == null && choice.barcode == null)) return;
    final db = ref.read(userDbProvider);
    await db.into(db.receiptLinks).insertOnConflictUpdate(ReceiptLinksCompanion.insert(
          lineKey: receiptKey(d.line.name),
          foodId: Value(choice.foodId),
          barcode: Value(choice.barcode),
          updatedAt: stampOf(ref.read(clockProvider)()),
        ));
    setState(() {
      d.foodId = choice.foodId;
      d.barcode = choice.barcode;
    });
  }

  Future<void> _grams(_Draft d) async {
    final g = await askNumber(context, title: 'Gramos de «${d.line.name}»', initial: d.grams, unit: 'g', decimals: 0);
    if (g != null && g > 0) setState(() => d.grams = g);
  }

  Future<void> _save() async {
    final ready = [for (final d in _drafts) if (d.include && d.linked && (d.grams ?? 0) > 0) d];
    if (ready.isEmpty) {
      toast(context, 'Nada listo: cada línea necesita su alimento y sus gramos.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(pantryRepositoryProvider);
    final today = isoDate(ref.read(todayProvider));
    for (final d in ready) {
      await repo.addItem(
        foodId: d.foodId,
        barcode: d.barcode,
        grams: d.grams!,
        priceCentsPerKg: (d.line.amountCents * 1000 / d.grams!).round(),
        purchasedOn: today,
        purchaseId: widget.purchaseId,
      );
    }
    if (!mounted) return;
    toast(context, '${ready.length} producto(s) en la despensa.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.receipt;
    final resolver = ref.watch(nutritionResolverProvider);
    return HosPage(
      title: 'RECIBO',
      subtitle: 'Revisa cada línea antes de guardarla',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Totales',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DataLine('Suma de las líneas', formatCents(r.linesCents)),
            DataLine('Total impreso', r.totalCents == null ? 'sin dato' : formatCents(r.totalCents!)),
            if (r.totalCents != null && r.totalCents != r.linesCents)
              const Note('La suma no coincide con el total: falta o sobra alguna línea. Corrígela o agrégala a mano.'),
          ]),
        ),
        if (!_loaded) const Note('Leyendo…'),
        for (final d in _drafts)
          TerminalPanel(
            label: d.line.name,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(d.line.text, style: Theme.of(context).textTheme.bodySmall),
              DataLine('Monto', formatCents(d.line.amountCents)),
              DataLine(
                'Alimento',
                d.linked ? resolver.resolve(foodId: d.foodId, barcode: d.barcode).name : 'sin vincular',
              ),
              DataLine('Gramos', d.grams == null ? 'sin dato' : fmtNum(d.grams, unit: 'g')),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton(onPressed: () => _link(d), child: Text(d.linked ? 'CAMBIAR ALIMENTO' : 'VINCULAR')),
                OutlinedButton(onPressed: () => _grams(d), child: const Text('GRAMOS')),
                FilterChip(
                  label: const Text('INCLUIR'),
                  selected: d.include,
                  onSelected: (v) => setState(() => d.include = v),
                ),
              ]),
            ]),
          ),
        BigButton(
          label: _saving ? 'Guardando…' : 'Añadir a la despensa',
          icon: Icons.check,
          onPressed: _saving ? null : _save,
        ),
      ]),
    );
  }
}
