import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../contexto/domain/context_model.dart';
import '../../trabajo/domain/work_model.dart';
import '../data/finance_repository.dart';

/// Finance settings (all user data; no default threshold or percentage).
abstract final class FinanceKey {
  /// Unplanned purchases at or above this wait (cents). Absent: no wait.
  static const pauseThresholdCents = 'finance_pause_threshold_cents';

  /// % of an income offered to the first goal. Absent: no offer.
  static const splitPercent = 'finance_split_percent';

  /// The goal the user marked as the emergency fund.
  static const emergencyGoalId = 'finance_emergency_goal_id';

  /// Rule codes the user asked not to show again (comma separated).
  static const dismissedRules = 'finance_dismissed_rules';

  /// `YYYY-MM-DD:code,code`: the advice already chosen for that day.
  static const adviceDay = 'finance_advice_day';
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final expenseRowsProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final from = isoDate(addDays(ref.watch(todayProvider), -62));
  return ref.watch(financeRepositoryProvider).watchExpensesSince(from);
});

final expensesProvider = Provider<List<Expense>>(
  (ref) => [for (final r in ref.watch(expenseRowsProvider).value ?? const <ExpenseRow>[]) expenseFromRow(r)],
);

final categoriesProvider = StreamProvider<List<ExpenseCategoryRow>>(
  (ref) => ref.watch(financeRepositoryProvider).watchCategories(),
);

final goalRowsProvider = StreamProvider<List<GoalRow>>((ref) => ref.watch(financeRepositoryProvider).watchGoals());

final goalsProvider = Provider<List<Goal>>(
  (ref) => [for (final r in ref.watch(goalRowsProvider).value ?? const <GoalRow>[]) goalFromRow(r)],
);

final pausesProvider = StreamProvider<List<PurchasePauseRow>>(
  (ref) => ref.watch(financeRepositoryProvider).watchPauses(),
);

/// Typed view of the finance settings.
class FinanceSettings {
  const FinanceSettings({
    this.pauseThresholdCents,
    this.splitPercent,
    this.emergencyGoalId,
    this.dismissed = const {},
    this.adviceDay,
    this.adviceRules = const [],
  });

  factory FinanceSettings.fromMap(Map<String, String> map) {
    final day = map[FinanceKey.adviceDay];
    final parts = day?.split(':');
    return FinanceSettings(
      pauseThresholdCents: int.tryParse(map[FinanceKey.pauseThresholdCents] ?? ''),
      splitPercent: int.tryParse(map[FinanceKey.splitPercent] ?? ''),
      emergencyGoalId: int.tryParse(map[FinanceKey.emergencyGoalId] ?? ''),
      dismissed: {
        for (final code in (map[FinanceKey.dismissedRules] ?? '').split(','))
          if (AdviceRule.parse(code) case final rule?) rule,
      },
      adviceDay: parts == null || parts.length != 2 ? null : parts[0],
      adviceRules: parts == null || parts.length != 2
          ? const []
          : [
              for (final code in parts[1].split(','))
                if (AdviceRule.parse(code) case final rule?) rule,
            ],
    );
  }

  final int? pauseThresholdCents;
  final int? splitPercent;
  final int? emergencyGoalId;
  final Set<AdviceRule> dismissed;
  final String? adviceDay;
  final List<AdviceRule> adviceRules;
}

final financeSettingsProvider = Provider<FinanceSettings>(
  (ref) => FinanceSettings.fromMap(ref.watch(settingsMapProvider).value ?? const {}),
);

/// Every rule that applies today, from the user's own data.
final adviceCandidatesProvider = Provider<List<Advice>>((ref) {
  final today = ref.watch(todayProvider);
  final settings = ref.watch(financeSettingsProvider);
  return adviceCandidates(
    income: MoneyIn.fromWork(ref.watch(workEntriesProvider)),
    expenses: ref.watch(expensesProvider),
    goals: ref.watch(goalsProvider),
    monthTotals: ref.watch(workSummaryProvider).month,
    today: today,
    emergencyWeeks: ref.watch(currentAssumptionsProvider).integer(A.emergencyFundWeeks),
    emergencyGoalId: settings.emergencyGoalId,
  );
});

/// Today's advice: the pieces chosen the first time today (kept so a
/// dismissal never pulls a new one in), or a fresh choice ([fresh] true,
/// to be stored). Empty in CHAMBA and ENTRENO.
final todaysAdviceProvider = Provider<({List<Advice> advice, bool fresh})>((ref) {
  final settings = ref.watch(financeSettingsProvider);
  final candidates = ref.watch(adviceCandidatesProvider);
  final mode = ref.watch(modeDecisionProvider).mode;
  final today = isoDate(ref.watch(todayProvider));
  if (settings.adviceDay == today) {
    final kept = mode.silences
        ? const <Advice>[]
        : [
            for (final a in candidates)
              if (settings.adviceRules.contains(a.rule) && !settings.dismissed.contains(a.rule)) a,
          ];
    return (advice: kept, fresh: false);
  }
  final chosen = dailyAdvice(
    candidates,
    dismissed: settings.dismissed,
    mode: mode,
    maxPerDay: ref.watch(currentAssumptionsProvider).integer(A.maxAdvicePerDay),
  );
  return (advice: chosen, fresh: chosen.isNotEmpty);
});
