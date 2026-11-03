/// Notification policy. Every notification the app schedules or posts goes
/// through [evaluateNotification]:
///
/// * zero notifications inside a work window (planned in a template, or an
///   entry in progress), except in its break;
/// * meal and day-close reminders never in quiet hours;
/// * food-safety alerts that fall inside a work window move to its break or
///   to its end.
library;

import 'assumptions.dart';
import 'work.dart';

enum NotificationKind {
  hydration('hydration'),
  meal('meal'),
  session('session'),
  dayClose('day_close'),
  foodSafety('food_safety');

  const NotificationKind(this.code);
  final String code;
}

class PolicyParams {
  const PolicyParams({required this.quietFromMin, required this.quietToMin});

  factory PolicyParams.fromAssumptions(Assumptions a) => PolicyParams(
    quietFromMin: (a[A.quietFromH] * 60).round(),
    quietToMin: (a[A.quietToH] * 60).round(),
  );

  final int quietFromMin;
  final int quietToMin;
}

int _wrap(int minute) => ((minute % 1440) + 1440) % 1440;

/// Whether [minute] lies in the half-open circular interval [from, to).
bool inCircularRange(int minute, int from, int to) {
  final m = _wrap(minute), f = _wrap(from), t = _wrap(to);
  if (f == t) return false;
  return f < t ? (m >= f && m < t) : (m >= f || m < t);
}

bool inQuietHours(DateTime at, PolicyParams params) => inCircularRange(
  at.hour * 60 + at.minute,
  params.quietFromMin,
  params.quietToMin,
);

/// True when [at] is inside a work window and not in its break.
bool inWorkSilence(DateTime at, List<WorkWindow> windows) =>
    windows.any((w) => w.silences(at));

class PolicyDecision {
  const PolicyDecision._({
    required this.allowed,
    required this.reasonEs,
    this.deferTo,
  });

  final bool allowed;

  /// When not allowed now but allowed later (food safety).
  final DateTime? deferTo;
  final String reasonEs;
}

/// Decides whether a notification of [kind] may fire at [at].
PolicyDecision evaluateNotification({
  required NotificationKind kind,
  required DateTime at,
  required List<WorkWindow> windows,
  required PolicyParams params,
}) {
  if (inWorkSilence(at, windows)) {
    if (kind == NotificationKind.foodSafety) {
      return PolicyDecision._(
        allowed: false,
        deferTo: nextOutsideSilence(at, windows),
        reasonEs: 'Estás trabajando: el aviso pasa a la pausa o al final.',
      );
    }
    return const PolicyDecision._(
      allowed: false,
      reasonEs: 'Mientras trabajas no hay avisos, salvo en la pausa.',
    );
  }
  final quietSensitive =
      kind == NotificationKind.meal || kind == NotificationKind.dayClose;
  if (quietSensitive && inQuietHours(at, params)) {
    return const PolicyDecision._(
      allowed: false,
      reasonEs: 'Horario de silencio.',
    );
  }
  return const PolicyDecision._(allowed: true, reasonEs: 'Permitido.');
}

/// First instant at or after [at] outside every silencing window: the next
/// break start or window end, repeated while windows overlap.
DateTime nextOutsideSilence(DateTime at, List<WorkWindow> windows) {
  var t = at;
  for (var guard = 0; guard < 32 && inWorkSilence(t, windows); guard++) {
    DateTime? best;
    for (final w in windows) {
      if (!w.silences(t)) continue;
      final b = w.breakStart;
      final candidate = (b != null && b.isAfter(t) && b.isBefore(w.end))
          ? b
          : w.end;
      if (best == null || candidate.isBefore(best)) best = candidate;
    }
    t = best!;
  }
  return t;
}
