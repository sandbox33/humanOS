/// Finance advisor rules (Fase 5): small, explained advice from the user's
/// own work and expenses. No LLM decides or writes advice; every text is a
/// template filled with the numbers it shows. No trading, no investment
/// advice, no external rates.
library;

import '../context_mode.dart';
import '../day.dart';
import '../format_es.dart';
import '../money.dart';
import '../work.dart';
import 'finance.dart';

/// Shown on the finance screen at all times.
const advisorDisclaimerEs =
    'Información general, no es asesoría financiera personalizada.';

enum AdviceRule {
  tasaAhorro('tasa_ahorro', 'Tasa de ahorro semanal'),
  etaMeta('eta_meta', 'Tiempo hasta la meta'),
  fondoEmergencia('fondo_emergencia', 'Fondo de emergencia'),
  valorHora('valor_hora', 'Valor de tu hora'),
  pausa24h('pausa_24h', 'Espera de 24 h'),
  impulsoMes('impulso_mes', 'Gasto impulsivo del mes'),
  separarIngreso('separar_ingreso', 'Separar parte del ingreso');

  const AdviceRule(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static AdviceRule? parse(String? code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// One piece of advice: the rule that made it, the sentence and the
/// numbers it used (label, value), so the user can check it.
class Advice {
  const Advice({
    required this.rule,
    required this.textEs,
    required this.numbers,
    this.goalId,
    this.cents,
  });

  final AdviceRule rule;
  final String textEs;
  final List<(String, String)> numbers;

  /// The goal an action applies to (separar ingreso), if any.
  final int? goalId;

  /// The amount an action applies to (separar ingreso), if any.
  final int? cents;
}

String _pct(double fraction) =>
    '${formatDecimal(fraction * 100, decimals: 1)} %';

/// Rule 1: weekly savings rate with its 4-week trend.
Advice? savingsRateAdvice(List<WeekFlow> flows) {
  if (flows.isEmpty) return null;
  final week = flows.last;
  final rate = week.savingsRate;
  if (rate == null) return null;
  final trend = savingsTrend(flows);
  return Advice(
    rule: AdviceRule.tasaAhorro,
    textEs: trend == null
        ? 'Esta semana guardaste el ${_pct(rate)} de lo que ganaste.'
        : 'Esta semana guardaste el ${_pct(rate)} de lo que ganaste; frente a las semanas anteriores, ${trend.labelEs}.',
    numbers: [
      ('Ingresos de la semana', formatCents(week.incomeCents)),
      ('Gastos de la semana', formatCents(week.expenseCents)),
      ('Tasa', _pct(rate)),
      ('Tendencia (${flows.length} semanas)', trend?.labelEs ?? 'sin dato'),
    ],
  );
}

/// The three largest expenses of the week of [today], largest first (ties:
/// the earlier one first).
List<Expense> topExpensesOfWeek(
  List<Expense> expenses,
  DateTime today, {
  int count = 3,
}) {
  final monday = weekStart(today);
  final week = [
    for (final e in expenses)
      if (!dateOnly(e.date).isBefore(monday) &&
          dateOnly(e.date).isBefore(addDays(monday, 7)))
        e,
  ];
  week.sort((a, b) {
    final byAmount = b.amountCents.compareTo(a.amountCents);
    return byAmount != 0 ? byAmount : a.date.compareTo(b.date);
  });
  return week.take(count).toList();
}

/// Rule 2: ETA of the first active goal with a target, at the average
/// surplus of the last weeks. Without surplus there is no ETA: the week's
/// three largest expenses are shown instead.
Advice? goalEtaAdvice({
  required List<Goal> goals,
  required List<WeekFlow> flows,
  required List<Expense> expenses,
  required DateTime today,
}) {
  final goal = orderedActiveGoals(
    goals,
  ).where((g) => goalRemainingCents(g, goals) != null).firstOrNull;
  if (goal == null) return null;
  final left = goalRemainingCents(goal, goals)!;
  if (left == 0) return null;
  final surplus = averageSurplusCents(flows);
  final eta = goalEtaWeeks(goal, goals, surplus);
  if (eta == null) {
    final top = topExpensesOfWeek(expenses, today);
    return Advice(
      rule: AdviceRule.etaMeta,
      goalId: goal.id,
      textEs: top.isEmpty
          ? 'En las últimas ${flows.length} semanas no quedó excedente para «${goal.title}».'
          : 'En las últimas ${flows.length} semanas no quedó excedente para «${goal.title}». '
                'Tus mayores gastos de esta semana:',
      numbers: [
        ('Falta', formatCents(left)),
        ('Excedente semanal medio', formatCents(surplus)),
        for (final e in top) (e.category, formatCents(e.amountCents)),
      ],
    );
  }
  return Advice(
    rule: AdviceRule.etaMeta,
    goalId: goal.id,
    textEs:
        'Al ritmo de las últimas ${flows.length} semanas, «${goal.title}» se completa en unas $eta semanas.',
    numbers: [
      ('Falta', formatCents(left)),
      ('Excedente semanal medio', formatCents(surplus)),
      ('Semanas', '$eta'),
    ],
  );
}

/// Rule 3: an emergency fund of [weeks] weeks of basic (planned) spending
/// before non-essential goals. A suggestion the user can edit or dismiss.
/// [emergencyGoalId] is the goal the user marked as that fund, if any.
Advice? emergencyFundAdvice({
  required List<Goal> goals,
  required List<WeekFlow> flows,
  required int weeks,
  int? emergencyGoalId,
}) {
  if (flows.isEmpty || weeks <= 0) return null;
  final basic = divRound(
    flows.fold(0, (a, f) => a + f.plannedCents),
    flows.length,
  );
  if (basic <= 0) return null;
  final fund = basic * weeks;
  final ordered = orderedActiveGoals(goals);
  final emergency = emergencyGoalId == null
      ? null
      : goals.where((g) => g.id == emergencyGoalId).firstOrNull;
  final numbers = [
    ('Gasto básico semanal (planificado)', formatCents(basic)),
    ('Semanas de reserva', '$weeks'),
    ('Fondo sugerido', formatCents(fund)),
  ];
  if (emergency == null) {
    return Advice(
      rule: AdviceRule.fondoEmergencia,
      textEs:
          'Una reserva de $weeks semanas de gasto básico (${formatCents(fund)}) da margen ante una semana sin trabajo. '
          'Puedes crearla como meta y ponerla primero.',
      numbers: numbers,
    );
  }
  final left = goalRemainingCents(emergency, goals);
  if (emergency.status != GoalStatus.activo || left == 0) return null;
  if (ordered.isNotEmpty && ordered.first.id == emergency.id) return null;
  return Advice(
    rule: AdviceRule.fondoEmergencia,
    goalId: emergency.id,
    textEs:
        '«${emergency.title}» aún no está completa y hay metas antes que ella. Puedes subirla al primer lugar.',
    numbers: [
      ...numbers,
      ('Falta', left == null ? 'sin dato' : formatCents(left)),
    ],
  );
}

/// Rule 4: real income per hour, and the week's largest expense in hours.
Advice? hourValueAdvice({
  required WorkTotals totals,
  required List<Expense> expenses,
  required DateTime today,
}) {
  final perHour = totals.centsPerHour;
  if (perHour == null || perHour <= 0) return null;
  final top = topExpensesOfWeek(expenses, today, count: 1).firstOrNull;
  if (top == null) return null;
  final hours = hoursOfWorkEs(top.amountCents, perHour);
  return Advice(
    rule: AdviceRule.valorHora,
    textEs:
        'Tu mayor gasto de esta semana (${top.category}, ${formatCents(top.amountCents)}) equivale a $hours de trabajo.',
    numbers: [
      ('Ingreso real por hora', '${formatCents(perHour)}/h'),
      ('Gasto', formatCents(top.amountCents)),
      ('Horas de trabajo', hours),
    ],
  );
}

/// Rule 5: the wait before an unplanned purchase at or above the user's
/// threshold. Null threshold: the rule is off.
DateTime? purchasePauseUntil({
  required int amountCents,
  required bool planned,
  required int? thresholdCents,
  required DateTime now,
  required int pauseHours,
}) {
  if (planned || thresholdCents == null || pauseHours <= 0) return null;
  if (amountCents < thresholdCents) return null;
  return now.add(Duration(hours: pauseHours));
}

/// Rule 5, explained: the purchase in hours of work and the wait.
Advice pauseAdvice({
  required int amountCents,
  required DateTime until,
  int? centsPerHour,
}) => Advice(
  rule: AdviceRule.pausa24h,
  textEs:
      'Compra no planificada: espera hasta ${formatClock(until.hour * 60 + until.minute)} del '
      '${isoDate(until)} y decide entonces. Si la sigues queriendo, regístrala.',
  numbers: [
    ('Monto', formatCents(amountCents)),
    if (centsPerHour != null)
      ('Horas de trabajo', hoursOfWorkEs(amountCents, centsPerHour)),
  ],
);

/// Rule 6: impulsive spending of the month of [today] against what the
/// first active goal with a target still needs.
Advice? impulseMonthAdvice({
  required List<Expense> expenses,
  required List<Goal> goals,
  required DateTime today,
}) {
  final total = expenses
      .where(
        (e) =>
            e.impulse &&
            e.date.year == today.year &&
            e.date.month == today.month,
      )
      .fold(0, (a, e) => a + e.amountCents);
  if (total <= 0) return null;
  final goal = orderedActiveGoals(
    goals,
  ).where((g) => (goalRemainingCents(g, goals) ?? 0) > 0).firstOrNull;
  if (goal == null) {
    return Advice(
      rule: AdviceRule.impulsoMes,
      textEs:
          'Este mes llevas ${formatCents(total)} en gastos que marcaste como impulsivos.',
      numbers: [('Impulsivo del mes', formatCents(total))],
    );
  }
  final left = goalRemainingCents(goal, goals)!;
  final share = total / left;
  return Advice(
    rule: AdviceRule.impulsoMes,
    goalId: goal.id,
    textEs:
        'Este mes llevas ${formatCents(total)} en gastos impulsivos: el ${_pct(share > 1 ? 1 : share)} '
        'de lo que falta para «${goal.title}».',
    numbers: [
      ('Impulsivo del mes', formatCents(total)),
      ('Falta para la meta', formatCents(left)),
    ],
  );
}

/// Rule 7: after an income, offer to set [percent] % aside for the first
/// active goal that still needs money. One tap applies [Advice.cents].
Advice? splitIncomeAdvice({
  required int incomeCents,
  required int? percent,
  required List<Goal> goals,
}) {
  if (percent == null || percent <= 0) return null;
  final goal = orderedActiveGoals(
    goals,
  ).where((g) => goalRemainingCents(g, goals) != 0).firstOrNull;
  if (goal == null) return null;
  var cents = splitCents(incomeCents, percent);
  final left = goalRemainingCents(goal, goals);
  if (left != null && cents > left) cents = left;
  if (cents <= 0) return null;
  return Advice(
    rule: AdviceRule.separarIngreso,
    goalId: goal.id,
    cents: cents,
    textEs:
        '¿Separas ${formatCents(cents)} ($percent %) de este ingreso para «${goal.title}»?',
    numbers: [
      ('Ingreso', formatCents(incomeCents)),
      ('Porcentaje', '$percent %'),
      ('A separar', formatCents(cents)),
    ],
  );
}

/// Every rule that applies today, in a fixed order.
List<Advice> adviceCandidates({
  required List<MoneyIn> income,
  required List<Expense> expenses,
  required List<Goal> goals,
  required WorkTotals monthTotals,
  required DateTime today,
  required int emergencyWeeks,
  int? emergencyGoalId,
  int weeks = 4,
}) {
  final flows = weeklyFlows(
    income: income,
    expenses: expenses,
    today: today,
    weeks: weeks,
  );
  return [
    ?savingsRateAdvice(flows),
    ?goalEtaAdvice(
      goals: goals,
      flows: flows,
      expenses: expenses,
      today: today,
    ),
    ?emergencyFundAdvice(
      goals: goals,
      flows: flows,
      weeks: emergencyWeeks,
      emergencyGoalId: emergencyGoalId,
    ),
    ?hourValueAdvice(totals: monthTotals, expenses: expenses, today: today),
    ?impulseMonthAdvice(expenses: expenses, goals: goals, today: today),
  ];
}

/// At most [maxPerDay] pieces a day, none of a dismissed rule, none while
/// the user is at work or training. [shownToday] counts what was already
/// shown today.
List<Advice> dailyAdvice(
  List<Advice> candidates, {
  required Set<AdviceRule> dismissed,
  required ContextMode mode,
  required int maxPerDay,
  int shownToday = 0,
}) {
  if (mode.silences) return const [];
  final room = maxPerDay - shownToday;
  if (room <= 0) return const [];
  return candidates
      .where((a) => !dismissed.contains(a.rule))
      .take(room)
      .toList();
}
