import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';

/// SUPUESTOS: every model constant with its value, explanation and source.
/// Edits are validated against the catalogue's range.
class SupuestosPage extends ConsumerWidget {
  const SupuestosPage({super.key});

  Future<void> _set(WidgetRef ref, String key, double value) {
    final db = ref.read(userDbProvider);
    return (db.update(db.assumptionRows)..where((t) => t.key.equals(key)))
        .write(AssumptionRowsCompanion(value: Value(value)));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AssumptionDef def, double current) async {
    final decimals = def.value == def.value.roundToDouble() && current == current.roundToDouble() ? 0 : 3;
    final value = await askNumber(
      context,
      title: def.titleEs,
      initial: current,
      unit: def.unitEs,
      decimals: decimals,
    );
    if (value == null || !context.mounted) return;
    if (!def.accepts(value)) {
      toast(context, 'Fuera de rango: entre ${fmtNum(def.min, decimals: 3)} y ${fmtNum(def.max, decimals: 3)}.');
      return;
    }
    await _set(ref, def.key, value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(currentAssumptionsProvider);
    final theme = Theme.of(context);
    String show(double v) => v == v.roundToDouble() ? fmtNum(v) : fmtNum(v, decimals: 3);
    return HosPage(
      title: 'SUPUESTOS',
      subtitle: 'Toca un valor para cambiarlo',
      body: PanelList(children: [
        for (final group in AssumptionGroup.values)
          TerminalPanel(
            label: group.labelEs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final def in assumptionCatalog.where((d) => d.group == group))
                  Builder(builder: (context) {
                    final current = a[def.key];
                    final changed = current != def.value;
                    return InkWell(
                      onTap: () => _edit(context, ref, def, current),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(child: Text(def.titleEs, style: theme.textTheme.titleSmall)),
                              Text(
                                '${show(current)}${def.unitEs.isEmpty ? '' : ' ${def.unitEs}'}',
                                style: theme.textTheme.titleLarge,
                              ),
                            ]),
                            Text(def.explainEs, style: theme.textTheme.bodySmall),
                            if (def.source != null) Text('Fuente: ${def.source}', style: theme.textTheme.bodySmall),
                            if (changed)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () => _set(ref, def.key, def.value),
                                  child: Text('RESTAURAR ${show(def.value)}'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
      ]),
    );
  }
}
