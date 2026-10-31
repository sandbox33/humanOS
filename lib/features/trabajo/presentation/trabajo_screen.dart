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
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';
import '../data/work_repository.dart';
import '../domain/work_model.dart';
import 'templates_page.dart';
import 'work_entry_sheet.dart';

/// TRABAJO: flexible work (any job, any hours), totals, heat and thermos.
class TrabajoScreen extends ConsumerWidget {
  const TrabajoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    return HosPage(
      title: 'TRABAJO',
      subtitle: fmtDay(today),
      actions: [
        IconButton(
          tooltip: 'Plantillas',
          icon: const Icon(Icons.bookmarks_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TemplatesPage()),
          ),
        ),
      ],
      body: const PanelList(children: [
        _RunningPanel(),
        _QuickLogPanel(),
        _TotalsPanel(),
        _HeatPanel(),
        _AfterWorkPanel(),
        _RecentPanel(),
      ]),
    );
  }
}

Future<void> _updateLog(WidgetRef ref, DailyLogsCompanion fields) =>
    ref.read(dailyLogRepositoryProvider).update(isoDate(ref.read(todayProvider)), fields);

class _RunningPanel extends ConsumerWidget {
  const _RunningPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(inProgressEntryProvider);
    if (running == null) return const SizedBox.shrink();
    final start = running.entry.start!;
    final now = ref.watch(clockProvider)();
    final elapsed = minutesBetween(start, now);
    return TerminalPanel(
      label: 'En curso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine(running.entry.label, 'desde ${fmtTime(start)}', emphasis: true),
          DataLine('Llevas', formatWorkMinutes(elapsed)),
          const Note('Mientras trabajas no llegan avisos, salvo en la pausa planificada.'),
          BigButton(
            label: 'Terminar',
            icon: Icons.stop_circle_outlined,
            onPressed: () async {
              final done = finishWork(running.entry, ref.read(clockProvider)());
              await ref.read(workRepositoryProvider).replaceEntry(running.row.id, done);
              if (context.mounted) {
                toast(context, '${running.entry.label}: ${formatWorkMinutes(done.minutes)}.');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _QuickLogPanel extends ConsumerWidget {
  const _QuickLogPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(activeTemplatesProvider);
    return TerminalPanel(
      label: 'Registrar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (templates.isEmpty)
            const Note('Crea una plantilla (arriba a la derecha) para registrar en tres toques: '
                'plantilla → horas → guardar.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in templates)
                ActionChip(
                  avatar: const Icon(Icons.work_outline, size: 18),
                  label: Text(t.label),
                  onPressed: () => WorkEntrySheet.show(context, template: t),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('OTRO'),
                onPressed: () => WorkEntrySheet.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalsPanel extends ConsumerWidget {
  const _TotalsPanel();

  Future<void> _threshold(BuildContext context, WidgetRef ref, String key, String title, int? current) async {
    final hours = await askNumber(context, title: title, initial: current == null ? null : current / 60, unit: 'h');
    final repo = ref.read(settingsRepositoryProvider);
    if (hours == null) return;
    if (hours <= 0) {
      await repo.remove(key);
    } else {
      await repo.set(key, (hours * 60).round().toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(workSummaryProvider);
    final settings = ref.watch(settingsProvider);
    Widget block(String title, WorkTotals t) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            DataLine('Horas', formatWorkMinutes(t.minutes)),
            DataLine('Ganado (conocido)', t.entries == 0 ? sinDato : formatCents(t.earnedCents)),
            if (t.unknownEarnings > 0) DataLine('Sin dato de pago', '${t.unknownEarnings}'),
            DataLine('Valor de tu hora', t.centsPerHour == null ? sinDato : formatCents(t.centsPerHour!)),
            if (t.overtimeMinutes != null) DataLine('Horas extra', formatWorkMinutes(t.overtimeMinutes!)),
            const SizedBox(height: 8),
          ],
        );
    return TerminalPanel(
      label: 'Totales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block('HOY', s.day),
          block('ESTA SEMANA (LUN–DOM)', s.week),
          block('ESTE MES', s.month),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _threshold(context, ref, SettingKey.overtimeDayMin,
                    'Horas extra a partir de (por día)', settings.overtimeDayMin),
                child: Text(settings.overtimeDayMin == null
                    ? 'EXTRA/DÍA: NO'
                    : 'EXTRA/DÍA > ${formatWorkMinutes(settings.overtimeDayMin!)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _threshold(context, ref, SettingKey.overtimeWeekMin,
                    'Horas extra a partir de (por semana)', settings.overtimeWeekMin),
                child: Text(settings.overtimeWeekMin == null
                    ? 'EXTRA/SEM: NO'
                    : 'EXTRA/SEM > ${formatWorkMinutes(settings.overtimeWeekMin!)}'),
              ),
            ),
          ]),
          const Note('Los umbrales de horas extra son tuyos: escribe 0 para quitarlos.'),
        ],
      ),
    );
  }
}

class _HeatPanel extends ConsumerWidget {
  const _HeatPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(todayLogProvider);
    final plan = ref.watch(hydrationPlanProvider);
    final heatMinutes = ref.watch(heatMinutesTodayProvider);
    final declared = log?.heatMinutes != null;
    return TerminalPanel(
      label: 'Calor y termo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tiempo al calor hoy', style: Theme.of(context).textTheme.labelLarge),
          ValueStepper(
            value: heatMinutes / 60,
            unit: 'h',
            decimals: 2,
            min: 0,
            max: 16,
            steps: const [0.25, 1],
            onChanged: (v) => _updateLog(ref, DailyLogsCompanion(heatMinutes: Value((v * 60).round()))),
          ),
          if (!declared && heatMinutes > 0)
            const Note('Sale de tus plantillas con calor planificadas hoy. Ajústalo si fue distinto.'),
          Text(plan.summaryEs, style: Theme.of(context).textTheme.bodyLarge),
          if (plan.hasHeat) ...[
            Note(plan.basisEs),
            Note(plan.highlightElectrolytes ? '⚠ $electrolyteNoteEs' : electrolyteNoteEs),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('EQUIPO COMPLETO'),
            subtitle: const Text('Ropa de protección completa: sudas más y no se evapora.'),
            value: log?.ppeFull ?? false,
            onChanged: (v) => _updateLog(ref, DailyLogsCompanion(ppeFull: Value(v))),
          ),
          Row(children: [
            Expanded(
              child: FilterChip(
                label: const Text('TERMO ANTES'),
                selected: log?.thermoPre ?? false,
                onSelected: (v) => _updateLog(ref, DailyLogsCompanion(thermoPre: Value(v))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilterChip(
                label: const Text('TERMO EN LA PAUSA'),
                selected: log?.thermoBreak ?? false,
                onSelected: (v) => _updateLog(ref, DailyLogsCompanion(thermoBreak: Value(v))),
              ),
            ),
          ]),
          const Note('Marca cuando llenes el termo: cuenta para el hábito H2O y para RESISTENCIA.'),
        ],
      ),
    );
  }
}

class _AfterWorkPanel extends ConsumerWidget {
  const _AfterWorkPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(todayLogProvider);
    final effort = WorkEffort.parse(log?.workEffort);
    final feel = SweatFeel.parse(log?.sweatFeel);
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Al terminar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿Cuánto sudaste?', style: theme.textTheme.labelLarge),
          Wrap(spacing: 6, children: [
            for (final f in SweatFeel.values)
              ChoiceChip(
                label: Text(f.labelEs),
                selected: f == feel,
                onSelected: (_) => _updateLog(ref, DailyLogsCompanion(sweatFeel: Value(f.code))),
              ),
          ]),
          const SizedBox(height: 8),
          Text('¿Qué tan duro fue? (1–5)', style: theme.textTheme.labelLarge),
          Wrap(spacing: 6, children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: log?.effortFeel == i,
                onSelected: (_) => _updateLog(ref, DailyLogsCompanion(effortFeel: Value(i))),
              ),
          ]),
          const SizedBox(height: 8),
          Text('Esfuerzo físico del día (para la recuperación)', style: theme.textTheme.labelLarge),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in WorkEffort.values)
              ChoiceChip(
                label: Text(e.labelEs),
                selected: e == effort,
                onSelected: (_) => _updateLog(ref, DailyLogsCompanion(workEffort: Value(e.code))),
              ),
          ]),
          const Note('El sudor ajusta el rango del termo de los próximos días.'),
        ],
      ),
    );
  }
}

class _RecentPanel extends ConsumerWidget {
  const _RecentPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(workEntryRowsProvider).value ?? const <WorkEntryRow>[];
    final recent = rows.take(20).toList();
    return TerminalPanel(
      label: 'Registros recientes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recent.isEmpty) const Note('Todavía no registras trabajos.'),
          for (final r in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.label),
              subtitle: Text(
                '${fmtShortDay(parseIsoDate(r.date))} · ${r.endTs == null && r.startTs != null ? 'en curso' : formatWorkMinutes(r.minutes)}'
                '${r.earnedCents == null ? '' : ' · ${formatCents(r.earnedCents!)}'}',
              ),
              trailing: IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Borrar registro',
                    message: '¿Borrar «${r.label}» del ${fmtShortDay(parseIsoDate(r.date))}?',
                    accept: 'BORRAR',
                  );
                  if (ok) await ref.read(workRepositoryProvider).deleteEntry(r.id);
                },
              ),
              onTap: () => WorkEntrySheet.show(context, existing: r),
            ),
        ],
      ),
    );
  }
}
