import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/notification_policy.dart';
import 'package:humanos_core/src/work.dart';
import 'package:test/test.dart';

void main() {
  final params = PolicyParams.fromAssumptions(Assumptions.defaults());
  const plan = WorkSchedule(
    label: 'Trabajo',
    startMin: 8 * 60,
    endMin: 16 * 60 + 30,
    breakStartMin: 12 * 60,
    breakMinutes: 30,
    daysMask: 0x1F, // Monday–Friday
  );
  final friday = DateTime(2026, 10, 30);
  final windows = plannedWindows(friday, [plan]);
  DateTime at(int h, int m) => DateTime(2026, 10, 30, h, m);

  PolicyDecision check(
    NotificationKind kind,
    DateTime when, [
    List<WorkWindow>? w,
  ]) => evaluateNotification(
    kind: kind,
    at: when,
    windows: w ?? windows,
    params: params,
  );

  test('zero notifications inside work except in the break', () {
    for (final kind in NotificationKind.values) {
      for (var minute = 8 * 60; minute < 16 * 60 + 30; minute += 5) {
        final when = at(minute ~/ 60, minute % 60);
        final inBreak = minute >= 12 * 60 && minute < 12 * 60 + 30;
        expect(
          check(kind, when).allowed,
          inBreak,
          reason: '${kind.code} $when',
        );
      }
    }
  });

  test('days without planned work have no silence', () {
    final saturday = plannedWindows(DateTime(2026, 10, 31), [plan]);
    expect(saturday, isEmpty);
    expect(
      check(
        NotificationKind.meal,
        DateTime(2026, 10, 31, 10),
        saturday,
      ).allowed,
      isTrue,
    );
  });

  test('an entry in progress silences like a planned window', () {
    final started = buildWorkEntry(
      date: DateTime(2026, 10, 31),
      label: 'Extra',
      kind: WorkKind.eventual,
      startMin: 15 * 60,
    ).entry!;
    final w = [inProgressWindow(started, openHours: 12)!];
    expect(
      check(NotificationKind.session, DateTime(2026, 10, 31, 20), w).allowed,
      isFalse,
    );
    expect(
      check(NotificationKind.session, DateTime(2026, 11, 1, 3, 30), w).allowed,
      isTrue,
    );
  });

  test('meal and day-close reminders respect quiet hours', () {
    expect(check(NotificationKind.meal, at(21, 30)).allowed, isFalse);
    expect(check(NotificationKind.dayClose, at(5, 30)).allowed, isFalse);
    expect(check(NotificationKind.dayClose, at(20, 30)).allowed, isTrue);
    expect(check(NotificationKind.foodSafety, at(2, 0)).allowed, isTrue);
  });

  test('food safety inside work moves to the break or the end', () {
    final morning = check(NotificationKind.foodSafety, at(9, 10));
    expect(morning.allowed, isFalse);
    expect(morning.deferTo, at(12, 0));
    expect(check(NotificationKind.foodSafety, at(14, 0)).deferTo, at(16, 30));
  });

  test('overlapping windows defer past both', () {
    final a = WorkWindow(start: at(8, 0), end: at(12, 0), label: 'A');
    final b = WorkWindow(start: at(11, 0), end: at(15, 0), label: 'B');
    expect(nextOutsideSilence(at(9, 0), [a, b]), at(15, 0));
  });

  test('in chamba or entreno each reminder follows its context rule', () {
    expect(contextRuleFor(NotificationKind.hydration), ContextRule.allow);
    expect(contextRuleFor(NotificationKind.foodSafety), ContextRule.allow);
    expect(contextRuleFor(NotificationKind.meal), ContextRule.drop);
    expect(
      contextRuleFor(NotificationKind.meal, inPlannedBreak: true),
      ContextRule.allow,
    );
    expect(contextRuleFor(NotificationKind.session), ContextRule.defer);
    expect(contextRuleFor(NotificationKind.dayClose), ContextRule.defer);
    expect(inPlannedBreak(at(12, 10), windows), isTrue);
    expect(inPlannedBreak(at(12, 30), windows), isFalse);
    expect(inPlannedBreak(at(10, 0), windows), isFalse);
  });

  test('circular ranges', () {
    expect(inCircularRange(30, 1380, 60), isTrue);
    expect(inCircularRange(90, 1380, 60), isFalse);
    expect(inCircularRange(10, 10, 10), isFalse);
  });
}
