import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/chores.dart';
import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/status_widgets.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/nutrients.dart';
import '../../../data/settings.dart';
import '../../../telemetry/confidence.dart';
import '../../habitos/domain/habits_model.dart';
import '../../heavy_duty/domain/training_plan.dart';
import '../../registro/domain/intake.dart';
import '../../turno/domain/hydration.dart';
import '../domain/readiness_today.dart';
import '../domain/targets.dart';

/// ESTADO: readiness, energy target, weight trend and today's essentials.
class EstadoScreen extends ConsumerWidget {
  const EstadoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    return HosPage(
      title: 'ESTADO',
      subtitle: fmtDay(today),
      actions: [
        IconButton(
          icon: const Icon(Icons.sync),
          tooltip: 'Leer Health Connect',
          onPressed: () async {
            final result = await syncHealth(ref);
            if (result.ok) await recordReadiness(ref);
            if (context.mounted) toast(context, result.messageEs);
          },
        ),
      ],
      body: const PanelList(children: [
        _ReadinessPanel(),
        _EnergyPanel(),
        _WeightPanel(),
        _TodayPanel(),
      ]),
    );
  }
}

Future<void> askWeight(BuildContext context, WidgetRef ref) async {
  final latest = ref.read(latestWeightProvider);
  final kg = await askNumber(context, title: 'Peso de hoy', initial: latest?.kg, unit: 'kg');
  if (kg == null || kg < 30 || kg > 250) return;
  await ref.read(bodyRepositoryProvider).setWeight(isoDate(ref.read(todayProvider)), kg);
}

Future<void> askRestingHr(BuildContext context, WidgetRef ref) async {
  final bpm = await askNumber(
    context,
    title: 'Pulso en reposo (60 s)',
    unit: 'lpm',
    decimals: 0,
  );
  if (bpm == null || bpm < 25 || bpm > 140) return;
  await ref.read(bodyRepositoryProvider).setRestingHr(isoDate(ref.read(todayProvider)), bpm);
  await recordReadiness(ref);
}

class _ReadinessPanel extends ConsumerWidget {
  const _ReadinessPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(readinessTodayProvider);
    final settings = ref.watch(settingsMapProvider).value ?? const {};
    final lastSync = DateTime.tryParse(settings[SettingKey.healthLastSync] ?? '');
    final syncLine = lastSync == null
        ? 'Health Connect: sin lecturas todavía'
        : 'Health Connect: leído ${fmtShortDay(lastSync)} ${fmtTime(lastSync)}';
    if (r.noData) {
      return TerminalPanel(
        label: 'Recuperación',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('SIN DATOS', style: Theme.of(context).textTheme.headlineMedium),
            const Note(
              'Sin VFC ni pulso en reposo no hay banda. Conecta la banda en '
              'AJUSTES → Datos de salud, o mide tu pulso 60 s al despertar.',
              icon: Icons.info_outline,
            ),
            Note(syncLine),
            const SizedBox(height: 8),
            BigButton(
              label: 'Pulso manual',
              icon: Icons.favorite_border,
              outlined: true,
              onPressed: () => askRestingHr(context, ref),
            ),
          ],
        ),
      );
    }
    final path = switch (r.path) {
      ReadinessPath.hrv => 'VFC (rMSSD) · ${TelemetryKind.hrv.confidenceEs}',
      ReadinessPath.rhr => 'PULSO EN REPOSO · ${TelemetryKind.restingHeartRate.confidenceEs}',
      ReadinessPath.none => 'SIN BASE',
    };
    return TerminalPanel(
      label: 'Recuperación',
      trailing: ConfidenceChip(path.split(' · ').last),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            BandBadge(r.band, large: true),
            const SizedBox(width: 12),
            Expanded(child: Text(path.split(' · ').first, style: Theme.of(context).textTheme.labelLarge)),
          ]),
          const SizedBox(height: 8),
          for (final reason in r.reasonsEs) Note(reason),
          if (r.hrvShortMean != null)
            DataLine('VFC 7 días (ln rMSSD)', fmtNum(r.hrvShortMean, decimals: 2)),
          if (r.hrvLongMean != null)
            DataLine('VFC 60 días (ln rMSSD)', fmtNum(r.hrvLongMean, decimals: 2)),
          if (r.rhrToday != null) DataLine('Pulso en reposo hoy', fmtNum(r.rhrToday, unit: 'lpm')),
          if (r.rhrMean != null) DataLine('Pulso habitual', fmtNum(r.rhrMean, unit: 'lpm')),
          DataLine(
            'Sueño anoche',
            r.sleepLastNightMin == null ? sinDato : formatHoursMinutes(r.sleepLastNightMin!),
          ),
          if (r.sleepDebtH != null) DataLine('Deuda de sueño', fmtNum(r.sleepDebtH, decimals: 1, unit: 'h')),
          if (r.suggestPostpone)
            const Note(
              'Sugerencia: pospón la sesión. Es solo un aviso: en HEAVY DUTY '
              'puedes entrenar igual.',
              icon: Icons.warning_amber,
            ),
          Note(syncLine),
          TextButton.icon(
            onPressed: () => askRestingHr(context, ref),
            icon: const Icon(Icons.favorite_border),
            label: const Text('ANOTAR PULSO MANUAL'),
          ),
        ],
      ),
    );
  }
}

