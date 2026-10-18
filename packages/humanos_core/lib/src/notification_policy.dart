/// Notification policy. Every notification the app schedules or posts goes
/// through [evaluateNotification]:
///
/// * zero notifications between shift start and end on a workday, except
///   inside the lunch break (the welder cannot touch the phone while
///   welding);
/// * tips at most `tips_max_per_day` per day, never in quiet hours;
/// * the stress-context question at most once a day, never in quiet hours
///   and never while the phone is inside the taller geofence;
/// * food-safety alerts that fall inside the shift are moved to the lunch
///   break or to the end of the shift.
library;

import 'assumptions.dart';
import 'day.dart';
import 'schedule.dart';

enum NotificationKind {
  hydration('hydration'),
  postShift('post_shift'),
  meal('meal'),
  tip('tip'),
  stressContext('stress_context'),
  foodSafety('food_safety'),
  session('session'),

  /// The silent "recibido" update after the user replies to a
  /// notification: a reaction to the user's own action.
  inboxAck('inbox_ack');

  const NotificationKind(this.code);
  final String code;
}

/// Shift and lunch window in minutes since midnight (wrapping allowed).
class ShiftWindow {
  const ShiftWindow({
    required this.shiftStartMin,
    required this.shiftEndMin,
    required this.lunchStartMin,
    required this.lunchEndMin,
  });

  factory ShiftWindow.from(
    ShiftConfig shift, {
    required int lunchDurationMin,
  }) => ShiftWindow(
    shiftStartMin: shift.shiftStartMin,
    shiftEndMin: shift.shiftEndMin,
    lunchStartMin: shift.lunchStartMin,
    lunchEndMin: shift.lunchStartMin + lunchDurationMin,
  );

  final int shiftStartMin;
  final int shiftEndMin;
  final int lunchStartMin;
  final int lunchEndMin;
}

class PolicyParams {
  const PolicyParams({
    required this.tipsMaxPerDay,
    required this.quietFromMin,
    required this.quietToMin,
  });

  factory PolicyParams.fromAssumptions(Assumptions a) => PolicyParams(
    tipsMaxPerDay: a.integer(A.tipsMaxPerDay),
    quietFromMin: (a[A.quietFromH] * 60).round(),
    quietToMin: (a[A.quietToH] * 60).round(),
  );

  final int tipsMaxPerDay;
  final int quietFromMin;
  final int quietToMin;
}

/// Whether [minute] lies in the half-open circular interval [from, to).
bool inCircularRange(int minute, int from, int to) {
  final m = _wrap(minute), f = _wrap(from), t = _wrap(to);
  if (f == t) return false;
  return f < t ? (m >= f && m < t) : (m >= f || m < t);
}

int _wrap(int minute) => ((minute % 1440) + 1440) % 1440;

int _minuteOf(DateTime at) => at.hour * 60 + at.minute;

/// True when [at] is inside the shift on a workday and outside lunch.
bool inShiftBlackout(
  DateTime at, {
  required ShiftWindow window,
  required bool workday,
}) {
  if (!workday) return false;
  final m = _minuteOf(at);
  final inShift = inCircularRange(m, window.shiftStartMin, window.shiftEndMin);
  final inLunch = inCircularRange(m, window.lunchStartMin, window.lunchEndMin);
  return inShift && !inLunch;
}

bool inQuietHours(DateTime at, PolicyParams params) =>
    inCircularRange(_minuteOf(at), params.quietFromMin, params.quietToMin);

class PolicyDecision {
  const PolicyDecision._({
    required this.allowed,
    required this.reasonEs,
    this.deferTo,
    this.silent = false,
  });

  final bool allowed;

  /// When not allowed now but allowed later today (food safety).
  final DateTime? deferTo;

  /// Post without sound or vibration.
  final bool silent;
  final String reasonEs;
}

