import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../trabajo/domain/work_model.dart';
import '../data/finance_repository.dart';
import '../domain/finance_model.dart';

final _money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

/// FINANZAS: expenses, goals and small explained advice. General
/// information only; no trading, no external rates.
class FinanzasScreen extends ConsumerWidget {
  const FinanzasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => HosPage(
        title: 'FINANZAS',
        subtitle: 'Gastos, metas y consejos pequeños',
        body: PanelList(children: const [
          Note(advisorDisclaimerEs, icon: Icons.info_outline),
          _AdvicePanel(),
          _WeekPanel(),
          _PausesPanel(),
          _GoalsPanel(),
          _ExpensesPanel(),
          _FinanceSettingsPanel(),
        ]),
      );
}

// ---------------------------------------------------------------- advice

class _AdvicePanel extends ConsumerWidget {
  const _AdvicePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todaysAdviceProvider);
    final settings = ref.watch(financeSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    if (today.fresh) {
      // Keep today's choice: a dismissal never brings in a new piece.
      final day = isoDate(ref.read(todayProvider));
      final codes = today.advice.map((a) => a.rule.code).join(',');
      scheduleMicrotask(() => repo.set(FinanceKey.adviceDay, '$day:$codes'));
    }
    return TerminalPanel(
      label: 'Consejos de hoy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (today.advice.isEmpty)
            const Note('Nada por hoy. Los consejos salen de tus propios registros de trabajo, gastos y metas.'),
          for (final a in today.advice) ...[
            Text(a.textEs, style: Theme.of(context).textTheme.bodyLarge),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Números · ${a.rule.labelEs}', style: Theme.of(context).textTheme.labelMedium),
              children: [
                for (final (label, value) in a.numbers) DataLine(label, value),
                DataLine('Regla', a.rule.labelEs),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => repo.set(
                  FinanceKey.dismissedRules,
                  {...settings.dismissed, a.rule}.map((r) => r.code).join(','),
                ),
                child: const Text('NO MOSTRAR MÁS ESTA REGLA'),
              ),
            ),
            const Divider(),
          ],
          if (settings.dismissed.isNotEmpty)
            TextButton(
              onPressed: () => repo.remove(FinanceKey.dismissedRules),
              child: Text('VOLVER A MOSTRAR ${settings.dismissed.length} REGLA(S) OCULTA(S)'),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ week

class _WeekPanel extends ConsumerWidget {
  const _WeekPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flows = weeklyFlows(
      income: MoneyIn.fromWork(ref.watch(workEntriesProvider)),
      expenses: ref.watch(expensesProvider),
      today: ref.watch(todayProvider),
    );
    final week = flows.last;
    final rate = week.savingsRate;
    final perHour = ref.watch(workSummaryProvider).month.centsPerHour;
    return TerminalPanel(
      label: 'Esta semana',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Ingresos (trabajo con monto)', formatCents(week.incomeCents)),
          DataLine('Gastos', formatCents(week.expenseCents)),
          DataLine('Excedente', formatCents(week.surplusCents), emphasis: true),
          DataLine('Tasa de ahorro', rate == null ? 'sin dato' : '${formatDecimal(rate * 100, decimals: 1)} %'),
          DataLine('Valor real de tu hora (mes)', perHour == null ? 'sin dato' : '${formatCents(perHour)}/h'),
          const SizedBox(height: 8),
          BigButton(label: 'Registrar gasto', icon: Icons.add, onPressed: () => ExpenseSheet.show(context)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- pauses

class _PausesPanel extends ConsumerWidget {
  const _PausesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pauses = ref.watch(pausesProvider).value ?? const <PurchasePauseRow>[];
    if (pauses.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final repo = ref.read(financeRepositoryProvider);
    return TerminalPanel(
      label: 'Compras en espera',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in pauses) ...[
            DataLine(p.category, formatCents(p.amountCents), emphasis: true),
            () {
              final until = DateTime.parse(p.untilTs);
              final done = !now.isBefore(until);
              return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(
                  done
                      ? 'La espera terminó: ¿la sigues queriendo?'
                      : 'Espera hasta ${formatClock(until.hour * 60 + until.minute)} del ${isoDate(until)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (done)
                  OutlinedButton(onPressed: () => repo.resolvePause(p, bought: true), child: const Text('LA COMPRÉ')),
                OutlinedButton(onPressed: () => repo.resolvePause(p, bought: false), child: const Text('YA NO')),
              ]);
            }(),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- goals

class _GoalsPanel extends ConsumerWidget {
  const _GoalsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(goalRowsProvider).value ?? const <GoalRow>[];
    final goals = ref.watch(goalsProvider);
    final settings = ref.watch(financeSettingsProvider);
    final flows = weeklyFlows(
      income: MoneyIn.fromWork(ref.watch(workEntriesProvider)),
      expenses: ref.watch(expensesProvider),
      today: ref.watch(todayProvider),
    );
    final surplus = averageSurplusCents(flows);
    final visible = [
      for (final r in rows)
        if (r.status == GoalStatus.activo.code || r.status == GoalStatus.pausado.code) r,
    ];
    final closed = [
      for (final r in rows)
        if (r.status == GoalStatus.completado.code) r,
    ];
    final roots = [
      for (final r in visible)
        if (r.parentId == null || !visible.any((p) => p.id == r.parentId)) r,
    ];

    List<Widget> tree(GoalRow r, int depth) => [
          _GoalTile(
            row: r,
            goal: goals.firstWhere((g) => g.id == r.id),
            goals: goals,
            surplus: surplus,
            depth: depth,
            isEmergency: settings.emergencyGoalId == r.id,
          ),
          for (final c in visible)
            if (c.parentId == r.id) ...tree(c, depth + 1),
        ];

    return TerminalPanel(
      label: 'Metas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visible.isEmpty) const Note('Sin metas todavía. Tú creas, ordenas, pausas o completas cada una.'),
          for (final r in roots) ...tree(r, 0),
          const SizedBox(height: 8),
          BigButton(label: 'Nueva meta', icon: Icons.flag_outlined, outlined: true, onPressed: () => _editGoal(context, ref)),
          if (closed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('COMPLETADAS', style: Theme.of(context).textTheme.titleSmall),
            for (final r in closed)
              DataLine(
                r.title,
                'estimado ${r.targetCents == null ? 'sin dato' : formatCents(r.targetCents!)} · '
                'real ${r.actualCents == null ? 'sin dato' : formatCents(r.actualCents!)}',
              ),
          ],
        ],
      ),
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const _GoalTile({
    required this.row,
    required this.goal,
    required this.goals,
    required this.surplus,
    required this.depth,
    required this.isEmergency,
  });

  final GoalRow row;
  final Goal goal;
  final List<Goal> goals;
  final int surplus;
  final int depth;
  final bool isEmergency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = goalProgress(goal, goals);
    final eta = goal.status == GoalStatus.activo ? goalEtaWeeks(goal, goals, surplus) : null;
    final hasChildren = goals.any((g) => g.parentId == goal.id && g.status != GoalStatus.descartado);
    final progress = p.targetCents == null || p.targetCents == 0 ? null : p.savedCents / p.targetCents!;
    final repo = ref.read(financeRepositoryProvider);
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * depth, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${goal.title}${isEmergency ? ' · RESERVA' : ''}${goal.status == GoalStatus.pausado ? ' · PAUSADA' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              onSelected: (action) async {
                switch (action) {
                  case 'abonar':
                    final cents = await _askCents(context, 'Abonar a «${goal.title}»', 'Monto (puede ser negativo para corregir)');
                    if (cents != null) await repo.addSaved(goal.id, cents);
                  case 'editar':
                    if (context.mounted) await _editGoal(context, ref, existing: row);
                  case 'sub':
                    if (context.mounted) await _editGoal(context, ref, parentId: goal.id);
                  case 'subir':
                    await repo.move(goal.id, up: true);
                  case 'bajar':
                    await repo.move(goal.id, up: false);
                  case 'pausar':
                    await repo.setStatus(goal.id, GoalStatus.pausado);
                  case 'reanudar':
                    await repo.setStatus(goal.id, GoalStatus.activo);
                  case 'completar':
                    if (!context.mounted) return;
                    final actual = await _askCents(context, 'Completar «${goal.title}»', 'Costo real (vacío: sin dato)',
                        allowEmpty: true);
                    if (actual == _cancelled) return;
                    await repo.complete(goal.id, actualCents: actual);
                  case 'descartar':
                    if (!context.mounted) return;
                    if (await confirm(context, title: 'Descartar meta', message: '«${goal.title}» deja de contar.', accept: 'DESCARTAR')) {
                      await repo.setStatus(goal.id, GoalStatus.descartado);
                    }
                  case 'reserva':
                    await ref.read(settingsRepositoryProvider).set(FinanceKey.emergencyGoalId, '${goal.id}');
                  case 'no_reserva':
                    await ref.read(settingsRepositoryProvider).remove(FinanceKey.emergencyGoalId);
                }
              },
              itemBuilder: (_) => [
                if (!hasChildren) const PopupMenuItem(value: 'abonar', child: Text('Abonar')),
                const PopupMenuItem(value: 'editar', child: Text('Editar')),
                const PopupMenuItem(value: 'sub', child: Text('Añadir sub-meta')),
                const PopupMenuItem(value: 'subir', child: Text('Subir')),
                const PopupMenuItem(value: 'bajar', child: Text('Bajar')),
                if (goal.status == GoalStatus.activo)
                  const PopupMenuItem(value: 'pausar', child: Text('Pausar'))
                else
                  const PopupMenuItem(value: 'reanudar', child: Text('Reanudar')),
                const PopupMenuItem(value: 'completar', child: Text('Completar')),
                const PopupMenuItem(value: 'descartar', child: Text('Descartar')),
                if (isEmergency)
                  const PopupMenuItem(value: 'no_reserva', child: Text('Ya no es el fondo de emergencia'))
                else
                  const PopupMenuItem(value: 'reserva', child: Text('Es mi fondo de emergencia')),
              ],
            ),
          ]),
          DataLine(
            'Guardado',
            '${formatCents(p.savedCents)} de ${p.targetCents == null ? 'sin dato' : formatCents(p.targetCents!)}',
          ),
          if (progress != null) LinearProgressIndicator(value: progress.clamp(0, 1).toDouble()),
          if (goal.status == GoalStatus.activo)
            DataLine(
              'Tiempo estimado',
              eta == null ? 'sin dato (sin costo o sin excedente)' : (eta == 0 ? 'lista' : '$eta semanas'),
            ),
        ],
      ),
    );
  }
}

