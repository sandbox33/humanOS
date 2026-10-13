import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/nutrients.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';
import '../../heavy_duty/domain/training_plan.dart';
import '../../indice/presentation/catalog_search.dart';
import '../domain/intake.dart';
import 'add_item_sheet.dart';

final mealTemplatesProvider = StreamProvider<List<MealTemplateRow>>(
  (ref) => ref.watch(mealsRepositoryProvider).watchTemplates(),
);

/// Meal slots of a day from the shift and the training plan.
List<MealSlot> slotsFor(WidgetRef ref, DateTime date) {
  final profile = ref.watch(profileProvider).value;
  final a = ref.watch(currentAssumptionsProvider);
  final today = ref.watch(todayProvider);
  final iso = isoDate(date);
  final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
  final log = logs.where((l) => l.date == iso).firstOrNull;
  final sessions = ref.watch(sessionsProvider).value ?? const <SessionRow>[];
  final trained = sessions.any((s) => s.date == iso) ||
      (date == today && ref.watch(sessionPlanProvider).isDue(today));
  final shift = ShiftConfig.fromClock(
    shiftStart: profile?.shiftStart ?? '07:00',
    shiftEnd: profile?.shiftEnd ?? '17:00',
    lunchStart: profile?.lunchStart ?? '12:00',
  );
  return mealSchedule(
    shift: shift,
    trainingDay: trained,
    workday: WorkEffort.parse(log?.workEffort) != WorkEffort.off,
    params: ScheduleParams.fromAssumptions(a),
  );
}

/// REGISTRO: what was eaten, by meal block, with day totals, interaction
/// warnings (never blocking), templates and "repetir ayer".
class RegistroScreen extends ConsumerStatefulWidget {
  const RegistroScreen({super.key});

  @override
  ConsumerState<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends ConsumerState<RegistroScreen> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final date = addDays(today, -_offset);
    final iso = isoDate(date);
    final intake = ref.watch(dayIntakeProvider(iso)).value;
    final slots = slotsFor(ref, date);
    final scheduled = {for (final s in slots) s.block};
    final extra = [
      for (final b in MealBlock.values)
        if (!scheduled.contains(b) && (intake?.inBlock(b).isNotEmpty ?? false)) b,
    ];
    return HosPage(
      title: 'REGISTRO',
      subtitle: _offset == 0 ? 'HOY · ${fmtDay(date)}' : fmtDay(date),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Día anterior',
          onPressed: _offset >= 59 ? null : () => setState(() => _offset++),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Día siguiente',
          onPressed: _offset == 0 ? null : () => setState(() => _offset--),
        ),
      ],
      floatingActionButton: FloatingActionButton.large(
        tooltip: 'Añadir',
        onPressed: () => _add(iso, _currentBlock(slots, date)),
        child: const Icon(Icons.add),
      ),
      body: PanelList(children: [
        _DayTotals(date: iso, intake: intake),
        for (final slot in slots)
          _BlockPanel(date: iso, block: slot.block, slot: slot, intake: intake, slots: slots),
        for (final b in extra)
          _BlockPanel(date: iso, block: b, intake: intake, slots: slots),
        _DayActions(date: date),
      ]),
    );
  }

  /// The block whose time is closest before now (today) or lunch otherwise.
  MealBlock _currentBlock(List<MealSlot> slots, DateTime date) {
    if (_offset != 0 || slots.isEmpty) return MealBlock.lunch;
    final now = ref.read(clockProvider)();
    final minute = now.hour * 60 + now.minute;
    var best = slots.first;
    for (final s in slots) {
      if (s.minuteOfDay <= minute + 30) best = s;
    }
    return best.block;
  }

  Future<void> _add(String date, MealBlock block) async {
    final choice = await pickFood(context, title: 'Añadir', pantryFirst: true);
    if (choice == null || !mounted) return;
    await showAddItemSheet(context, choice: choice, date: date, block: block);
  }
}

