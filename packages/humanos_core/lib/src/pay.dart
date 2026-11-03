/// Money from real income (B5): what the user was paid each week, with
/// normal and overtime hours, gives the real value of an hour and of an
/// overtime hour (no fixed rates). Cash on hand and the spending pace give
/// how many days the money lasts. Cents and minutes only.
library;

import 'advisor/finance.dart' show Expense, MoneyIn;
import 'day.dart';
import 'money.dart';

/// One week's pay as the user wrote it down.
class PayWeek {
  const PayWeek({
    required this.paidOn,
    required this.amountCents,
    required this.normalMinutes,
    required this.overtimeMinutes,
    this.overtimeCents,
  });

  /// The day the money came in.
  final DateTime paidOn;
  final int amountCents;
  final int normalMinutes;
  final int overtimeMinutes;

  /// The overtime part of the amount, when the pay slip shows it.
  final int? overtimeCents;

  MoneyIn get asIncome => MoneyIn(date: dateOnly(paidOn), cents: amountCents);
}

enum RateMethod {
  /// The user wrote the overtime part: exact split.
  slip('desglose del pago'),

  /// Estimated from weeks with different mixes of normal and overtime.
  estimated('estimado de tus semanas'),

  /// Only the average of all hours (not enough data to split).
  average('promedio de todas las horas'),

  /// No pay with hours recorded yet.
  none('sin dato');

  const RateMethod(this.labelEs);
  final String labelEs;
}

class HourValues {
  const HourValues({
    required this.method,
    this.averageCentsPerHour,
    this.normalCentsPerHour,
    this.overtimeCentsPerHour,
  });

  final RateMethod method;
  final int? averageCentsPerHour;
  final int? normalCentsPerHour;
  final int? overtimeCentsPerHour;
}

/// The real value of an hour from the last weeks of pay. The latest week
/// with an overtime part gives the exact split; else a least-squares fit
/// of amount = normal hours × a + overtime hours × b over [weeks] when the
/// weeks differ enough in their mix; else the average of all hours.
HourValues hourValues(List<PayWeek> weeks) {
  final usable = [
    for (final w in weeks)
      if (w.normalMinutes + w.overtimeMinutes > 0) w,
  ]..sort((a, b) => b.paidOn.compareTo(a.paidOn));
  if (usable.isEmpty) return const HourValues(method: RateMethod.none);
  final minutes = usable.fold(
    0,
    (s, w) => s + w.normalMinutes + w.overtimeMinutes,
  );
  final cents = usable.fold(0, (s, w) => s + w.amountCents);
  final average = divRound(cents * 60, minutes);

  final slip = usable
      .where(
        (w) =>
            w.overtimeCents != null &&
            w.overtimeMinutes > 0 &&
            w.normalMinutes > 0,
      )
      .firstOrNull;
  if (slip != null) {
    return HourValues(
      method: RateMethod.slip,
      averageCentsPerHour: average,
      normalCentsPerHour: divRound(
        (slip.amountCents - slip.overtimeCents!) * 60,
        slip.normalMinutes,
      ),
      overtimeCentsPerHour: divRound(
        slip.overtimeCents! * 60,
        slip.overtimeMinutes,
      ),
    );
  }

  // Least squares without intercept: [Σn² Σno; Σno Σo²][a b]ᵀ = [Σny Σoy]ᵀ
  // with n, o in hours and y in cents.
  var snn = 0.0, soo = 0.0, sno = 0.0, sny = 0.0, soy = 0.0;
  for (final w in usable) {
    final n = w.normalMinutes / 60,
        o = w.overtimeMinutes / 60,
        y = w.amountCents.toDouble();
    snn += n * n;
    soo += o * o;
    sno += n * o;
    sny += n * y;
    soy += o * y;
  }
  final det = snn * soo - sno * sno;
  // The weeks must not all have the same mix (a singular system has no
  // split; the tolerance only absorbs rounding).
  if (soo > 0 && snn > 0 && det > 1e-9 * snn * soo) {
    final a = (sny * soo - soy * sno) / det;
    final b = (soy * snn - sny * sno) / det;
    if (a > 0 && b > 0) {
      return HourValues(
        method: RateMethod.estimated,
        averageCentsPerHour: average,
        normalCentsPerHour: a.round(),
        overtimeCentsPerHour: b.round(),
      );
    }
  }
  return HourValues(method: RateMethod.average, averageCentsPerHour: average);
}

/// Cash now: the user's last count, minus the expenses logged after it,
/// plus the pay that came in after it ([spent] carries when each expense
/// was logged).
int cashNow({
  required int countedCents,
  required DateTime countedAt,
  required List<({int cents, DateTime loggedAt})> spent,
  required List<PayWeek> pay,
}) {
  var cash = countedCents;
  for (final s in spent) {
    if (s.loggedAt.isAfter(countedAt)) cash -= s.cents;
  }
  for (final p in pay) {
    if (p.paidOn.isAfter(countedAt)) cash += p.amountCents;
  }
  return cash;
}

/// Average spending per day over the [days] days before [today] (today
/// excluded, it is not over); null when nothing was logged in that time.
int? dailySpendPace(
  List<Expense> expenses,
  DateTime today, {
  required int days,
}) {
  final from = addDays(dateOnly(today), -days);
  final spent = expenses
      .where(
        (e) =>
            !dateOnly(e.date).isBefore(from) &&
            dateOnly(e.date).isBefore(dateOnly(today)),
      )
      .fold(0, (s, e) => s + e.amountCents);
  if (spent <= 0) return null;
  return divRound(spent, days);
}

/// Whole days the cash lasts at [paceCents] a day; null without a pace.
int? daysCovered(int cashCents, int? paceCents) {
  if (paceCents == null || paceCents <= 0) return null;
  if (cashCents <= 0) return 0;
  return cashCents ~/ paceCents;
}

/// Whether the cash reaches the next income the user wrote down; null when
/// the pace or the date is not known.
bool? reachesNextIncome({
  required int? daysCovered,
  required DateTime today,
  required DateTime? nextIncome,
}) {
  if (daysCovered == null || nextIncome == null) return null;
  return daysCovered >= daysBetween(today, nextIncome);
}
