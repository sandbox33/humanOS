import 'package:humanos_core/src/adaptive_tdee.dart';
import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/day.dart';
import 'package:test/test.dart';

void main() {
  final params = TdeeParams.fromAssumptions(Assumptions.defaults());
  final end = DateTime.utc(2026, 10, 12);

  List<DayRecord> days(
    int count, {
    double weight = 70,
    double intake = 3000,
    bool complete = true,
    double slopePerDay = 0,
  }) {
    return [
      for (var i = 0; i < count; i++)
        DayRecord(
          date: addDays(end, -(count - 1 - i)),
          weightKg: weight + slopePerDay * i,
          intakeKcal: intake,
          intakeComplete: complete,
        ),
    ];
  }

  test('flat weight at 3000 kcal gives 3000 ± 1', () {
    final estimate = estimateTdee(days(21), asOf: end, params: params);
    expect(estimate.tdeeKcal, isNotNull);
    expect(estimate.tdeeKcal!, closeTo(3000, 1));
  });

  test('13 valid days gives null (datos insuficientes)', () {
    final records = days(21);
    final trimmed = [
      for (var i = 0; i < records.length; i++)
        i < 8
            ? DayRecord(date: records[i].date, weightKg: records[i].weightKg)
            : records[i],
    ];
    final estimate = estimateTdee(trimmed, asOf: end, params: params);
    expect(estimate.validDays, 13);
    expect(estimate.tdeeKcal, isNull);
    expect(estimate.reasonEs, contains('insuficientes'));
  });

  test('14 valid days is enough', () {
    final records = days(21);
    final trimmed = [
      for (var i = 0; i < records.length; i++)
        i < 7
            ? DayRecord(date: records[i].date, weightKg: records[i].weightKg)
            : records[i],
    ];
    expect(estimateTdee(trimmed, asOf: end, params: params).sufficient, isTrue);
  });

  test('incomplete intake days do not count', () {
    final estimate = estimateTdee(
      days(21, complete: false),
      asOf: end,
      params: params,
    );
    expect(estimate.validDays, 0);
    expect(estimate.tdeeKcal, isNull);
  });

  test('null weights are skipped by the trend', () {
    final trend = weightTrend([
      DayRecord(date: DateTime.utc(2026, 1, 1), weightKg: 70),
      DayRecord(date: DateTime.utc(2026, 1, 2)),
      DayRecord(date: DateTime.utc(2026, 1, 3), weightKg: 71),
    ], 0.1);
    expect(trend.length, 3);
    expect(trend[1].measured, isFalse);
    expect(trend[1].trendKg, 70);
    expect(trend[2].trendKg, closeTo(70.1, 1e-9));
  });

  test('steady gain is subtracted using kcal per kg', () {
    // 60 days of history so the EMA reaches its steady slope.
    final records = days(60, slopePerDay: 0.03);
    final estimate = estimateTdee(records, asOf: end, params: params);
    expect(estimate.slopeKgPerDay!, closeTo(0.03, 0.002));
    expect(estimate.tdeeKcal!, closeTo(3000 - 0.03 * 7700, 20));
  });

  group('weekly target adjustment', () {
    TdeeEstimate fake({required double tdee, required double ratePerWeek}) =>
        TdeeEstimate(
          tdeeKcal: tdee,
          validDays: 21,
          requiredDays: 14,
          slopeKgPerDay: ratePerWeek / 7,
          trendKg: 66,
          meanIntakeKcal: tdee,
          reasonEs: '',
        );

    test('clamps an increase at +150', () {
      final adj = weeklyTargetAdjustment(
        currentTargetKcal: 2500,
        estimate: fake(tdee: 3000, ratePerWeek: 0),
        params: params,
      );
      expect(adj.stepKcal, 150);
      expect(adj.newTargetKcal, 2650);
    });

    test('clamps a decrease at -150', () {
      final adj = weeklyTargetAdjustment(
        currentTargetKcal: 3200,
        estimate: fake(tdee: 2600, ratePerWeek: 0.8),
        params: params,
      );
      expect(adj.stepKcal, -150);
    });

    test('inside the band the target does not move', () {
      final adj = weeklyTargetAdjustment(
        currentTargetKcal: 3200,
        estimate: fake(tdee: 3000, ratePerWeek: 0.2),
        params: params,
      );
      expect(adj.changed, isFalse);
    });

    test('small corrections are not clamped', () {
      final adj = weeklyTargetAdjustment(
        currentTargetKcal: 3200,
        estimate: fake(tdee: 3000, ratePerWeek: 0.1),
        params: params,
      );
      expect(adj.stepKcal, closeTo(3000 + 0.225 * 7700 / 7 - 3200, 1e-6));
    });

    test('never changes without 14 valid days', () {
      final insufficient = estimateTdee(days(10), asOf: end, params: params);
      final adj = weeklyTargetAdjustment(
        currentTargetKcal: 3000,
        estimate: insufficient,
        params: params,
      );
      expect(adj.changed, isFalse);
      expect(adj.reasonEs, contains('no cambia'));
    });
  });

  test('Mifflin bootstrap for the real profile', () {
    final age = ageFromBirthYear(2001, DateTime.utc(2026, 10, 12));
    expect(age, 25);
    final bmr = mifflinBmr(
      weightKg: 65,
      heightCm: 171,
      ageYears: age,
      sex: Sex.male,
    );
    expect(bmr, closeTo(10 * 65 + 6.25 * 171 - 5 * 25 + 5, 1e-9));
    expect(
      bootstrapTargetKcal(bmr: bmr, workday: true, params: params),
      closeTo(bmr * 1.9 + 300, 1e-9),
    );
    expect(
      bootstrapTargetKcal(bmr: bmr, workday: false, params: params),
      closeTo(bmr * 1.6 + 300, 1e-9),
    );
  });

  test('female Mifflin offset', () {
    expect(
      mifflinBmr(weightKg: 60, heightCm: 160, ageYears: 30, sex: Sex.female),
      closeTo(600 + 1000 - 150 - 161, 1e-9),
    );
  });

  group('goals and starting priors', () {
    TdeeEstimate est({required double tdee, required double ratePerWeek}) =>
        TdeeEstimate(
          tdeeKcal: tdee,
          validDays: 21,
          requiredDays: 14,
          slopeKgPerDay: ratePerWeek / 7,
          trendKg: 66,
          meanIntakeKcal: tdee,
          reasonEs: '',
        );
    final bmr = mifflinBmr(
      weightKg: 65,
      heightCm: 171,
      ageYears: 25,
      sex: Sex.male,
    );

    test('ecto gaining starts at Mifflin × 1.9 + 400', () {
      expect(
        bootstrapTargetKcal(
          bmr: bmr,
          workday: true,
          params: params,
          goal: Goal.ganar,
          somatotype: Somatotype.ecto,
        ),
        closeTo(bmr * 1.9 + 400, 1e-9),
      );
    });

    test('somatotype surplus applies only when gaining', () {
      for (final (soma, kcal) in [
        (Somatotype.ecto, 400.0),
        (Somatotype.meso, 300.0),
        (Somatotype.endo, 200.0),
        (Somatotype.noSe, 300.0),
      ]) {
        expect(
          bootstrapGoalKcal(goal: Goal.ganar, somatotype: soma, params: params),
          kcal,
        );
        expect(
          bootstrapGoalKcal(
            goal: Goal.mantener,
            somatotype: soma,
            params: params,
          ),
          0,
        );
      }
      // Losing: middle of −0.5…−0.25 kg/week × 7700 / 7 ≈ −412.5 kcal.
      expect(
        bootstrapGoalKcal(
          goal: Goal.perder,
          somatotype: Somatotype.ecto,
          params: params,
        ),
        closeTo(-0.375 * 7700 / 7, 1e-9),
      );
    });

    test('PAL follows the job type and off days never exceed it', () {
      expect(dayPal(workday: true, job: JobType.heavy, params: params), 1.9);
      expect(dayPal(workday: false, job: JobType.heavy, params: params), 1.6);
      expect(dayPal(workday: true, job: JobType.moderate, params: params), 1.6);
      expect(dayPal(workday: true, job: JobType.desk, params: params), 1.4);
      expect(dayPal(workday: false, job: JobType.desk, params: params), 1.4);
    });

    test('the weekly review aims at the band of the goal', () {
      final keep = weeklyTargetAdjustment(
        currentTargetKcal: 2600,
        estimate: est(tdee: 2600, ratePerWeek: 0.02),
        params: params,
        goal: Goal.mantener,
      );
      expect(keep.changed, isFalse);
      final lose = weeklyTargetAdjustment(
        currentTargetKcal: 2600,
        estimate: est(tdee: 2600, ratePerWeek: 0),
        params: params,
        goal: Goal.perder,
      );
      expect(lose.stepKcal, -150);
      expect(lose.reasonEs, contains('baja'));
    });

    test('profile codes round-trip with safe defaults', () {
      for (final g in Goal.values) {
        expect(Goal.parse(g.code), g);
      }
      for (final s in Somatotype.values) {
        expect(Somatotype.parse(s.code), s);
      }
      for (final j in JobType.values) {
        expect(JobType.parse(j.code), j);
      }
      expect(Goal.parse(null), Goal.ganar);
      expect(Somatotype.parse('x'), Somatotype.noSe);
      expect(JobType.parse(null), JobType.heavy);
    });
  });
}
