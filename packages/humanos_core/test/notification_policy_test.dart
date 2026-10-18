import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/notification_policy.dart';
import 'package:humanos_core/src/schedule.dart';
import 'package:test/test.dart';

void main() {
  final params = PolicyParams.fromAssumptions(Assumptions.defaults());
  final window = ShiftWindow.from(
    ShiftConfig.fromClock(
      shiftStart: '07:00',
      shiftEnd: '17:00',
      lunchStart: '12:00',
    ),
    lunchDurationMin: 60,
  );
  DateTime at(int h, int m) => DateTime(2026, 10, 19, h, m);

  PolicyDecision check(
    NotificationKind kind,
    DateTime when, {
    bool workday = true,
    int tips = 0,
    int stress = 0,
    bool taller = false,
  }) => evaluateNotification(
    kind: kind,
    at: when,
    window: window,
    workday: workday,
    params: params,
    tipsToday: tips,
    stressPromptsToday: stress,
    insideTaller: taller,
  );

  test('zero notifications between shift start and end except at lunch', () {
    for (final kind in NotificationKind.values) {
      if (kind == NotificationKind.inboxAck) continue;
      for (var minute = 7 * 60; minute < 17 * 60; minute += 5) {
        final when = at(minute ~/ 60, minute % 60);
        final lunch = minute >= 12 * 60 && minute < 13 * 60;
        final d = check(kind, when);
        if (!lunch) {
          expect(d.allowed, isFalse, reason: '${kind.code} $when');
        }
      }
    }
  });

  test('hydration at 06:30 and 12:00 is allowed', () {
    expect(check(NotificationKind.hydration, at(6, 30)).allowed, isTrue);
    expect(check(NotificationKind.hydration, at(12, 0)).allowed, isTrue);
    expect(check(NotificationKind.hydration, at(13, 0)).allowed, isFalse);
  });

  test('off days have no shift blackout', () {
    expect(
      check(NotificationKind.meal, at(10, 0), workday: false).allowed,
      isTrue,
    );
  });

  test('tips: max per day and never in quiet hours', () {
    expect(check(NotificationKind.tip, at(18, 0)).allowed, isTrue);
    expect(check(NotificationKind.tip, at(18, 0), tips: 3).allowed, isFalse);
    expect(check(NotificationKind.tip, at(22, 0)).allowed, isFalse);
    expect(check(NotificationKind.tip, at(5, 30)).allowed, isFalse);
  });

  test('stress context: once a day, not in the taller, not at night', () {
    expect(check(NotificationKind.stressContext, at(19, 0)).allowed, isTrue);
    expect(
      check(NotificationKind.stressContext, at(19, 0), stress: 1).allowed,
      isFalse,
    );
    expect(
      check(NotificationKind.stressContext, at(19, 0), taller: true).allowed,
      isFalse,
    );
    expect(check(NotificationKind.stressContext, at(23, 0)).allowed, isFalse);
  });

  test('food safety in the shift moves to lunch or the shift end', () {
    final morning = check(NotificationKind.foodSafety, at(9, 10));
    expect(morning.allowed, isFalse);
    expect(morning.deferTo, at(12, 0));
    final afternoon = check(NotificationKind.foodSafety, at(14, 0));
    expect(afternoon.deferTo, at(17, 0));
    expect(check(NotificationKind.foodSafety, at(2, 0)).allowed, isTrue);
  });

  test('the "recibido" update is always silent', () {
    final d = check(NotificationKind.inboxAck, at(9, 0));
    expect(d.allowed, isTrue);
    expect(d.silent, isTrue);
  });

  test('night shifts wrap around midnight', () {
    final night = ShiftWindow.from(
      ShiftConfig.fromClock(
        shiftStart: '22:00',
        shiftEnd: '06:00',
        lunchStart: '02:00',
      ),
      lunchDurationMin: 30,
    );
    bool blocked(int h, int m) =>
        inShiftBlackout(at(h, m), window: night, workday: true);
    expect(blocked(23, 0), isTrue);
    expect(blocked(1, 59), isTrue);
    expect(blocked(2, 15), isFalse);
    expect(blocked(5, 59), isTrue);
    expect(blocked(6, 0), isFalse);
    expect(blocked(21, 59), isFalse);
  });

  test('tip slots respect the policy on workdays and off days', () {
    final work = tipSlots(
      day: at(0, 0),
      workday: true,
      window: window,
      params: params,
    );
    expect(work, [12 * 60 + 20, 18 * 60, 19 * 60 + 30]);
    final off = tipSlots(
      day: at(0, 0),
      workday: false,
      window: window,
      params: params,
    );
    expect(off, hasLength(3));
    for (final m in off) {
      expect(m, inInclusiveRange(8 * 60, 20 * 60));
    }
    expect(
      tipSlots(
        day: at(0, 0),
        workday: true,
        window: window,
        params: params,
        count: 1,
      ),
      [12 * 60 + 20],
    );
  });

  test('circular ranges', () {
    expect(inCircularRange(30, 1380, 60), isTrue);
    expect(inCircularRange(90, 1380, 60), isFalse);
    expect(inCircularRange(10, 10, 10), isFalse);
  });
}
