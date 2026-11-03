import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/nutrients.dart';
import '../../../services/services.dart';
import '../../cierre/presentation/cierre_screen.dart';
import '../../despensa/domain/meal_day.dart';
import '../../despensa/domain/pantry_model.dart';
import '../../estado/domain/targets.dart';
import '../../filtro/domain/dns_model.dart';
import '../../finanzas/domain/finance_model.dart';
import '../../finanzas/domain/pay_model.dart';
import '../../finanzas/presentation/pay_panels.dart';
import '../../registro/domain/intake.dart';
import '../domain/schedule_model.dart';
import 'apps_page.dart';
import 'horario_page.dart';
import 'today_sheet.dart';

/// How long the clock must be held to open Ajustes → Apps predeterminadas.
const escapeHold = Duration(seconds: 5);

/// INICIO: the home screen. The current block in large type with its
/// countdown, the next one, the day's numbers and the user's pinned apps.
class InicioScreen extends ConsumerWidget {
  const InicioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const Scaffold(
        body: SafeArea(
          child: PanelList(children: [
            ClockHeader(),
            _NowPanel(),
            MealNowPanel(),
            _DayNumbers(),
            PinnedApps(),
          ]),
        ),
      );
}

/// The clock. Holding it for [escapeHold] opens the system's home-screen
/// choice, so the user can always go back to the phone's own launcher.
class ClockHeader extends ConsumerStatefulWidget {
  const ClockHeader({super.key});

  @override
  ConsumerState<ClockHeader> createState() => _ClockHeaderState();
}

class _ClockHeaderState extends ConsumerState<ClockHeader> {
  Timer? _hold;

  void _down() {
    _hold?.cancel();
    _hold = Timer(escapeHold, () => ref.read(launcherProvider).openHomeSettings());
  }

  void _up() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(minuteTickProvider).value ?? ref.watch(clockProvider)();
    final theme = Theme.of(context);
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatClock(now.hour * 60 + now.minute), style: theme.textTheme.displayLarge),
            Text(DateFormat("EEEE d 'de' MMMM", 'es').format(now).toUpperCase(), style: theme.textTheme.titleMedium),
            Text('Mantén el reloj 5 s para elegir otra pantalla de inicio.', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _NowPanel extends ConsumerWidget {
  const _NowPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templates = ref.watch(blockTemplatesProvider);
    final now = ref.watch(blockNowProvider);
    final current = now.current;
    final next = now.next;
    return TerminalPanel(
      label: 'Ahora',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (templates.isEmpty) ...[
            const Note('Aún no armaste tu día. Crea tus bloques (comidas, trabajo, entreno, proyecto, dormir…) '
                'con tus propias horas.'),
            BigButton(
              label: 'Armar mi horario',
              icon: Icons.schedule,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HorarioPage())),
            ),
          ] else ...[
            Text(current?.title.toUpperCase() ?? 'LIBRE', style: theme.textTheme.displaySmall),
            if (current != null)
              Text(
                'Quedan ${countdownEs(now.minutesLeft!)}'
                '${current.status == BlockStatus.normal ? '' : ' · ${current.status.labelEs}'}',
                style: theme.textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            if (next != null)
              DataLine('Sigue: ${next.title}', 'a las ${formatClock(next.startMin % (24 * 60))} · en ${countdownEs(now.minutesToNext!)}'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => TodaySheet.show(context), child: const Text('AJUSTAR HOY')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HorarioPage())),
                  child: const Text('HORARIO'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _DayNumbers extends ConsumerWidget {
  const _DayNumbers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final status = ref.watch(energyStatusProvider);
    final totals = ref.watch(dayIntakeProvider(isoDate(today))).value?.totals;
    final eaten = totals?.value(NutrientKey.energy);
    final protein = totals?.value(NutrientKey.protein);
    final day = isoDate(today);
    final spent = (ref.watch(expenseRowsProvider).value ?? const [])
        .where((e) => e.date == day)
        .fold(0, (a, e) => a + e.amountCents);
    final goals = ref.watch(goalsProvider);
    final goal = orderedActiveGoals(goals).where((g) => goalProgress(g, goals).targetCents != null).firstOrNull;
    final progress = goal == null ? null : goalProgress(goal, goals);
    return TerminalPanel(
      label: 'Hoy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine(
            'Energía',
            '${fmtTotal(eaten, partial: totals?.isPartial(NutrientKey.energy) ?? false, unit: 'kcal')}'
                '${status == null ? '' : ' / ${fmtNum(status.targetKcal, unit: 'kcal')}'}',
          ),
          DataLine(
            'Proteína',
            '${fmtTotal(protein, partial: totals?.isPartial(NutrientKey.protein) ?? false)}'
                '${status == null ? '' : ' / ${fmtNum(status.macros.proteinPlanG, unit: 'g')}'}',
          ),
          DataLine('Gastado hoy', formatCents(spent)),
          if (ref.watch(cashViewProvider) case final cash when cash.cashCents != null)
            DataLine(
              'Efectivo',
              '${formatCents(cash.cashCents!)}${cash.days == null ? '' : ' · te alcanza ${cash.days} días'}',
            ),
          DataLine('Filtro DNS', ref.watch(filterStatusProvider)?.status.labelEs ?? 'sin comprobar'),
          if (goal != null && progress != null) ...[
            DataLine(goal.title, '${formatCents(progress.savedCents)} de ${formatCents(progress.targetCents!)}'),
            if (goalEtaWeeks(goal, goals, ref.watch(averageSurplusProvider)) case final weeks?)
              Text(weeks == 0 ? 'Meta cubierta.' : 'Al ritmo actual: unas $weeks semanas.',
                  style: Theme.of(context).textTheme.bodySmall),
            LinearProgressIndicator(
              value: progress.targetCents == 0 ? 1 : (progress.savedCents / progress.targetCents!).clamp(0, 1).toDouble(),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: () => QuickExpenseSheet.show(context),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('GASTÉ'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CierreScreen())),
              icon: const Icon(Icons.nightlight_outlined),
              label: const Text('CERRAR EL DÍA'),
            ),
          ]),
        ],
      ),
    );
  }
}

