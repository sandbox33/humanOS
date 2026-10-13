import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/status_widgets.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/reference_models.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/readiness_today.dart';
import '../domain/training_plan.dart';
import 'session_page.dart';

/// HEAVY DUTY: next session (template, mode, rest window), readiness,
/// TARGET TO SMASH per exercise, records and history.
class HeavyDutyScreen extends ConsumerWidget {
  const HeavyDutyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(sessionPlanProvider);
    final catalog = ref.watch(exerciseCatalogProvider);
    final templates = ref.watch(exerciseTemplatesProvider);
    final readiness = ref.watch(readinessTodayProvider);
    final today = ref.watch(todayProvider);
    final exercises = templateExercises(plan.template, templates, catalog);
    return HosPage(
      title: 'HEAVY DUTY',
      subtitle: '1 serie al fallo seguro · ${plan.template.code} · ${plan.mode.labelEs}',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Próxima sesión',
          trailing: readiness.noData ? null : BandBadge(readiness.band),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataLine('Plantilla', plan.template.code, emphasis: true),
              DataLine('Modo', plan.mode.labelEs),
              DataLine(
                'Cuándo',
                plan.isDue(today)
                    ? 'HOY (hasta ${fmtShortDay(plan.latestDate)})'
                    : 'desde ${fmtDay(plan.earliestDate)}',
              ),
              for (final reason in plan.reasonsEs) Note(reason),
              if (plan.postponeSuggested)
                const Note('Banda ROJA: se sugiere posponer. No es obligatorio.',
                    icon: Icons.warning_amber),
              const SizedBox(height: 8),
              if (catalog.isEmpty)
                const Note(
                  'Los ejercicios vienen en la base de referencia, que este APK '
                  'no trae.',
                  icon: Icons.info_outline,
                )
              else
                BigButton(
                  label: 'Empezar sesión ${plan.template.code}',
                  icon: Icons.play_arrow,
                  onPressed: exercises.isEmpty ? null : () => _start(context, ref, plan),
                ),
            ],
          ),
        ),
        if (exercises.isNotEmpty) _TargetsPanel(plan: plan, exercises: exercises),
        const _RecordsPanel(),
        const _HistoryPanel(),
      ]),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, SessionPlan plan) async {
    final readiness = ref.read(readinessTodayProvider);
    var overridden = false;
    if (readiness.band == ReadinessBand.rojo && !readiness.noData) {
      final go = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('BANDA ROJA'),
          content: Text(
            '${readiness.reasonsEs.join('\n')}\n\nLa recomendación es posponer. '
            'Puedes entrenar igual; quedará anotado.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('POSPONER'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('ENTRENAR IGUAL'),
            ),
          ],
        ),
      );
      if (go != true) return;
      overridden = true;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SessionPage(
        template: plan.template,
        mode: plan.mode,
        band: readiness.noData ? null : readiness.band,
        overridden: overridden,
      ),
    ));
  }
}

class _TargetsPanel extends ConsumerWidget {
  const _TargetsPanel({required this.plan, required this.exercises});
  final SessionPlan plan;
  final List<ExerciseRecord> exercises;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(trainingHistoryProvider);
    final params = ProgressionParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Target to smash',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in exercises)
            Builder(builder: (context) {
              final t = nextExerciseTarget(e.toSpec(), history, mode: plan.mode, params: params);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(e.nameEs.toUpperCase(), style: theme.textTheme.titleMedium),
                    DataLine('Supera', previousText(e, t.previousBest)),
                    DataLine('Objetivo', targetText(e, t)),
                    if (!e.failureSafe)
                      Note('NO AL FALLO: termina con ${t.rirTarget ?? 2} repeticiones en reserva.',
                          icon: Icons.back_hand_outlined),
                    Note(t.messageEs),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

String loadText(ExerciseRecord e, double? kg) {
  if (kg == null) return 'carga por elegir';
  return e.assisted
      ? 'asistencia ${fmtNum(kg, decimals: 1, unit: 'kg')}'
      : fmtNum(kg, decimals: 1, unit: 'kg');
}

String previousText(ExerciseRecord e, SetRecord? best) {
  if (best == null) return 'sin historial';
  final unit = e.timed ? 's' : 'reps';
  return '${loadText(e, best.loadKg)} × ${best.validReps} $unit';
}

String targetText(ExerciseRecord e, ExerciseTarget t) {
  final unit = e.timed ? 's' : 'reps';
  return '${loadText(e, t.loadKg)} × ${t.repTarget} $unit';
}

class _RecordsPanel extends ConsumerWidget {
  const _RecordsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(personalRecordsProvider).value ?? const <PersonalRecordRow>[];
    final catalog = ref.watch(exerciseCatalogProvider);
    if (records.isEmpty) return const SizedBox.shrink();
    return TerminalPanel(
      label: 'Récords',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in records)
            DataLine(
              catalog[r.exerciseId]?.nameEs ?? 'Ejercicio ${r.exerciseId}',
              '${fmtNum(r.loadKg, decimals: 1, unit: 'kg')} × ${r.reps} · 1RM est. '
              '${fmtNum(r.e1rm, decimals: 1, unit: 'kg')} · ${fmtShortDay(parseIsoDate(r.date))}',
            ),
          const Note('1RM estimado con Epley: carga × (1 + reps / 30).'),
        ],
      ),
    );
  }
}

class _HistoryPanel extends ConsumerWidget {
  const _HistoryPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).value ?? const <SessionRow>[];
    final sets = ref.watch(setsProvider).value ?? const <SetRow>[];
    if (sessions.isEmpty) {
      return const TerminalPanel(
        label: 'Historial',
        child: Note('Sin sesiones todavía. La primera es la BASELINE: busca tus cargas.'),
      );
    }
    final work = <int, int>{};
    for (final s in sets) {
      if (!s.isWarmup) work[s.sessionId] = (work[s.sessionId] ?? 0) + 1;
    }
    return TerminalPanel(
      label: 'Historial',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in sessions.take(12))
            InkWell(
              onLongPress: () async {
                final ok = await confirm(
                  context,
                  title: 'Borrar sesión',
                  message: 'Se borra la sesión del ${s.date} con sus series. '
                      'Los récords guardados no cambian.',
                  accept: 'BORRAR',
                );
                if (ok) await ref.read(trainingRepositoryProvider).deleteSession(s.id);
              },
              child: DataLine(
                '${fmtShortDay(parseIsoDate(s.date))} · ${s.template}'
                '${s.mode == 'normal' ? '' : ' · ${SessionMode.parse(s.mode).labelEs}'}',
                '${work[s.id] ?? 0} series'
                '${s.readiness == null ? '' : ' · ${s.readiness}${s.readinessOverridden ? ' (entrenó igual)' : ''}'}',
              ),
            ),
          const Note('Mantén pulsada una sesión para borrarla.'),
        ],
      ),
    );
  }
}
