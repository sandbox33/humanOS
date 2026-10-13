import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/chores.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/seed.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../estado/domain/targets.dart';
import '../domain/habits_model.dart';

/// HÁBITOS: the three streak tiers (minimum, global, per habit), today's
/// habits, the minimum mission and the four attributes. A broken streak
/// shows the best streak and the days achieved in 30, never a red zero.
class HabitosScreen extends ConsumerWidget {
  const HabitosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(habitsOverviewProvider);
    return HosPage(
      title: 'HÁBITOS',
      body: overview == null
          ? const Center(child: Text('Cargando…'))
          : PanelList(children: [
              if (overview.suggestMission) _MissionPanel(overview: overview),
              _StreaksPanel(overview: overview),
              _TodayPanel(overview: overview),
              const _AttributesPanel(),
            ]),
    );
  }
}

class _StreakBlock extends StatelessWidget {
  const _StreakBlock({required this.title, required this.summary});
  final String title;
  final StreakSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          if (summary.broken) ...[
            Text('MEJOR ${summary.best}', style: theme.textTheme.headlineMedium),
            Text('${summary.completedLast30} días cumplidos en 30', style: theme.textTheme.bodySmall),
          ] else ...[
            Text('${summary.current} DÍAS', style: theme.textTheme.headlineMedium),
            Text('mejor ${summary.best} · ${summary.completedLast30}/30', style: theme.textTheme.bodySmall),
          ],
          if (summary.repairTokens > 0)
            Text('comodines: ${summary.repairTokens}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StreaksPanel extends ConsumerWidget {
  const _StreaksPanel({required this.overview});
  final HabitsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final every = ref.watch(currentAssumptionsProvider).integer(A.repairTokenEveryDays);
    return TerminalPanel(
      label: 'Rachas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _StreakBlock(title: 'MÍNIMA', summary: overview.minimum),
            _StreakBlock(title: 'GLOBAL', summary: overview.global),
          ]),
          const SizedBox(height: 6),
          Note(
            'Mínima: ${overview.minimumToday.required} de las '
            '${overview.minimumToday.essentials} esenciales. Global: el día suma '
            'según el peso de cada hábito. Cada $every días cumplidos ganas '
            'un comodín que cubre un día fallado.',
          ),
        ],
      ),
    );
  }
}

class _MissionPanel extends StatelessWidget {
  const _MissionPanel({required this.overview});
  final HabitsOverview overview;

  @override
  Widget build(BuildContext context) {
    final essentials = overview.habits.where((h) => h.isMinimum).map((h) => h.alias).join(' · ');
    return TerminalPanel(
      label: 'Misión mínima',
      child: Note(
        'Dos días seguidos sin el mínimo. Hoy solo cuenta lo esencial: '
        '${overview.minimumToday.required} de estas: $essentials.',
        icon: Icons.flag_outlined,
      ),
    );
  }
}

String _targetText(HabitRow h) => switch (HabitMetric.parse(h.metric)) {
      HabitMetric.check => 'hecho / no hecho',
      HabitMetric.atLeast => '≥ ${fmtNum(h.target, decimals: h.target != null && h.target! < 10 ? 1 : 0)}',
      HabitMetric.atMost => '≤ ${fmtNum(h.target)}',
    };

String _sourceText(String? source) => switch (source) {
      HabitSource.proteinG => 'proteína registrada (g)',
      HabitSource.weighIn => 'pesaje del día',
      HabitSource.sober => 'día sin alcohol ni drogas',
      HabitSource.screenMinutes => 'minutos de pantalla en ocio',
      HabitSource.hydrationPct => '% del agua del turno',
      HabitSource.big3 => 'Big 3 de McGill',
      HabitSource.sleepHours => 'horas de sueño',
      _ => 'manual',
    };