/// Decides whether a notification of [kind] may be posted at [at] (local
/// wall-clock time). Counters are what was already posted today.
PolicyDecision evaluateNotification({
  required NotificationKind kind,
  required DateTime at,
  required ShiftWindow window,
  required bool workday,
  required PolicyParams params,
  int tipsToday = 0,
  int stressPromptsToday = 0,
  bool insideTaller = false,
}) {
  final blackout = inShiftBlackout(at, window: window, workday: workday);
  final quiet = inQuietHours(at, params);

  if (kind == NotificationKind.inboxAck) {
    return const PolicyDecision._(
      allowed: true,
      silent: true,
      reasonEs: 'Respuesta a tu propio mensaje: se actualiza sin sonido.',
    );
  }
  if (blackout) {
    if (kind == NotificationKind.foodSafety) {
      return PolicyDecision._(
        allowed: false,
        deferTo: _nextOutsideBlackout(at, window),
        reasonEs: 'Estás en el turno: el aviso pasa al almuerzo o a la salida.',
      );
    }
    return const PolicyDecision._(
      allowed: false,
      reasonEs: 'Durante el turno no hay avisos, salvo en el almuerzo.',
    );
  }
  switch (kind) {
    case NotificationKind.tip:
      if (quiet) {
        return const PolicyDecision._(
          allowed: false,
          reasonEs: 'Horario de silencio.',
        );
      }
      if (tipsToday >= params.tipsMaxPerDay) {
        return PolicyDecision._(
          allowed: false,
          reasonEs:
              'Ya llegaron ${params.tipsMaxPerDay} consejos hoy (el máximo).',
        );
      }
    case NotificationKind.stressContext:
      if (quiet) {
        return const PolicyDecision._(
          allowed: false,
          reasonEs: 'Horario de silencio.',
        );
      }
      if (stressPromptsToday >= 1) {
        return const PolicyDecision._(
          allowed: false,
          reasonEs: 'Ya se preguntó el contexto una vez hoy.',
        );
      }
      if (insideTaller) {
        return const PolicyDecision._(
          allowed: false,
          reasonEs: 'Estás en el taller: no se pregunta.',
        );
      }
    case NotificationKind.meal:
    case NotificationKind.postShift:
      if (quiet) {
        return const PolicyDecision._(
          allowed: false,
          reasonEs: 'Horario de silencio.',
        );
      }
    case NotificationKind.hydration:
    case NotificationKind.foodSafety:
    case NotificationKind.session:
    case NotificationKind.inboxAck:
      break;
  }
  return const PolicyDecision._(allowed: true, reasonEs: 'Permitido.');
}

/// First minute at or after [at] that is outside the blackout: the lunch
/// start if it comes first, otherwise the shift end.
DateTime _nextOutsideBlackout(DateTime at, ShiftWindow window) {
  final now = _minuteOf(at);
  int distance(int target) => _wrap(target - now);
  final toLunch = distance(window.lunchStartMin);
  final toEnd = distance(window.shiftEndMin);
  final minutes = toLunch < toEnd ? toLunch : toEnd;
  final base = DateTime(at.year, at.month, at.day, at.hour, at.minute);
  return base.add(Duration(minutes: minutes));
}

/// Minutes of the day for up to [count] tips: on workdays at lunch and
/// after the shift, on off days spread through the waking day. Every slot
/// passes [evaluateNotification].
List<int> tipSlots({
  required DateTime day,
  required bool workday,
  required ShiftWindow window,
  required PolicyParams params,
  int? count,
}) {
  final wanted = count ?? params.tipsMaxPerDay;
  if (wanted <= 0) return const [];
  final candidates = <int>[];
  if (workday) {
    candidates
      ..add(window.lunchStartMin + 20)
      ..add(window.shiftEndMin + 60)
      ..add(window.shiftEndMin + 150);
  } else {
    final start = params.quietToMin + 120;
    final end = params.quietFromMin - 60;
    final span = end - start;
    for (var i = 0; i < 3; i++) {
      candidates.add(start + (span * i / 2).round());
    }
  }
  final result = <int>[];
  final base = dateOnly(day);
  for (final minute in candidates) {
    if (result.length >= wanted) break;
    final at = DateTime(
      base.year,
      base.month,
      base.day,
    ).add(Duration(minutes: _wrap(minute)));
    final decision = evaluateNotification(
      kind: NotificationKind.tip,
      at: at,
      window: window,
      workday: workday,
      params: params,
      tipsToday: result.length,
    );
    if (decision.allowed) result.add(_wrap(minute));
  }
  return result;
}