/// The phone's dialer (from the system) and the apps the user pinned.
class PinnedApps extends ConsumerWidget {
  const PinnedApps({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.watch(launcherProvider);
    final pinned = ref.watch(pinnedAppsProvider).value ?? const [];
    return TerminalPanel(
      label: 'Apps',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => launcher.openDialer(),
              icon: const Icon(Icons.call),
              label: const Text('TELÉFONO'),
            ),
            for (final app in pinned)
              OutlinedButton.icon(
                onPressed: () => openApp(context, ref, app),
                icon: AppIcon(app.package, size: 24),
                label: Text(app.label.toUpperCase()),
              ),
          ]),
          if (pinned.isEmpty)
            const Note('Fija tus apps de siempre (por ejemplo, tu mensajería) desde TODAS LAS APPS: mantén pulsada una app.'),
          const SizedBox(height: 8),
          BigButton(
            label: 'Todas las apps',
            icon: Icons.apps,
            outlined: true,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppsPage())),
          ),
        ],
      ),
    );
  }
}

/// COMER AHORA (B4): what the current meal of the schedule needs from the
/// pantry, logged with one tap (the pantry is decremented; short stock
/// warns, never blocks).
class MealNowPanel extends ConsumerWidget {
  const MealNowPanel({super.key});

  Future<void> _logAll(BuildContext context, WidgetRef ref, SlotPlan p) async {
    final stock = {for (final s in ref.read(stockViewProvider)) s.key: s};
    final repo = ref.read(mealsRepositoryProvider);
    final date = isoDate(ref.read(todayProvider));
    var short = 0;
    for (final e in p.grams.entries) {
      final s = stock[e.key];
      if (s == null) continue;
      final result = await repo.addItem(
        date: date,
        block: p.slot.block,
        grams: e.value.roundToDouble(),
        foodId: s.row.foodId,
        barcode: s.row.barcode,
        pantryItemId: s.row.id,
      );
      if (result.insufficient) short++;
    }
    if (!context.mounted) return;
    toast(
      context,
      short == 0
          ? '${p.slot.contextEs} registrado.'
          : '${p.slot.contextEs} registrado. $short alimento(s) con menos stock del registrado: revisa la despensa.',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mealDayPlanProvider);
    if (plans.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(minuteTickProvider).value ?? ref.watch(clockProvider)();
    final slot = slotAt([for (final p in plans) p.slot], now.hour * 60 + now.minute);
    final p = plans.firstWhere((x) => x.slot == slot);
    final stock = {for (final s in ref.watch(stockViewProvider)) s.key: s};
    return TerminalPanel(
      label: 'Comer ahora · ${p.slot.contextEs}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.noteEs != null)
            Note(p.noteEs!)
          else if (p.grams.isEmpty)
            Note([
              p.plan?.messageEs ?? 'La despensa no alcanza para esta comida.',
              if (p.plan?.excludedEs.isNotEmpty ?? false) 'No usados: ${p.plan!.excludedEs.join('; ')}.',
            ].join(' '))
          else ...[
            for (final e in p.grams.entries) DataLine(stock[e.key]?.food.name ?? e.key, fmtNum(e.value, unit: 'g')),
            const SizedBox(height: 8),
            BigButton(label: 'Lo comí', icon: Icons.check, onPressed: () => _logAll(context, ref, p)),
          ],
        ],
      ),
    );
  }
}
