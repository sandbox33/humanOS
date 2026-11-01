import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented amounts only.
final today = DateTime(2026, 10, 28); // Wednesday; week starts 2026-10-26.
final monday = DateTime(2026, 10, 26);

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

void main() {
  group('weekly flows', () {
    test('four ISO weeks, oldest first, income and expenses in their week', () {
      final flows = weeklyFlows(
        income: [
          MoneyIn(date: DateTime(2026, 10, 27), cents: 10000),
          MoneyIn(date: DateTime(2026, 10, 19), cents: 8000),
          MoneyIn(date: DateTime(2026, 9, 1), cents: 99999), // out of range
        ],
        expenses: [
          spend(DateTime(2026, 11, 1), 2500, planned: true),
          spend(DateTime(2026, 10, 25), 1000),
        ],
        today: today,
      );
      expect(flows.map((f) => isoDate(f.start)), [
        '2026-10-05',
        '2026-10-12',
        '2026-10-19',
        '2026-10-26',
      ]);
      expect(flows.last.incomeCents, 10000);
      expect(
        flows.last.expenseCents,
        2500,
        reason: 'Sunday belongs to the same ISO week',
      );
      expect(flows.last.plannedCents, 2500);
      expect(flows[2].incomeCents, 8000);
      expect(flows[2].expenseCents, 1000);
    });

    test(
      'a week with zero income has no savings rate (not 0 %, not infinite)',
      () {
        final empty = WeekFlow(
          start: monday,
          incomeCents: 0,
          expenseCents: 1500,
          plannedCents: 0,
        );
        expect(empty.savingsRate, isNull);
        expect(empty.surplusCents, -1500);
        final good = WeekFlow(
          start: monday,
          incomeCents: 20000,
          expenseCents: 15000,
          plannedCents: 0,
        );
        expect(good.savingsRate, closeTo(0.25, 1e-9));
      },
    );

    test('irregular income: weeks without work are skipped by the trend', () {
      final flows = [
        WeekFlow(
          start: monday,
          incomeCents: 10000,
          expenseCents: 9000,
          plannedCents: 0,
        ), // 10 %
        WeekFlow(
          start: monday,
          incomeCents: 0,
          expenseCents: 3000,
          plannedCents: 0,
        ), // no work
        WeekFlow(
          start: monday,
          incomeCents: 10000,
          expenseCents: 8000,
          plannedCents: 0,
        ), // 20 %
      ];
      expect(savingsTrend(flows), Trend.sube);
      expect(
        savingsTrend(flows.sublist(0, 2)),
        isNull,
        reason: 'only one week with income',
      );
      expect(
        savingsTrend([
          WeekFlow(
            start: monday,
            incomeCents: 10000,
            expenseCents: 8000,
            plannedCents: 0,
          ),
          WeekFlow(
            start: monday,
            incomeCents: 10000,
            expenseCents: 8100,
            plannedCents: 0,
          ),
        ]),
        Trend.estable,
      );
    });

    test('average surplus rounds to the cent', () {
      final flows = [
        WeekFlow(
          start: monday,
          incomeCents: 100,
          expenseCents: 0,
          plannedCents: 0,
        ),
        WeekFlow(
          start: monday,
          incomeCents: 0,
          expenseCents: 0,
          plannedCents: 0,
        ),
        WeekFlow(
          start: monday,
          incomeCents: 0,
          expenseCents: 0,
          plannedCents: 0,
        ),
      ];
      expect(averageSurplusCents(flows), 33);
      expect(averageSurplusCents(const []), 0);
    });

    test('only work entries with known money count as income', () {
      final income = MoneyIn.fromWork([
        WorkEntry(
          date: DateTime(2026, 10, 27),
          label: 'A',
          kind: WorkKind.values.first,
          minutes: 60,
          earnedCents: 500,
        ),
        WorkEntry(
          date: DateTime(2026, 10, 27),
          label: 'B',
          kind: WorkKind.values.first,
          minutes: 60,
        ),
      ]);
      expect(income, hasLength(1));
      expect(income.single.cents, 500);
    });
  });

  group('goals', () {
    test(
      'a parent goal takes its progress from its non-discarded sub-goals',
      () {
        final goals = [
          const Goal(
            id: 1,
            title: 'Grande',
            priority: 0,
            targetCents: 999999,
            savedCents: 5,
          ),
          const Goal(
            id: 2,
            parentId: 1,
            title: 'Parte A',
            priority: 0,
            targetCents: 30000,
            savedCents: 10000,
          ),
          const Goal(
            id: 3,
            parentId: 1,
            title: 'Parte B',
            priority: 1,
            targetCents: 20000,
            savedCents: 5000,
          ),
          const Goal(
            id: 4,
            parentId: 1,
            title: 'Descartada',
            priority: 2,
            targetCents: 50000,
            status: GoalStatus.descartado,
          ),
        ];
        final p = goalProgress(goals.first, goals);
        expect(p.savedCents, 15000);
        expect(p.targetCents, 50000);
        expect(goalRemainingCents(goals.first, goals), 35000);
      },
    );

    test('a sub-goal without a target leaves the parent without a target', () {
      final goals = [
        const Goal(id: 1, title: 'Grande', priority: 0),
        const Goal(
          id: 2,
          parentId: 1,
          title: 'Con costo',
          priority: 0,
          targetCents: 1000,
        ),
        const Goal(id: 3, parentId: 1, title: 'Sin costo', priority: 1),
      ];
      expect(goalProgress(goals.first, goals).targetCents, isNull);
      expect(goalEtaWeeks(goals.first, goals, 500), isNull);
    });

    test('tied priorities keep a stable order; only active goals count', () {
      final goals = [
        const Goal(id: 7, title: 'B', priority: 1),
        const Goal(id: 3, title: 'A', priority: 1),
        const Goal(
          id: 5,
          title: 'Pausada',
          priority: 0,
          status: GoalStatus.pausado,
        ),
        const Goal(id: 9, title: 'Primera', priority: 0),
      ];
      expect(orderedActiveGoals(goals).map((g) => g.id), [9, 3, 7]);
      expect(orderedActiveGoals(goals.reversed.toList()).map((g) => g.id), [
        9,
        3,
        7,
      ]);
    });

    test('ETA rounds up to whole weeks; none without surplus', () {
      final goals = [
        const Goal(
          id: 1,
          title: 'Meta',
          priority: 0,
          targetCents: 10000,
          savedCents: 1,
        ),
      ];
      expect(goalEtaWeeks(goals.first, goals, 3333), 3);
      expect(goalEtaWeeks(goals.first, goals, 9999), 1);
      expect(goalEtaWeeks(goals.first, goals, 0), isNull);
      expect(goalEtaWeeks(goals.first, goals, -500), isNull);
      final done = [
        const Goal(
          id: 1,
          title: 'Meta',
          priority: 0,
          targetCents: 100,
          savedCents: 150,
        ),
      ];
      expect(goalRemainingCents(done.first, done), 0);
      expect(goalEtaWeeks(done.first, done, 10), 0);
    });

    test(
      'splitting an income rounds down to the cent and never exceeds it',
      () {
        expect(splitCents(1999, 10), 199);
        expect(splitCents(1, 50), 0);
        expect(splitCents(5000, 150), 5000);
        expect(splitCents(0, 10), 0);
        expect(splitCents(5000, 0), 0);
      },
    );

    test('statuses parse with active as fallback', () {
      expect(GoalStatus.parse('completado'), GoalStatus.completado);
      expect(GoalStatus.parse(null), GoalStatus.activo);
    });
  });
}