/// Marks a cancelled amount dialog (distinct from an empty "sin dato").
const _cancelled = -1 << 40;

Future<int?> _askCents(BuildContext context, String title, String label, {bool allowEmpty = false}) async {
  final controller = TextEditingController();
  final result = await showDialog<int?>(
    context: context,
    // A tap outside must not read as "sin dato".
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title.toUpperCase()),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: label, suffixText: 'USD'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(_cancelled), child: const Text('CANCELAR')),
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty && allowEmpty) {
              Navigator.of(context).pop(null);
              return;
            }
            final cents = parseCents(text);
            if (cents != null) Navigator.of(context).pop(cents);
          },
          child: const Text('ACEPTAR'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (!allowEmpty && result == _cancelled) return null;
  return result;
}

Future<void> _editGoal(BuildContext context, WidgetRef ref, {GoalRow? existing, int? parentId}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final target = TextEditingController(
    text: existing?.targetCents == null ? '' : formatCents(existing!.targetCents!, withCurrency: false),
  );
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? (parentId == null ? 'NUEVA META' : 'NUEVA SUB-META') : 'EDITAR META'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 8),
        TextField(
          controller: target,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _money,
          decoration: const InputDecoration(labelText: 'Costo estimado (vacío: sin dato)', suffixText: 'USD'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCELAR')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('GUARDAR')),
      ],
    ),
  );
  final name = title.text.trim();
  final targetText = target.text.trim();
  title.dispose();
  target.dispose();
  if (saved != true || name.isEmpty) return;
  final cents = targetText.isEmpty ? null : parseCents(targetText);
  if (targetText.isNotEmpty && (cents == null || cents < 0)) {
    if (context.mounted) toast(context, 'Revisa el costo: usa números como 120,50.');
    return;
  }
  final repo = ref.read(financeRepositoryProvider);
  if (existing == null) {
    await repo.addGoal(title: name, targetCents: cents, parentId: parentId);
  } else {
    await repo.updateGoal(existing.id, title: name, targetCents: Value(cents));
  }
}

