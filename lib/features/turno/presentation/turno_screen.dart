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
import '../../../services/services.dart';
import '../../estado/domain/targets.dart';
import '../domain/hydration.dart';

/// TURNO: today's shift (effort, heat hours, PPE), the thermos plan with
/// sodium, fluids drunk, hydration reminders and the sweat test.
class TurnoScreen extends ConsumerWidget {
  const TurnoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    return HosPage(
      title: 'TURNO',
      subtitle: fmtDay(today),
      body: const PanelList(children: [
        _ShiftPanel(),
        _WaterPanel(),
        _SweatTestPanel(),
      ]),
    );
  }
}

Future<void> _update(WidgetRef ref, DailyLogsCompanion fields) =>
    ref.read(dailyLogRepositoryProvider).update(isoDate(ref.read(todayProvider)), fields);

class _ShiftPanel extends ConsumerWidget {
  const _ShiftPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(todayLogProvider);
    final effort = WorkEffort.parse(log?.workEffort);
    final heat = log?.heatHours ?? 0;
    return TerminalPanel(
      label: 'Jornada',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Esfuerzo físico', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in WorkEffort.values)
                ChoiceChip(
                  label: Text(e.labelEs),
                  selected: e == effort,
                  onSelected: (_) => _update(ref, DailyLogsCompanion(workEffort: Value(e.code))),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Horas de calor (soldando o junto a fuentes de calor)',
              style: Theme.of(context).textTheme.labelLarge),
          ValueStepper(
            value: heat,
            unit: 'h',
            decimals: 1,
            min: 0,
            max: 14,
            steps: const [0.5, 2],
            onChanged: (v) => _update(ref, DailyLogsCompanion(heatHours: Value(v))),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('EQUIPO COMPLETO'),
            subtitle: const Text('Chaqueta, guantes y careta: sudas más y no se evapora.'),
            value: log?.ppeFull ?? false,
            onChanged: (v) => _update(ref, DailyLogsCompanion(ppeFull: Value(v))),
          ),
          if (effort == null)
            const Note('Marca el esfuerzo: ajusta la energía del día y la recuperación.'),
        ],
      ),
    );
  }
}

class _WaterPanel extends ConsumerWidget {
  const _WaterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(todayLogProvider);
    final plan = ref.watch(hydrationPlanProvider);
    final compliance = ref.watch(hydrationComplianceProvider);
    final fluids = log?.fluidsL ?? 0;
    final heat = log?.heatHours ?? 0;

    Future<void> addLitres(double litres) =>
        _update(ref, DailyLogsCompanion(fluidsL: Value(double.parse((fluids + litres).toStringAsFixed(2)))));

    return TerminalPanel(
      label: 'Agua y sodio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heat <= 0)
            const Note('Declara las horas de calor para calcular el termo del turno.')
          else ...[
            Text(plan.summaryEs, style: Theme.of(context).textTheme.bodyLarge),
            if (plan.capped)
              const Note('El plan quedó limitado por el máximo por hora que el '
                  'intestino absorbe: no bebas más rápido que eso.'),
            DataLine(
              'Sodio a reponer',
              '${fmtNum(plan.sodiumMgMin)}–${fmtNum(plan.sodiumMgMax)} mg '
                  '(≈ ${fmtNum(HydrationPlan.saltGramsFor(plan.sodiumMgMin), decimals: 1)}–'
                  '${fmtNum(HydrationPlan.saltGramsFor(plan.sodiumMgMax), decimals: 1)} g de sal)',
            ),
          ],
          const SizedBox(height: 8),
          DataLine('Bebido hoy', fmtNum(fluids, decimals: 2, unit: 'L'), emphasis: true),
          if (compliance != null) ...[
            LinearProgressIndicator(value: compliance.clamp(0, 1).toDouble(), minHeight: 10),
            const SizedBox(height: 4),
            Text('${fmtNum(compliance * 100)} % del plan', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Row(children: [
            for (final litres in const [0.25, 0.5, 1.0])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: () => addLitres(litres),
                    child: Text('+${fmtNum(litres, decimals: 2)} L'),
                  ),
                ),
              ),
          ]),
          TextButton(
            onPressed: () async {
              final value = await askNumber(context, title: 'Litros bebidos hoy', initial: fluids, unit: 'L', decimals: 2);
              if (value != null && value >= 0) {
                await _update(ref, DailyLogsCompanion(fluidsL: Value(value)));
              }
            },
            child: const Text('CORREGIR TOTAL'),
          ),
          if (heat > 0) const _NudgeButtons(),
        ],
      ),
    );
  }
}

