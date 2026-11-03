import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show parseStamp, stampOf;
import 'finance_model.dart';

/// B5 settings (user data).
abstract final class PayKey {
  /// `YYYY-MM-DD` of the next income the user expects; absent = unknown.
  static const nextIncome = 'next_income_date';
}

PayWeek payWeekOf(PayWeekRow r) => PayWeek(
      paidOn: parseIsoDate(r.paidOn),
      amountCents: r.amountCents,
      normalMinutes: r.normalMinutes,
      overtimeMinutes: r.overtimeMinutes,
      overtimeCents: r.overtimeCents,
    );

/// Weekly pay and cash counts.
class PayRepository {
  PayRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  Stream<List<PayWeekRow>> watchPay() =>
      (_db.select(_db.payWeeks)..orderBy([(t) => OrderingTerm.desc(t.paidOn), (t) => OrderingTerm.desc(t.id)])).watch();

  Future<int> addPay({
    required DateTime paidOn,
    required int amountCents,
    required int normalMinutes,
    required int overtimeMinutes,
    int? overtimeCents,
  }) =>
      _db.into(_db.payWeeks).insert(PayWeeksCompanion.insert(
            paidOn: isoDate(paidOn),
            amountCents: amountCents,
            normalMinutes: normalMinutes,
            overtimeMinutes: overtimeMinutes,
            overtimeCents: Value(overtimeCents),
            createdAt: stampOf(_now()),
          ));

  Future<void> deletePay(int id) => (_db.delete(_db.payWeeks)..where((t) => t.id.equals(id))).go();

  Stream<CashCountRow?> watchLastCount() => (_db.select(_db.cashCounts)
        ..orderBy([(t) => OrderingTerm.desc(t.countedAt), (t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<int> count(int cents) =>
      _db.into(_db.cashCounts).insert(CashCountsCompanion.insert(countedAt: stampOf(_now()), cents: cents));
}

final payRepositoryProvider = Provider<PayRepository>(
  (ref) => PayRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final payRowsProvider = StreamProvider<List<PayWeekRow>>((ref) => ref.watch(payRepositoryProvider).watchPay());

final payWeeksProvider = Provider<List<PayWeek>>(
  (ref) => [for (final r in ref.watch(payRowsProvider).value ?? const <PayWeekRow>[]) payWeekOf(r)],
);

/// The real value of an hour from the last pays.
final hourValuesProvider = Provider<HourValues>((ref) {
  final n = ref.watch(currentAssumptionsProvider).integer(A.payWeeksForRate);
  return hourValues(ref.watch(payWeeksProvider).take(n).toList());
});

final lastCashCountProvider = StreamProvider<CashCountRow?>((ref) => ref.watch(payRepositoryProvider).watchLastCount());

/// Cash now, how fast it goes and how long it lasts.
class CashView {
  const CashView({this.cashCents, this.countedAt, this.paceCents, this.days, this.nextIncome, this.reaches});

  /// Null until the user counts their cash once.
  final int? cashCents;
  final DateTime? countedAt;
  final int? paceCents;
  final int? days;
  final DateTime? nextIncome;
  final bool? reaches;
}

final cashViewProvider = Provider<CashView>((ref) {
  final today = ref.watch(todayProvider);
  final a = ref.watch(currentAssumptionsProvider);
  final expenses = ref.watch(expensesProvider);
  final rows = ref.watch(expenseRowsProvider).value ?? const <ExpenseRow>[];
  final pace = dailySpendPace(expenses, today, days: a.integer(A.spendPaceDays));
  final next = DateTime.tryParse((ref.watch(settingsMapProvider).value ?? const {})[PayKey.nextIncome] ?? '');
  final count = ref.watch(lastCashCountProvider).value;
  final at = parseStamp(count?.countedAt);
  if (count == null || at == null) return CashView(paceCents: pace, nextIncome: next);
  final cash = cashNow(
    countedCents: count.cents,
    countedAt: at,
    spent: [
      for (final r in rows)
        if (parseStamp(r.createdAt) case final logged?) (cents: r.amountCents, loggedAt: logged),
    ],
    pay: [
      for (final r in ref.watch(payRowsProvider).value ?? const <PayWeekRow>[])
        if (parseStamp(r.createdAt) case final logged?)
          PayWeek(
            paidOn: logged,
            amountCents: r.amountCents,
            normalMinutes: r.normalMinutes,
            overtimeMinutes: r.overtimeMinutes,
          ),
    ],
  );
  final days = daysCovered(cash, pace);
  return CashView(
    cashCents: cash,
    countedAt: at,
    paceCents: pace,
    days: days,
    nextIncome: next,
    reaches: reachesNextIncome(daysCovered: days, today: today, nextIncome: next),
  );
});