class _DayTotals extends ConsumerWidget {
  const _DayTotals({required this.date, required this.intake});
  final String date;
  final DayIntake? intake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = intake?.totals;
    final status = ref.watch(energyStatusProvider);
    String line(NutrientKey key, {int decimals = 0}) => fmtTotal(
          totals?.value(key),
          partial: totals?.isPartial(key) ?? false,
          decimals: decimals,
          unit: key.unit,
        );
    final missingEnergy = totals?.missingIn(NutrientKey.energy) ?? const <String>[];
    final isToday = date == isoDate(ref.watch(todayProvider));
    return TerminalPanel(
      label: 'Total del día',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine(
            'Energía',
            isToday && status != null
                ? '${line(NutrientKey.energy)} / ${fmtNum(status.targetKcal, unit: 'kcal')}'
                : line(NutrientKey.energy),
            emphasis: true,
          ),
          DataLine(
            'Proteína',
            isToday && status != null
                ? '${line(NutrientKey.protein)} / ${fmtNum(status.macros.proteinPlanG, unit: 'g')}'
                : line(NutrientKey.protein),
          ),
          DataLine('Carbohidratos', line(NutrientKey.carbs)),
          DataLine('Grasa', line(NutrientKey.fat)),
          DataLine('Fibra', line(NutrientKey.fiber, decimals: 1)),
          DataLine('Sodio', line(NutrientKey.sodium)),
          if (totals != null && NutrientKey.values.any(totals.isPartial))
            const Note('"≥" = algún alimento no tiene ese dato: el total es un mínimo.'),
          if (missingEnergy.isNotEmpty)
            Note('Sin dato de energía: ${missingEnergy.toSet().join(', ')}.'),
        ],
      ),
    );
  }
}

class _BlockPanel extends ConsumerWidget {
  const _BlockPanel({
    required this.date,
    required this.block,
    required this.intake,
    required this.slots,
    this.slot,
  });

