import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented packages only.
DateTime t(int h, [int m = 0, int s = 0]) => DateTime(2026, 11, 3, h, m, s);
UsageEvent on(String p, DateTime at, {String a = ''}) =>
    UsageEvent(package: p, type: UsageEventType.resumed, at: at, activity: a);
UsageEvent off(String p, DateTime at, {String a = ''}) =>
    UsageEvent(package: p, type: UsageEventType.paused, at: at, activity: a);

void main() {
  group('intervals from events', () {
    test('pairs resume and pause; an open app counts until now', () {
      final list = intervalsFromEvents([
        on('test.juego', t(19)),
        off('test.juego', t(19, 30)),
        on('test.video', t(20)),
      ], until: t(20, 10));
      expect(list, hasLength(2));
      expect(list.first.seconds, 1800);
      expect(list.last.end, t(20, 10));
    });

    test(
      'a pause without its resume is ignored; two activities of one app are not counted twice',
      () {
        final list = intervalsFromEvents([
          off('test.juego', t(8)),
          on('test.juego', t(9), a: 'A'),
          on('test.juego', t(9, 5), a: 'B'),
          off('test.juego', t(9, 10), a: 'A'),
          off('test.juego', t(9, 20), a: 'B'),
        ], until: t(10));
        expect(list, hasLength(1));
        expect(list.single.start, t(9));
        expect(list.single.end, t(9, 20));
      },
    );
  });

  group('minutes', () {
    final intervals = [
      UsageInterval(
        package: 'test.juego',
        start: t(23, 30),
        end: DateTime(2026, 11, 4, 0, 20),
      ),
      UsageInterval(package: 'test.notas', start: t(10), end: t(10, 45)),
      UsageInterval(package: 'test.notas', start: t(11), end: t(11, 0, 20)),
    ];

    test(
      'per app per calendar day, split at midnight and rounded to the minute',
      () {
        expect(minutesByApp(intervals, t(0)), {
          'test.juego': 30,
          'test.notas': 45,
        });
        expect(minutesByApp(intervals, DateTime(2026, 11, 4)), {
          'test.juego': 20,
        });
      },
    );

    test('per category, with unclassified apps kept apart', () {
      final byCategory = minutesByCategory(
        {'test.juego': 30, 'test.notas': 45, 'test.nuevo': 5},
        {'test.juego': AppCategory.ocio, 'test.notas': AppCategory.trabajo},
      );
      expect(byCategory, {
        AppCategory.ocio: 30,
        AppCategory.trabajo: 45,
        AppCategory.sinClasificar: 5,
      });
    });

    test('per block of the day', () {
      final plan = [
        PlannedBlock(
          id: 1,
          kind: BlockKind.trabajo,
          title: 'Trabajo',
          startMin: 600,
          endMin: 660,
          alarm: false,
          status: BlockStatus.normal,
        ),
        PlannedBlock(
          id: 2,
          kind: BlockKind.ocio,
          title: 'Ocio',
          startMin: 1380,
          endMin: 1500,
          alarm: false,
          status: BlockStatus.normal,
        ),
      ];
      final byBlock = minutesByBlock(
        intervals: intervals,
        plan: plan,
        day: t(0),
        classes: {
          'test.juego': AppCategory.ocio,
          'test.notas': AppCategory.trabajo,
        },
      );
      expect(byBlock[1], {AppCategory.trabajo: 45});
      expect(byBlock[2], {
        AppCategory.ocio: 50,
      }, reason: 'the block runs past midnight');
    });

    test('seven-day trend keeps missing days as unknown', () {
      final trend = sevenDayTrend({'2026-11-03': 120, '2026-11-01': 60}, t(0));
      expect(trend, [null, null, null, null, 60, null, 120]);
    });
  });

  group('hiding in blocks', () {
    final today = [
      PlannedBlock(
        id: 1,
        kind: BlockKind.otro,
        title: 'Mañana',
        startMin: 300,
        endMin: 420,
        alarm: false,
        status: BlockStatus.normal,
      ),
      PlannedBlock(
        id: 2,
        kind: BlockKind.dormir,
        title: 'Dormir',
        startMin: 1260,
        endMin: 1740,
        alarm: false,
        status: BlockStatus.normal,
      ),
      PlannedBlock(
        id: 3,
        kind: BlockKind.ocio,
        title: 'Ocio',
        startMin: 1080,
        endMin: 1200,
        alarm: false,
        status: BlockStatus.normal,
      ),
    ];
    const rule = HideRule(
      blockIds: {1, 2},
      categories: {AppCategory.ocio, AppCategory.redes},
    );

    test('a game is hidden at 05:30 and shown at 19:00', () {
      expect(hiddenCategoriesAt(rule: rule, nowMin: 330, today: today), {
        AppCategory.ocio,
        AppCategory.redes,
      });
      expect(
        hiddenCategoriesAt(rule: rule, nowMin: 1140, today: today),
        isEmpty,
      );
    });

    test('after midnight, yesterday\'s sleep block still hides', () {
      expect(
        hiddenCategoriesAt(
          rule: rule,
          nowMin: 120,
          today: const [],
          yesterday: today,
        ),
        contains(AppCategory.ocio),
      );
    });

    test('without blocks or categories nothing is hidden', () {
      expect(
        hiddenCategoriesAt(
          rule: const HideRule(blockIds: {}, categories: {AppCategory.ocio}),
          nowMin: 330,
          today: today,
        ),
        isEmpty,
      );
    });

    test('a skipped block hides nothing that day', () {
      final skipped = [today.first.copyWith(status: BlockStatus.saltado)];
      expect(
        hiddenCategoriesAt(rule: rule, nowMin: 330, today: skipped),
        isEmpty,
      );
    });

    test('use of hidden apps inside hidden blocks is measured as data', () {
      final minutes = minutesWhileHidden(
        intervals: [
          UsageInterval(package: 'test.juego', start: t(5, 50), end: t(7, 10)),
          UsageInterval(package: 'test.notas', start: t(6), end: t(6, 30)),
        ],
        plan: today,
        day: t(0),
        rule: rule,
        classes: {
          'test.juego': AppCategory.ocio,
          'test.notas': AppCategory.trabajo,
        },
      );
      expect(
        minutes,
        70,
        reason: '05:50–07:00 of the game inside the 05:00–07:00 block',
      );
    });
  });

  test(
    'suggestions come from the category the app declares; unknown stays unclassified',
    () {
      expect(suggestCategory(0), AppCategory.ocio);
      expect(suggestCategory(4), AppCategory.redes);
      expect(suggestCategory(7), AppCategory.trabajo);
      expect(suggestCategory(-1), AppCategory.sinClasificar);
      expect(suggestCategory(null), AppCategory.sinClasificar);
      for (final c in AppCategory.values) {
        expect(AppCategory.parse(c.code), c);
      }
    },
  );
}
