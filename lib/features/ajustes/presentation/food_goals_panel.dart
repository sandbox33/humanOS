import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../despensa/domain/meal_day.dart';
import 'supuestos_page.dart';

/// METAS DE COMIDA (B4): the day's energy target (fixed or estimated),
/// protein per kg, the meals' shares and whether there is a fridge. Every
/// value can go back to its default with RESTABLECER.
class FoodGoalsPanel extends ConsumerWidget {
  const FoodGoalsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsMapProvider).value ?? const {};
    final repo = ref.read(settingsRepositoryProvider);
    final fixed = double.tryParse(settings[SettingKey.kcalTargetFixed] ?? '');
    final a = ref.watch(currentAssumptionsProvider);
    final proteinDef = assumptionsByKey[A.proteinGPerKg]!;
    final protein = a[A.proteinGPerKg];
    final fridge = settings[FoodKey.hasFridge];
    Widget reset(VoidCallback onPressed, String to) =>
        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onPressed, child: Text('RESTABLECER $to')));

    return TerminalPanel(
      label: 'Metas de comida',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ENERGÍA DEL DÍA'),
            subtitle: Text(fixed == null
                ? 'Calculada por la app (peso, trabajo y, con 14 días completos, tu propio gasto).'
                : 'Meta fija tuya: ${fmtNum(fixed, unit: 'kcal')}.'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await askNumber(context, title: 'Meta fija de energía', initial: fixed, unit: 'kcal', decimals: 0);
              if (v == null || !context.mounted) return;
              if (v < 1000 || v > 6000) {
                toast(context, 'Entre 1000 y 6000 kcal.');
                return;
              }
              await repo.set(SettingKey.kcalTargetFixed, '${v.round()}');
            },
          ),
          if (fixed != null) reset(() => repo.remove(SettingKey.kcalTargetFixed), 'AL CÁLCULO DE LA APP'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('PROTEÍNA POR KG'),
            subtitle: Text('${fmtNum(protein, decimals: 1)} g por kg de peso al día '
                '(entre ${fmtNum(proteinDef.min, decimals: 1)} y ${fmtNum(proteinDef.max, decimals: 1)}).'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final v = await askNumber(context, title: proteinDef.titleEs, initial: protein, unit: 'g/kg', decimals: 1);
              if (v == null || !context.mounted) return;
              if (!proteinDef.accepts(v)) {
                toast(context, 'Entre ${fmtNum(proteinDef.min, decimals: 1)} y ${fmtNum(proteinDef.max, decimals: 1)} g/kg.');
                return;
              }
              await _setAssumption(ref, A.proteinGPerKg, v);
            },
          ),
          if (protein != proteinDef.value)
            reset(() => _setAssumption(ref, A.proteinGPerKg, proteinDef.value), 'A ${fmtNum(proteinDef.value, decimals: 1)}'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('REPARTO POR COMIDA'),
            subtitle: const Text('Cada comida de tu HORARIO recibe su parte según el peso de esa comida. '
                'Se cambia y se restablece en SUPUESTOS → HORARIO DE COMIDAS.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupuestosPage())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('TENGO REFRIGERADORA'),
            subtitle: Text(fridge == null
                ? 'Sin respuesta: el plan usa la carne, el pescado y los lácteos frescos solo el día de la compra.'
                : fridge == '1'
                    ? 'El plan usa lo fresco de la despensa cualquier día.'
                    : 'El plan usa lo fresco solo el día de la compra (se compra y se cocina el mismo día).'),
            value: fridge == '1',
            onChanged: (v) => repo.set(FoodKey.hasFridge, v ? '1' : '0'),
          ),
          if (fridge != null) reset(() => repo.remove(FoodKey.hasFridge), 'SIN RESPUESTA'),
        ],
      ),
    );
  }
}

Future<void> _setAssumption(WidgetRef ref, String key, double value) {
  final db = ref.read(userDbProvider);
  return (db.update(db.assumptionRows)..where((t) => t.key.equals(key))).write(AssumptionRowsCompanion(value: Value(value)));
}
