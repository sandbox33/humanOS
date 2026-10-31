import 'package:humanos_core/src/day.dart';
import 'package:humanos_core/src/work.dart';
import 'package:test/test.dart';

void main() {
  final day = DateTime(2026, 10, 30);

  test('a shift crossing midnight counts its real minutes', () {
    final span = spanFromClock(day, parseClock('22:00'), parseClock('06:00'));
    expect(span.minutes, 480);
    expect(span.end.day, 31);
    final same = spanFromClock(day, parseClock('08:00'), parseClock('08:00'));
    expect(same.minutes, 24 * 60, reason: 'equal clocks mean a full day');
  });

  test('rate × minutes in cents, rounded half away from zero', () {
    expect(earnedFor(240, 325), 1300); // 4 h at 3,25/h
    expect(earnedFor(90, 325), 488); // 487,5 → 488
    expect(earnedFor(1, 100), 2); // 1,67 → 2
    expect(earnedFor(0, 325), 0);
    expect(() => earnedFor(-1, 325), throwsArgumentError);
  });

  test('entry with start and end across midnight and a rate', () {
    final r = buildWorkEntry(
      date: day,
      label: 'Turno de noche',
      kind: WorkKind.eventual,
      startMin: parseClock('20:30'),
      endMin: parseClock('00:30'),
      rateCentsPerHour: 325,
    );
    expect(r.issues, isEmpty);
    final e = r.entry!;
    expect(e.minutes, 240);
    expect(e.earnedCents, 1300);
    expect(e.date, dateOnly(day));
    expect(e.end!.day, 31);
  });

  test('entry without a rate keeps the total and no rate', () {
    final r = buildWorkEntry(
      date: day,
      label: 'Arreglo',
      kind: WorkKind.eventual,
      minutes: 150,
      rateCentsPerHour: 500,
      totalCents: 2000,
    );
    expect(r.entry!.earnedCents, 2000);
    expect(r.entry!.rateCentsPerHour, isNull);
    expect(r.entry!.effectiveRateCentsPerHour, 800);
  });

  test('entry with only a total and no hours is valid', () {
    final r = buildWorkEntry(
      date: day,
      label: 'Trabajo suelto',
      kind: WorkKind.eventual,
      totalCents: 1500,
    );
    expect(r.issues, isEmpty);
    expect(r.entry!.minutes, 0);
    expect(r.entry!.effectiveRateCentsPerHour, isNull);
  });

  test('a rate without hours is refused, not turned into zero', () {
    final r = buildWorkEntry(
      date: day,
      label: 'Trabajo',
      kind: WorkKind.estable,
      rateCentsPerHour: 325,
    );
    expect(r.entry, isNull);
    expect(r.issues, [WorkIssue.rateWithoutHours]);
    final noTime = buildWorkEntry(
      date: day,
      label: 'Trabajo',
      kind: WorkKind.estable,
    );
    expect(noTime.issues, [WorkIssue.noTime]);
  });

  test('hours only: minutes known, earnings unknown', () {
    final r = buildWorkEntry(
      date: day,
      label: 'Trabajo',
      kind: WorkKind.estable,
      minutes: 480,
    );
    expect(r.entry!.earnedCents, isNull);
  });

  test('invalid input is reported', () {
    final r = buildWorkEntry(
      date: day,
      label: '  ',
      kind: WorkKind.estable,
      minutes: -5,
    );
    expect(r.issues, containsAll([WorkIssue.noLabel, WorkIssue.negative]));
    expect(WorkIssue.noLabel.messageEs, isNotEmpty);
  });

  test('start now, finish later', () {
    final started = buildWorkEntry(
      date: day,
      label: 'Trabajo',
      kind: WorkKind.estable,
      startMin: parseClock('23:15'),
      rateCentsPerHour: 400,
    ).entry!;
    expect(started.inProgress, isTrue);
    final done = finishWork(started, DateTime(2026, 10, 31, 1, 45));
    expect(done.inProgress, isFalse);
    expect(done.minutes, 150);
    expect(done.earnedCents, 1000);
    expect(
      finishWork(done, DateTime(2026, 10, 31, 9)).minutes,
      150,
      reason: 'already closed',
    );
  });

  test('minutes split by calendar day for charts', () {
    final e = buildWorkEntry(
      date: day,
      label: 'Noche',
      kind: WorkKind.eventual,
      startMin: parseClock('22:00'),
      endMin: parseClock('02:00'),
    ).entry!;
    final split = minutesByCalendarDay(e);
    expect(split[dateOnly(day)], 120);
    expect(split[dateOnly(DateTime(2026, 10, 31))], 120);
  });

  group('totals', () {
    WorkEntry e(DateTime d, int minutes, {int? earned}) => WorkEntry(
      date: d,
      label: 'x',
      kind: WorkKind.estable,
      minutes: minutes,
      earnedCents: earned,
    );

    test('day, ISO week and month with unknown earnings counted apart', () {
      final entries = [
        e(DateTime(2026, 10, 30), 300, earned: 1500), // Friday
        e(DateTime(2026, 10, 30), 120), // unknown money
        e(DateTime(2026, 10, 26), 480, earned: 2400), // Monday same week
        e(DateTime(2026, 10, 25), 60, earned: 300), // previous Sunday
        e(DateTime(2026, 9, 30), 600, earned: 9999), // previous month
      ];
      final s = workSummary(
        entries,
        today: DateTime(2026, 10, 30),
        dailyOvertimeMin: 360,
      );
      expect(s.day.minutes, 420);
      expect(s.day.earnedCents, 1500);
      expect(s.day.unknownEarnings, 1);
      expect(s.day.overtimeMinutes, 60);
      expect(s.day.centsPerHour, 300);
      expect(s.week.minutes, 900);
      expect(s.week.earnedCents, 3900);
      expect(s.week.overtimeMinutes, isNull, reason: 'no weekly threshold set');
      expect(s.month.minutes, 960);
      expect(s.month.entries, 4);
    });

    test('weeks with no work have no hourly value', () {
      final s = sumWork(const []);
      expect(s.minutes, 0);
      expect(s.centsPerHour, isNull);
    });

    test('week start is Monday', () {
      expect(weekStart(DateTime(2026, 11, 1)), DateTime.utc(2026, 10, 26));
      expect(weekStart(DateTime(2026, 10, 26)), DateTime.utc(2026, 10, 26));
    });
  });

  test('formatting', () {
    expect(formatWorkMinutes(450), '7 h 30 min');
    expect(formatWorkMinutes(45), '45 min');
    expect(formatWorkMinutes(120), '2 h');
    expect(hoursOfWorkEs(1300, 325), '4 h');
    expect(hoursOfWorkEs(1000, 0), 'sin dato');
    expect(WorkKind.parse('estable'), WorkKind.estable);
    expect(WorkKind.parse(null), WorkKind.eventual);
  });

  group('schedules and windows', () {
    const night = WorkSchedule(
      label: 'Noche',
      startMin: 22 * 60,
      endMin: 6 * 60,
      breakStartMin: 2 * 60,
      breakMinutes: 30,
      daysMask: 1 << 4, // Friday
      heatExposure: true,
    );
    const day = WorkSchedule(
      label: 'Día',
      startMin: 7 * 60,
      endMin: 17 * 60,
      breakStartMin: 12 * 60,
      breakMinutes: 60,
      daysMask: 0x3F, // Monday–Saturday
    );

    test('days mask round-trip', () {
      expect(daysMaskOf([1, 2, 3, 4, 5, 6]), 0x3F);
      expect(weekdaysOf(0x3F), [1, 2, 3, 4, 5, 6]);
      expect(weekdaysOf(null), isEmpty);
      expect(day.plannedOn(DateTime(2026, 11, 1)), isFalse, reason: 'Sunday');
      expect(day.plannedOn(DateTime(2026, 10, 31)), isTrue, reason: 'Saturday');
      expect(day.plannedMinutes(DateTime(2026, 10, 31)), 540);
      expect(night.plannedMinutes(DateTime(2026, 10, 30)), 450);
    });

    test('a night window planned on Friday also covers Saturday morning', () {
      final friday = plannedWindows(DateTime(2026, 10, 30), [night, day]);
      expect(friday.map((w) => w.label), ['Día', 'Noche']);
      final saturday = plannedWindows(DateTime(2026, 10, 31), [night, day]);
      expect(saturday.map((w) => w.label), ['Noche', 'Día']);
      final w = saturday.first;
      expect(w.silences(DateTime(2026, 10, 31, 1)), isTrue);
      expect(
        w.silences(DateTime(2026, 10, 31, 2, 10)),
        isFalse,
        reason: 'break',
      );
      expect(w.silences(DateTime(2026, 10, 31, 6)), isFalse, reason: 'ended');
    });

    test('break window and silence', () {
      final w = plannedWindows(DateTime(2026, 10, 29), [day]).single;
      expect(w.silences(DateTime(2026, 10, 29, 9)), isTrue);
      expect(w.inBreak(DateTime(2026, 10, 29, 12, 30)), isTrue);
      expect(w.silences(DateTime(2026, 10, 29, 12, 30)), isFalse);
      expect(w.silences(DateTime(2026, 10, 29, 6, 59)), isFalse);
    });

    test(
      'an entry in progress silences until its template end or the open window',
      () {
        final started = buildWorkEntry(
          date: DateTime(2026, 10, 29),
          label: 'Día',
          kind: WorkKind.estable,
          startMin: 7 * 60 + 5,
        ).entry!;
        final withTemplate = inProgressWindow(
          started,
          openHours: 12,
          schedule: day,
        )!;
        expect(withTemplate.end, DateTime(2026, 10, 29, 17));
        final open = inProgressWindow(started, openHours: 12)!;
        expect(open.end, DateTime(2026, 10, 29, 19, 5));
        expect(
          inProgressWindow(
            finishWork(started, DateTime(2026, 10, 29, 9)),
            openHours: 12,
          ),
          isNull,
        );
      },
    );
  });
}