// -------------------------------------------------------------- expenses

class _ExpensesPanel extends ConsumerWidget {
  const _ExpensesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(expenseRowsProvider).value ?? const <ExpenseRow>[];
    final monday = isoDate(weekStart(ref.watch(todayProvider)));
    final week = [for (final r in rows) if (r.date.compareTo(monday) >= 0) r];
    final repo = ref.read(financeRepositoryProvider);
    return TerminalPanel(
      label: 'Gastos de la semana',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (week.isEmpty) const Note('Sin gastos registrados esta semana.'),
          for (final r in week)
            Row(children: [
              Expanded(
                child: DataLine(
                  '${r.date.substring(5)} · ${r.category}${r.planned ? ' · plan' : ''}${r.impulse ? ' · impulso' : ''}',
                  formatCents(r.amountCents),
                ),
              ),
              IconButton(
                tooltip: 'Borrar gasto',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, title: 'Borrar gasto', message: '${r.category}: ${formatCents(r.amountCents)}.', accept: 'BORRAR')) {
                    await repo.deleteExpense(r.id);
                  }
                },
              ),
            ]),
        ],
      ),
    );
  }
}

/// Logs one expense. An unplanned purchase at or above the user's
/// threshold suggests waiting; the user can always log it anyway.
class ExpenseSheet extends ConsumerStatefulWidget {
  const ExpenseSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const ExpenseSheet(),
      );

  @override
  ConsumerState<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<ExpenseSheet> {
  final _amount = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  bool _planned = false;
  bool _impulse = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final cents = parseCents(_amount.text);
    final category = _category.text.trim();
    if (cents == null || cents <= 0) {
      toast(context, 'Escribe el monto, por ejemplo 3,50.');
      return;
    }
    if (category.isEmpty) {
      toast(context, 'Elige o escribe una categoría.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(financeRepositoryProvider);
    final now = ref.read(clockProvider)();
    final settings = ref.read(settingsRepositoryProvider);
    final threshold = int.tryParse(await settings.get(FinanceKey.pauseThresholdCents) ?? '');
    final until = purchasePauseUntil(
      amountCents: cents,
      planned: _planned,
      thresholdCents: threshold,
      now: now,
      pauseHours: ref.read(currentAssumptionsProvider).integer(A.purchasePauseH),
    );
    await repo.ensureCategory(category);
    if (until != null && mounted) {
      final advice = pauseAdvice(
        amountCents: cents,
        until: until,
        centsPerHour: ref.read(workSummaryProvider).month.centsPerHour,
      );
      final wait = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿ESPERAR ANTES DE COMPRAR?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(advice.textEs),
            for (final (label, value) in advice.numbers) DataLine(label, value),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('REGISTRAR IGUAL')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ESPERAR')),
          ],
        ),
      );
      if (wait == true) {
        await repo.addPause(category: category, amountCents: cents, until: until, note: _note.text);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (wait == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    await repo.addExpense(
      date: now,
      category: category,
      amountCents: cents,
      planned: _planned,
      impulse: _impulse,
      note: _note.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final c in ref.watch(categoriesProvider).value ?? const <ExpenseCategoryRow>[])
        if (c.status == 'activo') c,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('REGISTRAR GASTO', style: Theme.of(context).textTheme.titleLarge),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _money,
              decoration: const InputDecoration(labelText: 'Monto', suffixText: 'USD'),
            ),
            const SizedBox(height: 8),
            TextField(controller: _category, decoration: const InputDecoration(labelText: 'Categoría (tuya)')),
            if (categories.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final c in categories)
                  ActionChip(label: Text(c.label), onPressed: () => setState(() => _category.text = c.label)),
              ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PLANIFICADO'),
              subtitle: const Text('Gasto básico previsto (cuenta para el fondo de emergencia).'),
              value: _planned,
              onChanged: (v) => setState(() => _planned = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('IMPULSIVO'),
              subtitle: const Text('Solo para que tú lo veas en el mes; sin juicio.'),
              value: _impulse,
              onChanged: (v) => setState(() => _impulse = v),
            ),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 12),
            BigButton(label: _saving ? 'Guardando…' : 'Guardar gasto', icon: Icons.check, onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- settings

class _FinanceSettingsPanel extends ConsumerWidget {
  const _FinanceSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(financeSettingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final hours = ref.watch(currentAssumptionsProvider).integer(A.purchasePauseH);
    return TerminalPanel(
      label: 'Tus reglas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Esperar $hours h desde', s.pauseThresholdCents == null ? 'apagado' : formatCents(s.pauseThresholdCents!)),
          OutlinedButton(
            onPressed: () async {
              final cents = await _askCents(context, 'Umbral de espera', 'Compras no planificadas desde (vacío: apagado)',
                  allowEmpty: true);
              if (cents == _cancelled) return;
              if (cents == null || cents <= 0) {
                await repo.remove(FinanceKey.pauseThresholdCents);
              } else {
                await repo.set(FinanceKey.pauseThresholdCents, '$cents');
              }
            },
            child: const Text('CAMBIAR UMBRAL'),
          ),
          const SizedBox(height: 8),
          DataLine('Separar de cada ingreso', s.splitPercent == null ? 'apagado' : '${s.splitPercent} %'),
          Wrap(spacing: 8, children: [
            for (final pct in const [5, 10, 15, 20])
              ChoiceChip(
                label: Text('$pct %'),
                selected: s.splitPercent == pct,
                onSelected: (_) => repo.set(FinanceKey.splitPercent, '$pct'),
              ),
            ChoiceChip(
              label: const Text('APAGADO'),
              selected: s.splitPercent == null,
              onSelected: (_) => repo.remove(FinanceKey.splitPercent),
            ),
          ]),
          const Note('Los consejos usan solo tus metas activas. La cantidad de consejos por día y las semanas '
              'del fondo de emergencia se cambian en SUPUESTOS → FINANZAS.'),
        ],
      ),
    );
  }
}

/// Rule 7: after an income, offer to set the user's share aside for the
/// first active goal. Nothing moves without the tap.
Future<void> offerIncomeSplit(BuildContext context, WidgetRef ref, int incomeCents) async {
  final settings = ref.read(settingsRepositoryProvider);
  final percent = int.tryParse(await settings.get(FinanceKey.splitPercent) ?? '');
  if (percent == null) return;
  final repo = ref.read(financeRepositoryProvider);
  final goals = [for (final r in await repo.watchGoals().first) goalFromRow(r)];
  final advice = splitIncomeAdvice(incomeCents: incomeCents, percent: percent, goals: goals);
  if (advice == null || !context.mounted) return;
  final ok = await confirm(context, title: 'Separar para tu meta', message: advice.textEs, accept: 'SEPARAR');
  if (ok) await repo.addSaved(advice.goalId!, advice.cents!);
}
