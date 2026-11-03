import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../domain/finance_model.dart';
import '../domain/pay_model.dart';

String _perHour(int? cents) => cents == null ? 'sin dato' : '${formatCents(cents)}/h';

/// INGRESOS REALES: what the user was paid, with normal and overtime hours;
/// the real value of an hour comes from it (no fixed rate).
class PayPanel extends ConsumerWidget {
  const PayPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(payRowsProvider).value ?? const <PayWeekRow>[];
    final v = ref.watch(hourValuesProvider);
    final repo = ref.read(payRepositoryProvider);
    return TerminalPanel(
      label: 'Ingresos reales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Hora normal', _perHour(v.normalCentsPerHour), emphasis: true),
          DataLine('Hora extra', _perHour(v.overtimeCentsPerHour), emphasis: true),
          DataLine('Promedio de todas las horas', _perHour(v.averageCentsPerHour)),
          DataLine('Cómo se calculó', v.method.labelEs),
          if (v.method == RateMethod.average)
            const Note('Para separar la hora extra: anota la parte de horas extra del pago, o registra semanas con '
                'distinta cantidad de horas extra.'),
          const SizedBox(height: 8),
          BigButton(label: 'Registrar pago', icon: Icons.payments_outlined, onPressed: () => PaySheet.show(context)),
          for (final r in rows.take(6))
            Row(children: [
              Expanded(
                child: DataLine(
                  r.paidOn,
                  '${formatCents(r.amountCents)} · ${formatWorkMinutes(r.normalMinutes)}'
                  '${r.overtimeMinutes > 0 ? ' + ${formatWorkMinutes(r.overtimeMinutes)} extra' : ''}',
                ),
              ),
              IconButton(
                tooltip: 'Borrar pago',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await confirm(context, title: 'Borrar pago', message: formatCents(r.amountCents), accept: 'BORRAR')) {
                    await repo.deletePay(r.id);
                  }
                },
              ),
            ]),
        ],
      ),
    );
  }
}

/// One week's pay: amount, normal hours, overtime hours and, optionally,
/// the overtime part shown on the pay slip.
class PaySheet extends ConsumerStatefulWidget {
  const PaySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const PaySheet(),
      );

  @override
  ConsumerState<PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends ConsumerState<PaySheet> {
  final _amount = TextEditingController();
  final _normal = TextEditingController();
  final _overtime = TextEditingController();
  final _overtimePay = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _normal.dispose();
    _overtime.dispose();
    _overtimePay.dispose();
    super.dispose();
  }

  int? _minutes(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final h = double.tryParse(t);
    return h == null || h < 0 ? null : (h * 60).round();
  }

  Future<void> _save() async {
    final amount = parseCents(_amount.text);
    final normal = _minutes(_normal);
    final overtime = _minutes(_overtime);
    final otPay = _overtimePay.text.trim().isEmpty ? null : parseCents(_overtimePay.text);
    if (amount == null || amount <= 0 || normal == null || overtime == null || normal + overtime == 0) {
      toast(context, 'Escribe el monto y las horas (por ejemplo 40 y 5,5).');
      return;
    }
    if (otPay != null && (otPay < 0 || otPay > amount)) {
      toast(context, 'La parte de horas extra no puede pasar del monto.');
      return;
    }
    await ref.read(payRepositoryProvider).addPay(
          paidOn: ref.read(clockProvider)(),
          amountCents: amount,
          normalMinutes: normal,
          overtimeMinutes: overtime,
          overtimeCents: otPay,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    const hours = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('REGISTRAR PAGO', style: Theme.of(context).textTheme.titleLarge),
          TextField(
            controller: _amount,
            keyboardType: hours,
            inputFormatters: money,
            decoration: const InputDecoration(labelText: 'Monto cobrado', suffixText: 'USD'),
          ),
          TextField(controller: _normal, keyboardType: hours, decoration: const InputDecoration(labelText: 'Horas normales')),
          TextField(controller: _overtime, keyboardType: hours, decoration: const InputDecoration(labelText: 'Horas extra')),
          TextField(
            controller: _overtimePay,
            keyboardType: hours,
            inputFormatters: money,
            decoration: const InputDecoration(labelText: 'Parte de horas extra (si el pago la muestra)', suffixText: 'USD'),
          ),
          const SizedBox(height: 12),
          BigButton(label: 'Guardar pago', icon: Icons.check, onPressed: _save),
        ]),
      ),
    );
  }
}

/// EFECTIVO: the cash counted, kept up to date with what is logged, and how
/// many days it lasts at the recent pace.
class CashPanel extends ConsumerWidget {
  const CashPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cashViewProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final days = ref.watch(currentAssumptionsProvider).integer(A.spendPaceDays);
    return TerminalPanel(
      label: 'Efectivo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Tienes', c.cashCents == null ? 'sin dato' : formatCents(c.cashCents!), emphasis: true),
          DataLine('Gasto por día (últimos $days días)', c.paceCents == null ? 'sin dato' : formatCents(c.paceCents!)),
          DataLine('A tu ritmo te alcanza', c.days == null ? 'sin dato' : '${c.days} días'),
          DataLine('Próximo ingreso', c.nextIncome == null ? 'sin dato' : isoDate(c.nextIncome!)),
          if (c.reaches == false)
            const Note('A este ritmo el efectivo no llega a tu próximo ingreso.', icon: Icons.info_outline),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton(
              onPressed: () async {
                final cents = await askCents(context, title: 'Efectivo que tienes ahora');
                if (cents != null) await ref.read(payRepositoryProvider).count(cents);
              },
              child: const Text('CONTAR EFECTIVO'),
            ),
            OutlinedButton(
              onPressed: () async {
                final today = ref.read(todayProvider);
                final picked = await showDatePicker(
                  context: context,
                  initialDate: c.nextIncome ?? addDays(today, 7),
                  firstDate: today,
                  lastDate: addDays(today, 366),
                );
                if (picked != null) await settings.set(PayKey.nextIncome, isoDate(picked));
              },
              child: const Text('PRÓXIMO INGRESO'),
            ),
            if (c.nextIncome != null)
              TextButton(onPressed: () => settings.remove(PayKey.nextIncome), child: const Text('RESTABLECER FECHA')),
          ]),
        ],
      ),
    );
  }
}

/// GASTÉ: amount and category, saved by the category tap (two taps after
/// typing). The full form (planned, impulsive, note) stays in FINANZAS.
class QuickExpenseSheet extends ConsumerStatefulWidget {
  const QuickExpenseSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const QuickExpenseSheet(),
      );

  @override
  ConsumerState<QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

class _QuickExpenseSheetState extends ConsumerState<QuickExpenseSheet> {
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(String category) async {
    if (_saving) return;
    final cents = parseCents(_amount.text);
    if (cents == null || cents <= 0) {
      toast(context, 'Escribe el monto, por ejemplo 1,50.');
      return;
    }
    setState(() => _saving = true);
    await ref.read(financeRepositoryProvider).addExpense(
          date: ref.read(clockProvider)(),
          category: category,
          amountCents: cents,
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
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('GASTÉ', style: Theme.of(context).textTheme.titleLarge),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Monto', suffixText: 'USD'),
        ),
        const SizedBox(height: 8),
        if (categories.isEmpty)
          const Note('Crea tus categorías la primera vez en FINANZAS → Registrar gasto.')
        else
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final c in categories) ActionChip(label: Text(c.label), onPressed: () => _save(c.label)),
          ]),
      ]),
    );
  }
}