class _NudgeButtons extends ConsumerWidget {
  const _NudgeButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider).value;
    if (!settings.hydrationNudges) {
      return const Note('Los avisos de agua están desactivados en AJUSTES.');
    }
    Future<void> schedule(bool enabled) async {
      final now = ref.read(clockProvider)();
      final end = parseClock(profile?.shiftEnd ?? '17:00');
      final until = DateTime(now.year, now.month, now.day, end ~/ 60, end % 60);
      final every = ref.read(currentAssumptionsProvider).integer(A.heatBolusIntervalMaxMin);
      final plan = ref.read(hydrationPlanProvider);
      await ref.read(notificationServiceProvider).scheduleHydration(
            from: now,
            until: until,
            everyMinutes: every,
            body: plan.bolusL == null
                ? 'Toca beber según tu plan del turno.'
                : 'Toca beber ${fmtNum(plan.bolusL! * 1000)} ml.',
            enabled: enabled,
          );
      if (context.mounted) {
        toast(
          context,
          enabled
              ? (until.isAfter(now)
                  ? 'Avisos cada $every min hasta las ${profile?.shiftEnd ?? '17:00'}.'
                  : 'El turno ya terminó: no hay avisos que programar.')
              : 'Avisos de agua quitados.',
        );
      }
    }

    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('AVISOS HOY'),
          onPressed: () => schedule(true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton(onPressed: () => schedule(false), child: const Text('QUITAR')),
      ),
    ]);
  }
}

class _SweatTestPanel extends ConsumerWidget {
  const _SweatTestPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(todayLogProvider);
    final latest = ref.watch(latestSweatTestProvider);
    final params = SweatParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
    final pre = log?.sweatPreKg;
    final post = log?.sweatPostKg;
    final heat = log?.heatHours ?? 0;
    final result = pre != null && post != null && heat > 0
        ? evaluateSweatTest(
            SweatTest(
              preKg: pre,
              postKg: post,
              fluidsL: log?.fluidsL ?? 0,
              urineL: log?.urineL ?? 0,
              hours: heat,
            ),
            params,
          )
        : null;

    Future<void> ask(String title, double? initial, DailyLogsCompanion Function(double) build,
        {String unit = 'kg', int decimals = 1}) async {
      final value = await askNumber(context, title: title, initial: initial, unit: unit, decimals: decimals);
      if (value != null && value >= 0) await _update(ref, build(value));
    }

    return TerminalPanel(
      label: 'Prueba de sudor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'Pésate sin ropa ni botas al empezar el turno (PRE) y al terminar '
            '(POST). Anota lo bebido arriba y la orina si orinaste. La pérdida '
            'por hora define tu plan personal.',
          ),
          DataLine('PRE', fmtNum(pre, decimals: 1, unit: 'kg')),
          DataLine('POST', fmtNum(post, decimals: 1, unit: 'kg')),
          DataLine('Orina', fmtNum(log?.urineL, decimals: 2, unit: 'L')),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => ask('Peso PRE', pre, (v) => DailyLogsCompanion(sweatPreKg: Value(v))),
                child: const Text('PRE'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => ask('Peso POST', post, (v) => DailyLogsCompanion(sweatPostKg: Value(v))),
                child: const Text('POST'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () => ask('Orina', log?.urineL, (v) => DailyLogsCompanion(urineL: Value(v)),
                    unit: 'L', decimals: 2),
                child: const Text('ORINA'),
              ),
            ),
          ]),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(result.messageEs, style: Theme.of(context).textTheme.bodyLarge),
            if (result.valid) ...[
              DataLine('Sudor por hora', fmtNum(result.rateLPerH, decimals: 2, unit: 'L/h'), emphasis: true),
              DataLine('Pérdida de peso', '${fmtNum(result.lossPct, decimals: 1)} %'),
            ],
          ] else if (pre != null || post != null)
            const Note('Faltan datos: PRE, POST y horas de calor.'),
          const SizedBox(height: 8),
          DataLine(
            'Prueba en uso',
            latest == null
                ? 'ninguna (plan genérico)'
                : '${fmtNum(latest.rate, decimals: 2, unit: 'L/h')} · ${fmtShortDay(parseIsoDate(latest.date))}',
          ),
          if (latest == null)
            BigButton(
              label: 'Cómo hacer la prueba',
              icon: Icons.help_outline,
              outlined: true,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('PRUEBA DE SUDOR'),
                  content: const Text(
                    '1. Orina y pésate sin ropa antes del turno (PRE).\n'
                    '2. Trabaja normal; anota cada termo que bebes.\n'
                    '3. Si orinas, estima los litros.\n'
                    '4. Al terminar, sécate y pésate sin ropa (POST).\n'
                    '5. Declara las horas de calor del día.\n\n'
                    'Sudor por hora = (PRE − POST + bebido − orina) ÷ horas.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialog).pop(),
                      child: const Text('ENTENDIDO'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