class _EnergyPanel extends ConsumerWidget {
  const _EnergyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(energyStatusProvider);
    final today = isoDate(ref.watch(todayProvider));
    final intake = ref.watch(dayIntakeProvider(today)).value;
    if (status == null) {
      return TerminalPanel(
        label: 'Energía',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Note('Registra tu peso para calcular el objetivo del día.'),
            BigButton(label: 'Pesarme', icon: Icons.monitor_weight_outlined, onPressed: () => askWeight(context, ref)),
          ],
        ),
      );
    }
    final totals = intake?.totals;
    final eaten = totals?.value(NutrientKey.energy);
    final protein = totals?.value(NutrientKey.protein);
    final remaining = status.targetKcal - (eaten ?? 0);
    final m = status.macros;
    return TerminalPanel(
      label: 'Energía',
      trailing: status.adaptive ? null : ConfidenceChip.of(status.dayEnergy.confidence),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Objetivo de hoy', fmtNum(status.targetKcal, unit: 'kcal'), emphasis: true),
          Text(status.modeEs, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          DataLine(
            'Comido',
            fmtTotal(eaten, partial: totals?.isPartial(NutrientKey.energy) ?? false, unit: 'kcal'),
          ),
          DataLine('Falta', fmtNum(remaining < 0 ? 0.0 : remaining, unit: 'kcal')),
          DataLine(
            'Proteína',
            '${fmtTotal(protein, partial: totals?.isPartial(NutrientKey.protein) ?? false)} / '
                '${fmtNum(m.proteinPlanG, unit: 'g')}',
          ),
          DataLine('Por comida', '≥ ${fmtNum(m.proteinPerMealG, unit: 'g')} × ${ref.watch(currentAssumptionsProvider).integer(A.proteinMealsPerDay)}'),
          DataLine('Grasa / carbohidratos', '${fmtNum(m.fatG, unit: 'g')} / ${fmtNum(m.carbG, unit: 'g')}'),
          const SizedBox(height: 6),
          if (status.estimate.sufficient)
            DataLine('Gasto estimado (TDEE)', fmtNum(status.estimate.tdeeKcal, unit: 'kcal'))
          else
            Note(status.estimate.reasonEs),
          if (!status.adaptive) Note(status.dayEnergy.noteEs),
          Note(m.explanationEs),
        ],
      ),
    );
  }
}

class _WeightPanel extends ConsumerWidget {
  const _WeightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(energyStatusProvider);
    final latest = ref.watch(latestWeightProvider);
    final profile = ref.watch(profileProvider).value;
    final today = ref.watch(todayProvider);
    final accent = Theme.of(context).colorScheme.primary;
    final from = addDays(today, -59);
    final points = [
      for (final p in status?.trend ?? const <TrendPoint>[])
        if (!p.date.isBefore(from)) p,
    ];
    final rate = status?.estimate.weeklyRateKg;
    return TerminalPanel(
      label: 'Peso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine(
            'Último',
            latest == null ? sinDato : '${fmtNum(latest.kg, decimals: 1, unit: 'kg')} · ${fmtShortDay(parseIsoDate(latest.date))}',
            emphasis: true,
          ),
          DataLine('Tendencia', fmtNum(status?.trendKg, decimals: 1, unit: 'kg')),
          DataLine('Ritmo', rate == null ? sinDato : '${rate >= 0 ? '+' : ''}${fmtNum(rate, decimals: 2)} kg/semana'),
          DataLine('Meta', fmtNum(profile?.targetWeightKg, decimals: 1, unit: 'kg')),
          if (points.length >= 2) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 59,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (final p in points)
                          FlSpot(daysBetween(from, p.date).toDouble(), p.trendKg),
                      ],
                      color: accent,
                      barWidth: 2,
                      dotData: FlDotData(
                        checkToShowDot: (spot, bar) =>
                            points[bar.spots.indexOf(spot)].measured,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(radius: 2.5, color: accent),
                      ),
                    ),
                  ],
                ),
                duration: Duration.zero,
              ),
            ),
            Text('Línea: tendencia (media móvil). Puntos: pesajes.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          BigButton(
            label: latest?.date == isoDate(today) ? 'Corregir peso de hoy' : 'Pesarme',
            icon: Icons.monitor_weight_outlined,
            outlined: latest?.date == isoDate(today),
            onPressed: () => askWeight(context, ref),
          ),
        ],
      ),
    );
  }
}

class _TodayPanel extends ConsumerWidget {
  const _TodayPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final log = ref.watch(todayLogProvider);
    final plan = ref.watch(hydrationPlanProvider);
    final compliance = ref.watch(hydrationComplianceProvider);
    final session = ref.watch(sessionPlanProvider);
    final overview = ref.watch(habitsOverviewProvider);
    final heat = log?.heatHours ?? 0;
    final sessionLine = session.isDue(today)
        ? 'HOY · ${session.template.code} · ${session.mode.labelEs}'
        : '${fmtDay(session.earliestDate)} · ${session.template.code} · ${session.mode.labelEs}';
    return TerminalPanel(
      label: 'Hoy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine(
            'Agua del turno',
            heat <= 0
                ? 'declara horas de calor en TURNO'
                : '${fmtNum(log?.fluidsL, decimals: 1, unit: 'L')} de '
                    '${fmtNum(plannedLitres(plan), decimals: 1, unit: 'L')}'
                    '${compliance == null ? '' : ' (${fmtNum(compliance * 100)} %)'}',
          ),
          DataLine('Próxima sesión', sessionLine),
          if (overview != null)
            DataLine(
              'Mínimo del día',
              overview.minimumToday.noData
                  ? 'sin registros'
                  : '${overview.minimumToday.done} de ${overview.minimumToday.essentials}'
                      ' (bastan ${overview.minimumToday.required})',
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => ref.read(shellTabProvider.notifier).select(1),
                child: const Text('REGISTRAR'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => ref.read(shellTabProvider.notifier).select(3),
                child: const Text('TURNO'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