  final String date;
  final MealBlock block;
  final MealSlot? slot;
  final DayIntake? intake;
  final List<MealSlot> slots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = intake;
    final items = day?.inBlock(block) ?? const <LoggedItem>[];
    final totals = day?.blockTotals[block];
    final settings = ref.watch(settingsProvider);
    final a = ref.watch(currentAssumptionsProvider);
    final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
    final log = logs.where((l) => l.date == date).firstOrNull;
    final report = day == null || items.isEmpty
        ? null
        : blockInteractions(
            day: day,
            block: block,
            blockMinutes: {for (final s in slots) s.block: s.minuteOfDay},
            params: InteractionParams.fromAssumptions(a),
            shiftDay: WorkEffort.parse(log?.workEffort) != WorkEffort.off,
          );
    final theme = Theme.of(context);
    return TerminalPanel(
      label: slot == null ? block.labelEs : '${block.labelEs} · ${slot!.clock}',
      trailing: totals == null
          ? null
          : Text(
              fmtTotal(
                totals.value(NutrientKey.energy),
                partial: totals.isPartial(NutrientKey.energy),
                unit: 'kcal',
              ),
              style: theme.textTheme.labelLarge,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slot != null) Note(slot!.contextEs),
          if (block == MealBlock.lunch && settings.fiberFirst)
            const Note(
              'Orden sugerido: verduras y fibra primero, luego la proteína y al '
              'final los carbohidratos.',
            ),
          for (final item in items) _ItemRow(item: item),
          if (report != null) ...[
            for (final w in report.warnings)
              Note(w.messageEs, icon: w.severity == WarningSeverity.media ? Icons.warning_amber : Icons.info_outline),
            for (final s in report.synergiesEs) Note(s, icon: Icons.thumb_up_alt_outlined),
            if (report.missingDataEs.isNotEmpty)
              Note('Datos que faltan: ${report.missingDataEs.join('; ')}.'),
          ],
          Row(children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('AÑADIR'),
                onPressed: () async {
                  final choice = await pickFood(context, title: 'Añadir', pantryFirst: true);
                  if (choice == null || !context.mounted) return;
                  await showAddItemSheet(context, choice: choice, date: date, block: block);
                },
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.bookmarks_outlined),
                label: const Text('PLANTILLA'),
                onPressed: () => _templates(context, ref, items),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _templates(BuildContext context, WidgetRef ref, List<LoggedItem> items) async {
    final templates = ref.read(mealTemplatesProvider).value ?? const <MealTemplateRow>[];
    final repo = ref.read(mealsRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          for (final t in templates)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(title: Text(t.nameEs)),
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.of(sheet).pop();
                          final n = await repo.applyTemplate(t.id, date, block);
                          messenger.showSnackBar(SnackBar(
                            content: Text(n == 0
                                ? 'La plantilla está vacía: guarda primero un bloque en ella.'
                                : '$n elementos añadidos (sin descontar de la despensa).'),
                          ));
                        },
                        child: const Text('USAR AQUÍ'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: items.isEmpty
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                Navigator.of(sheet).pop();
                                final n = await repo.saveAsTemplate(
                                    t.id, [for (final i in items) i.row]);
                                messenger.showSnackBar(SnackBar(
                                  content: Text('Plantilla "${t.nameEs}": $n elementos.'),
                                ));
                              },
                        child: const Text('GUARDAR BLOQUE'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});
  final LoggedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _actions(context, ref),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.food.name, style: theme.textTheme.bodyLarge),
                    Text(
                      '${fmtNum(item.row.grams, unit: 'g')} · '
                      'P ${fmtNum(item.proteinG, decimals: 1, unit: 'g')}'
                      '${item.row.pantryItemId == null ? '' : ' · despensa'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(fmtNum(item.kcal, unit: 'kcal'), style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(mealsRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(title: Text(item.food.name)),
          ListTile(
            leading: const Icon(Icons.scale_outlined),
            title: const Text('CAMBIAR GRAMOS'),
            onTap: () => Navigator.of(sheet).pop('grams'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('QUITAR'),
            subtitle: item.row.pantryItemId == null
                ? null
                : const Text('Los gramos vuelven a la despensa'),
            onTap: () => Navigator.of(sheet).pop('remove'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'remove') {
      await repo.removeItem(item.row);
    } else if (action == 'grams') {
      final grams = await askNumber(context, title: 'Gramos', initial: item.row.grams, unit: 'g', decimals: 0);
      if (grams == null || grams <= 0) return;
      final result = await repo.updateItemGrams(item.row, grams);
      final message = stockMessage(result);
      if (message != null && context.mounted) toast(context, message);
    }
  }
}

class _DayActions extends ConsumerWidget {
  const _DayActions({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iso = isoDate(date);
    final logs = ref.watch(dailyLogsProvider).value ?? const <DailyLogRow>[];
    final complete = logs.where((l) => l.date == iso).firstOrNull?.intakeComplete ?? false;
    return TerminalPanel(
      label: 'Día',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('DÍA COMPLETO'),
            subtitle: const Text(
              'Actívalo solo si registraste todo lo que comiste. Solo los días '
              'completos ajustan tu gasto real (hacen falta 14).',
            ),
            value: complete,
            onChanged: (v) => ref
                .read(dailyLogRepositoryProvider)
                .update(iso, DailyLogsCompanion(intakeComplete: Value(v))),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: const Text('REPETIR EL DÍA ANTERIOR'),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Repetir',
                message: 'Copiar aquí todo lo registrado el día anterior '
                    '(sin descontar de la despensa).',
                accept: 'COPIAR',
              );
              if (!ok) return;
              final n = await ref.read(mealsRepositoryProvider).repeatDay(
                    from: isoDate(addDays(date, -1)),
                    to: iso,
                  );
              if (context.mounted) {
                toast(context, n == 0 ? 'El día anterior está vacío.' : '$n elementos copiados.');
              }
            },
          ),
        ],
      ),
    );
  }
}
