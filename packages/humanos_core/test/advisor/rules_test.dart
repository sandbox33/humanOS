import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented amounts only.
final today = DateTime(2026, 10, 28, 19); // Wednesday evening.

Expense spend(
  DateTime d,
  int cents, {
  String category = 'Comida',
  bool planned = false,
  bool impulse = false,
}) => Expense(
  date: d,
  category: category,
  amountCents: cents,
  planned: planned,
  impulse: impulse,
);

WeekFlow week(int income, int expenses, {int planned = 0}) => WeekFlow(
  start: DateTime(2026, 10, 26),
  incomeCents: income,
  expenseCents: expenses,
  plannedCents: planned,
);

void main() {
  group('rule 1 · savings rate', () {
    test('shows the rate, its numbers and the trend', () {
      final a = savingsRateAdvice([week(10000, 9000), week(10000, 7500)])!;
      expect(a.rule, AdviceRule.tasaAhorro);
      expect(a.textEs, contains('25,0 %'));
      expect(a.textEs, contains('sube'));
      expect(a.numbers, contains(('Ingresos de la semana', '100,00 USD')));
    });

    test('no advice in a week without income', () {
      expect(savingsRateAdvice([week(10000, 9000), week(0, 2000)]), isNull);
      expect(savingsRateAdvice(const []), isNull);
    });
  });

  group('rule 2 · goal ETA', () {
    final goals = [
      const Goal(id: 1, title: 'Herramienta', priority: 0, targetCents: 12000),
    ];

    test('ETA from the average surplus', () {
      final a = goalEtaAdvice(
        goals: goals,
        flows: [week(10000, 7000), week(10000, 7000)],
        expenses: const [],
        today: today,
      )!;
      expect(a.textEs, contains('unas 4 semanas'));
      expect(a.goalId, 1);
    });

    test(
      'negative surplus: no ETA, the three largest expenses of the week instead',
      () {
        final expenses = [
          spend(DateTime(2026, 10, 26), 500, category: 'Pasaje'),
          spend(DateTime(2026, 10, 27), 4000, category: 'Celular'),
          spend(DateTime(2026, 10, 27), 1500, category: 'Comida'),
          spend(DateTime(2026, 10, 28), 2000, category: 'Ropa'),
          spend(DateTime(2026, 10, 20), 9000, category: 'Semana pasada'),
        ];
        final a = goalEtaAdvice(
          goals: goals,
          flows: [week(5000, 8000)],
          expenses: expenses,
          today: today,
        )!;
        expect(a.textEs, contains('no quedó excedente'));
        expect(a.textEs, isNot(contains('semanas.')));
        expect(a.numbers.skip(2).map((n) => n.$1), [
          'Celular',
          'Ropa',
          'Comida',
        ]);
      },
    );

    test('goals without a target or already reached give no ETA advice', () {
      expect(
        goalEtaAdvice(
          goals: const [Goal(id: 1, title: 'Sin costo', priority: 0)],
          flows: [week(1, 0)],
          expenses: const [],
          today: today,
        ),
        isNull,
      );
      expect(
        goalEtaAdvice(
          goals: const [
            Goal(
              id: 1,
              title: 'Lista',
              priority: 0,
              targetCents: 100,
              savedCents: 100,
            ),
          ],
          flows: [week(1, 0)],
          expenses: const [],
          today: today,
        ),
        isNull,
      );
    });
  });

  group('rule 3 · emergency fund', () {
    test('suggests N weeks of planned spending when no fund is marked', () {
      final a = emergencyFundAdvice(
        goals: const [],
        flows: [week(0, 0, planned: 3000), week(0, 0, planned: 5000)],
        weeks: 12,
      )!;
      expect(a.numbers, contains(('Fondo sugerido', '480,00 USD')));
    });

    test(
      'suggests moving the fund first only while it is incomplete and not first',
      () {
        final goals = [
          const Goal(id: 1, title: 'Viaje', priority: 0, targetCents: 1000),
          const Goal(id: 2, title: 'Reserva', priority: 1, targetCents: 5000),
        ];
        final flows = [week(0, 0, planned: 1000)];
        expect(
          emergencyFundAdvice(
            goals: goals,
            flows: flows,
            weeks: 4,
            emergencyGoalId: 2,
          )!.goalId,
          2,
        );
        final reordered = [
          goals[0],
          const Goal(id: 2, title: 'Reserva', priority: -1, targetCents: 5000),
        ];
        expect(
          emergencyFundAdvice(
            goals: reordered,
            flows: flows,
            weeks: 4,
            emergencyGoalId: 2,
          ),
          isNull,
        );
        expect(
          emergencyFundAdvice(goals: goals, flows: [week(0, 0)], weeks: 4),
          isNull,
          reason: 'no planned spending yet',
        );
      },
    );
  });

  group('rule 4 · hour value', () {
    test('the largest expense of the week in hours of work', () {
      const totals = WorkTotals(
        entries: 1,
        minutes: 480,
        earnedCents: 4000,
        unknownEarnings: 0,
        paidMinutes: 480,
      );
      final a = hourValueAdvice(
        totals: totals,
        expenses: [spend(DateTime(2026, 10, 27), 1500, category: 'Zapatos')],
        today: today,
      )!;
      expect(a.textEs, contains('3 h'));
      expect(a.numbers.first, ('Ingreso real por hora', '5,00 USD/h'));
    });

    test('without paid hours there is no hour value', () {
      const totals = WorkTotals(
        entries: 1,
        minutes: 480,
        earnedCents: 0,
        unknownEarnings: 1,
        paidMinutes: 0,
      );
      expect(
        hourValueAdvice(
          totals: totals,
          expenses: [spend(today, 100)],
          today: today,
        ),
        isNull,
      );
    });
  });

  group('rule 5 · 24 h pause', () {
    test('only unplanned purchases at or above the user threshold wait', () {
      DateTime? until(
        int cents, {
        bool planned = false,
        int? threshold = 2000,
      }) => purchasePauseUntil(
        amountCents: cents,
        planned: planned,
        thresholdCents: threshold,
        now: today,
        pauseHours: 24,
      );
      expect(until(2000), DateTime(2026, 10, 29, 19));
      expect(until(1999), isNull);
      expect(until(5000, planned: true), isNull);
      expect(
        until(5000, threshold: null),
        isNull,
        reason: 'no threshold set: rule off',
      );
      final a = pauseAdvice(
        amountCents: 2500,
        until: DateTime(2026, 10, 29, 19),
        centsPerHour: 500,
      );
      expect(a.textEs, contains('19:00'));
      expect(a.numbers, contains(('Horas de trabajo', '5 h')));
    });
  });

  group('rule 6 · impulsive spending of the month', () {
    test('sums only this month impulsive expenses against the first goal', () {
      final expenses = [
        spend(DateTime(2026, 10, 3), 1000, impulse: true),
        spend(DateTime(2026, 10, 20), 1500, impulse: true),
        spend(DateTime(2026, 10, 21), 9000),
        spend(DateTime(2026, 9, 30), 7000, impulse: true),
      ];
      final goals = [
        const Goal(id: 1, title: 'Meta', priority: 0, targetCents: 10000),
      ];
      final a = impulseMonthAdvice(
        expenses: expenses,
        goals: goals,
        today: today,
      )!;
      expect(a.numbers.first, ('Impulsivo del mes', '25,00 USD'));
      expect(a.textEs, contains('25,0 %'));
      expect(
        impulseMonthAdvice(
          expenses: expenses.sublist(2, 3),
          goals: goals,
          today: today,
        ),
        isNull,
      );
    });
  });

  group('rule 7 · set part of an income aside', () {
    test(
      'offers the configured share for the first goal, capped at what it needs',
      () {
        final goals = [
          const Goal(
            id: 4,
            title: 'Meta',
            priority: 0,
            targetCents: 1000,
            savedCents: 900,
          ),
        ];
        final a = splitIncomeAdvice(
          incomeCents: 5000,
          percent: 10,
          goals: goals,
        )!;
        expect(a.cents, 100, reason: 'capped at the 1,00 USD still missing');
        expect(a.goalId, 4);
        expect(
          splitIncomeAdvice(incomeCents: 5000, percent: null, goals: goals),
          isNull,
        );
        expect(
          splitIncomeAdvice(incomeCents: 5000, percent: 10, goals: const []),
          isNull,
        );
      },
    );
  });

  group('presentation', () {
    final candidates = [
      const Advice(rule: AdviceRule.tasaAhorro, textEs: 'a', numbers: []),
      const Advice(rule: AdviceRule.etaMeta, textEs: 'b', numbers: []),
      const Advice(rule: AdviceRule.valorHora, textEs: 'c', numbers: []),
    ];

    test('at most the daily limit, dismissed rules never return', () {
      expect(
        dailyAdvice(
          candidates,
          dismissed: {},
          mode: ContextMode.descanso,
          maxPerDay: 2,
        ).map((a) => a.textEs),
        ['a', 'b'],
      );
      expect(
        dailyAdvice(
          candidates,
          dismissed: {AdviceRule.tasaAhorro},
          mode: ContextMode.descanso,
          maxPerDay: 2,
        ).map((a) => a.textEs),
        ['b', 'c'],
      );
      expect(
        dailyAdvice(
          candidates,
          dismissed: {},
          mode: ContextMode.otro,
          maxPerDay: 2,
          shownToday: 2,
        ),
        isEmpty,
      );
    });

    test('silenced at work and while training', () {
      for (final mode in [ContextMode.chamba, ContextMode.entreno]) {
        expect(
          dailyAdvice(candidates, dismissed: {}, mode: mode, maxPerDay: 2),
          isEmpty,
        );
      }
    });

    test('every rule round-trips its code and the disclaimer is fixed', () {
      for (final r in AdviceRule.values) {
        expect(AdviceRule.parse(r.code), r);
      }
      expect(AdviceRule.parse('otra'), isNull);
      expect(
        advisorDisclaimerEs,
        'Información general, no es asesoría financiera personalizada.',
      );
    });

    test('candidates come in a fixed order from the user data', () {
      final list = adviceCandidates(
        income: [MoneyIn(date: DateTime(2026, 10, 27), cents: 10000)],
        expenses: [
          spend(DateTime(2026, 10, 27), 2000, planned: true),
          spend(DateTime(2026, 10, 27), 500, impulse: true),
        ],
        goals: const [
          Goal(id: 1, title: 'Meta', priority: 0, targetCents: 50000),
        ],
        monthTotals: const WorkTotals(
          entries: 1,
          minutes: 600,
          earnedCents: 10000,
          unknownEarnings: 0,
          paidMinutes: 600,
        ),
        today: today,
        emergencyWeeks: 12,
      );
      expect(list.map((a) => a.rule), [
        AdviceRule.tasaAhorro,
        AdviceRule.etaMeta,
        AdviceRule.fondoEmergencia,
        AdviceRule.valorHora,
        AdviceRule.impulsoMes,
      ]);
    });
  });
}
