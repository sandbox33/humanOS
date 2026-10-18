import 'dart:math' as math;

import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/confidence.dart';
import 'package:humanos_core/src/day.dart';
import 'package:humanos_core/src/readiness.dart';
import 'package:test/test.dart';

void main() {
  final p = ReadinessParams.fromAssumptions(Assumptions.defaults());
  final today = DateTime.utc(2026, 10, 12);
  DateTime d(int back) => addDays(today, -back);

  test('missing data gives VERDE with "sin datos"', () {
    final r = assessReadiness(const [], today: today, params: p);
    expect(r.band, ReadinessBand.verde);
    expect(r.noData, isTrue);
    expect(r.reasonsEs.single, contains('Sin datos'));
  });

  group('HRV path', () {
    List<DailyRecovery> hrv({required double recent, required double base}) {
      final rng = math.Random(7);
      return [
        for (var i = 0; i < 60; i++)
          DailyRecovery(
            date: d(i),
            hrvRmssdMs: (i < 7 ? recent : base) + rng.nextDouble() * 4 - 2,
          ),
      ];
    }

    test('7-day mean below 60-day mean − 0.5 SD flags AMARILLO', () {
      final r = assessReadiness(
        hrv(recent: 40, base: 60),
        today: today,
        params: p,
      );
      expect(r.path, ReadinessPath.hrv);
      expect(r.flags, contains(ReadinessFlag.hrvLow));
      expect(r.band, ReadinessBand.amarillo);
    });

    test('normal HRV stays VERDE and ignores RHR', () {
      final records = hrv(recent: 60, base: 60)
          .map(
            (r) => DailyRecovery(
              date: r.date,
              hrvRmssdMs: r.hrvRmssdMs,
              rhrBpm: r.date == today ? 99 : 50,
            ),
          )
          .toList();
      final r = assessReadiness(records, today: today, params: p);
      expect(r.path, ReadinessPath.hrv);
      expect(r.band, ReadinessBand.verde);
    });
  });

  group('RHR path', () {
    List<DailyRecovery> rhr(double todayValue) => [
      DailyRecovery(date: today, rhrBpm: todayValue),
      for (var i = 1; i <= 28; i++)
        DailyRecovery(date: d(i), rhrBpm: 54 + (i % 3) * 1.0),
    ];

    test('RHR above mean + 1 SD flags AMARILLO', () {
      final r = assessReadiness(rhr(62), today: today, params: p);
      expect(r.path, ReadinessPath.rhr);
      expect(r.flags, [ReadinessFlag.rhrHigh]);
      expect(r.band, ReadinessBand.amarillo);
    });

    test('RHR within baseline stays VERDE', () {
      final r = assessReadiness(rhr(55), today: today, params: p);
      expect(r.band, ReadinessBand.verde);
    });

    test('too few baseline days: RHR not evaluated', () {
      final r = assessReadiness(
        [
          DailyRecovery(date: today, rhrBpm: 90),
          DailyRecovery(date: d(1), rhrBpm: 50),
        ],
        today: today,
        params: p,
      );
      expect(r.flags, isEmpty);
      expect(r.noData, isFalse);
    });
  });

  test('short sleep flags AMARILLO', () {
    final r = assessReadiness(
      [DailyRecovery(date: today, sleepMinutes: 320)],
      today: today,
      params: p,
    );
    expect(r.flags, contains(ReadinessFlag.shortSleep));
    expect(r.band, ReadinessBand.amarillo);
  });

  test('HIGH work effort flags AMARILLO', () {
    final r = assessReadiness(
      [DailyRecovery(date: today, workEffort: WorkEffort.high)],
      today: today,
      params: p,
    );
    expect(r.flags, [ReadinessFlag.highEffort]);
  });

  test(
    'sleep debt over 5 h in 7 nights flags; missing nights are not debt',
    () {
      final records = [
        for (var i = 0; i < 7; i++)
          DailyRecovery(date: d(i), sleepMinutes: i.isEven ? 400.0 : null),
      ];
      // 4 nights with data, each 8 h − 6 h 40 min = 1 h 20 min → 5,33 h debt.
      final r = assessReadiness(records, today: today, params: p);
      expect(r.sleepDebtH!, closeTo(4 * (8 - 400 / 60), 1e-9));
      expect(r.flags, contains(ReadinessFlag.sleepDebt));
    },
  );

  test('two flags make ROJO: suggests postponing, never blocks', () {
    final r = assessReadiness(
      [
        DailyRecovery(
          date: today,
          sleepMinutes: 300,
          workEffort: WorkEffort.high,
        ),
      ],
      today: today,
      params: p,
    );
    expect(r.band, ReadinessBand.rojo);
    expect(r.suggestPostpone, isTrue);
    expect(r.reasonsEs.last, contains('Puedes entrenar igual'));
  });

  test('band codes round-trip', () {
    for (final b in ReadinessBand.values) {
      expect(ReadinessBand.parse(b.code), b);
    }
    expect(WorkEffort.parse('HIGH'), WorkEffort.high);
  });

  group('capability-aware inputs', () {
    const band9 = ReadinessCapabilities(
      hrv: false,
      restingHr: false,
      sleep: true,
    );

    test('Band 9 via Mi Fitness: sleep, feel, effort and performance only', () {
      final r = assessReadiness(
        [
          DailyRecovery(
            date: today,
            sleepMinutes: 420,
            morningFeel: 4,
            workEffort: WorkEffort.medium,
          ),
        ],
        today: today,
        params: p,
        capabilities: band9,
        performanceDrop: false,
      );
      expect(r.band, ReadinessBand.verde);
      expect(r.path, ReadinessPath.none);
      final hrv = r.input(ReadinessInputKind.hrv)!;
      expect(hrv.status, ReadinessInputStatus.unavailable);
      expect(hrv.detailEs, 'VFC: no disponible con tu dispositivo');
      expect(
        r.input(ReadinessInputKind.restingHr)!.status,
        ReadinessInputStatus.unavailable,
      );
      final used = r.inputs
          .where((i) => i.status == ReadinessInputStatus.used)
          .map((i) => i.kind)
          .toSet();
      expect(used, {
        ReadinessInputKind.sleep,
        ReadinessInputKind.sleepDebt,
        ReadinessInputKind.effort,
        ReadinessInputKind.feel,
        ReadinessInputKind.performance,
      });
      expect(r.confidence, Confidence.media);
    });

    test(
      'unknown capability with no data reads as missing, not unavailable',
      () {
        final r = assessReadiness(const [], today: today, params: p);
        expect(
          r.input(ReadinessInputKind.hrv)!.status,
          ReadinessInputStatus.missing,
        );
        expect(r.inputs, hasLength(ReadinessInputKind.values.length));
        expect(r.confidence, Confidence.baja);
      },
    );

    test('morning feel ≤ 2/5 flags AMARILLO', () {
      final r = assessReadiness(
        [DailyRecovery(date: today, morningFeel: 2)],
        today: today,
        params: p,
        capabilities: band9,
      );
      expect(r.flags, [ReadinessFlag.lowFeel]);
      expect(r.band, ReadinessBand.amarillo);
      expect(r.input(ReadinessInputKind.feel)!.flagged, isTrue);
    });

    test('a feel of 3/5 or an out-of-range value does not flag', () {
      for (final feel in [3, 0, 9]) {
        final r = assessReadiness(
          [DailyRecovery(date: today, morningFeel: feel, sleepMinutes: 480)],
          today: today,
          params: p,
        );
        expect(r.flags, isEmpty, reason: 'feel $feel');
      }
    });

    test(
      'reps below the previous session flag AMARILLO; with low feel ROJO',
      () {
        final one = assessReadiness(
          const [],
          today: today,
          params: p,
          performanceDrop: true,
        );
        expect(one.noData, isFalse);
        expect(one.flags, [ReadinessFlag.performanceDrop]);
        expect(one.band, ReadinessBand.amarillo);

        final two = assessReadiness(
          [DailyRecovery(date: today, morningFeel: 1)],
          today: today,
          params: p,
          performanceDrop: true,
        );
        expect(two.band, ReadinessBand.rojo);
        expect(two.suggestPostpone, isTrue);
      },
    );

    test('HRV path with enough inputs reaches alta confidence', () {
      final rng = math.Random(3);
      final r = assessReadiness(
        [
          for (var i = 0; i < 60; i++)
            DailyRecovery(
              date: d(i),
              hrvRmssdMs: 60 + rng.nextDouble() * 4 - 2,
              sleepMinutes: 450,
              morningFeel: i == 0 ? 4 : null,
            ),
        ],
        today: today,
        params: p,
        performanceDrop: false,
      );
      expect(r.path, ReadinessPath.hrv);
      expect(
        r.input(ReadinessInputKind.hrv)!.status,
        ReadinessInputStatus.used,
      );
      expect(r.confidence, Confidence.alta);
    });
  });
}