class _TodayPanel extends ConsumerWidget {
  const _TodayPanel({required this.overview});
  final HabitsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(habitsRepositoryProvider);
    final today = isoDate(ref.watch(todayProvider));
    final log = ref.watch(todayLogProvider);
    return TerminalPanel(
      label: 'Hoy',
      trailing: Text(
        overview.scoreToday.noData ? 'sin registros' : '${fmtNum(overview.scoreToday.fraction * 100)} %',
        style: theme.textTheme.labelLarge,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in overview.habits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: HabitMetric.parse(h.metric) == HabitMetric.check
                            ? null
                            : () async {
                                final target = await askNumber(context, title: 'Meta de ${h.alias}', initial: h.target);
                                if (target != null && target >= 0) await repo.updateHabit(h, target: target);
                              },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${h.alias}${h.isMinimum ? ' · ESENCIAL' : ''}', style: theme.textTheme.titleMedium),
                            Text('${_sourceText(h.source)} · ${_targetText(h)}', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    _ValueCell(habit: h, value: overview.today[h.id]),
                  ]),
                  _HabitControl(habit: h, today: today, sober: log?.sober),
                  Builder(builder: (context) {
                    final streak = overview.perHabit[h.id];
                    if (streak == null) return const SizedBox.shrink();
                    return Text(
                      streak.broken
                          ? 'mejor racha ${streak.best} · ${streak.completedLast30} días en 30'
                          : 'racha ${streak.current} · mejor ${streak.best}',
                      style: theme.textTheme.bodySmall,
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.habit, required this.value});
  final HabitRow habit;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final text = switch (HabitMetric.parse(habit.metric)) {
      HabitMetric.check => v == null ? '—' : (v > 0 ? 'HECHO' : 'NO'),
      _ => v == null ? sinDato : fmtNum(v, decimals: v < 10 ? 1 : 0),
    };
    return Text(text, style: theme.textTheme.titleLarge);
  }
}

/// Manual input where a habit needs it (B3, CLARO, VISOR, NOCHE).
class _HabitControl extends ConsumerWidget {
  const _HabitControl({required this.habit, required this.today, required this.sober});
  final HabitRow habit;
  final String today;
  final bool? sober;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(habitsRepositoryProvider);
    final logs = ref.read(dailyLogRepositoryProvider);
    switch (habit.source) {
      case HabitSource.big3:
      case null:
        return Row(children: [
          TextButton(onPressed: () => repo.setValue(habit.id, today, 1), child: const Text('HECHO')),
          TextButton(onPressed: () => repo.clearValue(habit.id, today), child: const Text('BORRAR')),
        ]);
      case HabitSource.sober:
        return Row(children: [
          ChoiceChip(
            label: const Text('SÍ'),
            selected: sober == true,
            onSelected: (_) => logs.update(today, const DailyLogsCompanion(sober: Value(true))),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('NO'),
            selected: sober == false,
            onSelected: (_) => logs.update(today, const DailyLogsCompanion(sober: Value(false))),
          ),
        ]);
      case HabitSource.screenMinutes:
        return Row(children: [
          TextButton(
            onPressed: () async {
              final source = ref.read(screenTimeProvider);
              if (source != null && !await source.hasPermission()) {
                if (!context.mounted) return;
                final open = await confirm(
                  context,
                  title: 'Tiempo de pantalla',
                  message: 'Android pide permiso de "acceso al uso" para leer el '
                      'tiempo de pantalla. Se abre la configuración: activa HumanOS.',
                  accept: 'ABRIR',
                );
                if (open) await source.openSettings();
                return;
              }
              final minutes = await syncScreenTime(ref);
              if (context.mounted) {
                toast(context, minutes == null ? 'No se pudo leer el tiempo de pantalla.' : 'Hoy: $minutes min.');
              }
            },
            child: const Text('LEER DEL TELÉFONO'),
          ),
          TextButton(
            onPressed: () async {
              final minutes = await askNumber(context, title: 'Minutos de pantalla', unit: 'min', decimals: 0);
              if (minutes != null && minutes >= 0) {
                await logs.update(today, DailyLogsCompanion(screenMinutes: Value(minutes.round())));
              }
            },
            child: const Text('ANOTAR'),
          ),
        ]);
      case HabitSource.sleepHours:
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () async {
              final hours = await askNumber(context, title: 'Horas dormidas', unit: 'h');
              if (hours != null && hours >= 0 && hours <= 16) await repo.setValue(habit.id, today, hours);
            },
            child: const Text('ANOTAR A MANO'),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _AttributesPanel extends ConsumerWidget {
  const _AttributesPanel();

  static const _explain = {
    AttributeKind.fuerza: '1RM estimado frente a tu primera sesión de cada ejercicio.',
    AttributeKind.resistencia: 'Turnos con calor en los que bebiste lo planificado.',
    AttributeKind.recuperacion: 'Sueño de la semana y pulso en reposo frente a tu base.',
    AttributeKind.disciplina: 'Días sobrios, pantalla bajo el límite y mínimo cumplido.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(attributesProvider);
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Atributos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final kind in AttributeKind.values) ...[
            DataLine(
              kind.labelEs,
              values[kind] == null ? sinDato : fmtNum(values[kind]! * 100),
              emphasis: true,
            ),
            Text(_explain[kind]!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
          ],
          Note(
            'Escala 0–100 de los últimos '
            '${ref.watch(currentAssumptionsProvider).integer(A.attrWindowDays)} días. '
            'Sin datos no hay número.',
          ),
        ],
      ),
    );
  }
}
