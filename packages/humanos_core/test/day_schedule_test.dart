import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

int at(String clock) => parseClock(clock);

// The brief's example day, only as test data (the app presets nothing).
const weekdays = 0x1F; // Monday–Friday
const everyDay = 0x7F;
final template = [
  BlockTemplate(
    id: 1,
    kind: BlockKind.desayuno,
    startMin: at('05:00'),
    daysMask: everyDay,
    alarm: true,
  ),
  BlockTemplate(
    id: 2,
    kind: BlockKind.trabajo,
    startMin: at('07:00'),
    durationMin: 540,
    daysMask: weekdays,
  ),
  BlockTemplate(
    id: 3,
    kind: BlockKind.mediaManana,
    startMin: at('08:00'),
    daysMask: everyDay,
  ),
  BlockTemplate(
    id: 4,
    kind: BlockKind.almuerzo,
    startMin: at('13:00'),
    daysMask: everyDay,
  ),
  BlockTemplate(
    id: 5,
    kind: BlockKind.entreno,
    startMin: at('16:30'),
    durationMin: 90,
    daysMask: weekdays,
  ),
  BlockTemplate(
    id: 6,
    kind: BlockKind.mediaTarde,
    startMin: at('18:00'),
    daysMask: everyDay,
  ),
  BlockTemplate(
    id: 7,
    kind: BlockKind.proyecto,
    startMin: at('19:00'),
    daysMask: everyDay,
    label: 'Proyecto nocturno',
  ),
  BlockTemplate(
    id: 8,
    kind: BlockKind.dormir,
    startMin: at('21:00'),
    daysMask: everyDay,
    alarm: true,
  ),
];

PlannedBlock byId(List<PlannedBlock> plan, int id) =>
    plan.firstWhere((b) => b.id == id);

void main() {
  group('template day', () {
    test(
      'weekday blocks in order; sleep runs to the next morning; meals are short',
      () {
        final plan = planDay(templates: template, weekday: DateTime.monday);
        expect(plan.map((b) => b.id), [1, 2, 3, 4, 5, 6, 7, 8]);
        expect(byId(plan, 8).endMin, at('05:00') + 1440);
        expect(byId(plan, 3).minutes, 30);
        expect(
          byId(plan, 7).endMin,
          at('21:00'),
          reason: 'until the next non-meal block',
        );
        expect(byId(plan, 7).title, 'Proyecto nocturno');
        expect(byId(plan, 1).title, 'Desayuno');
      },
    );

    test('a weekend day has only the blocks marked for it', () {
      final plan = planDay(templates: template, weekday: DateTime.saturday);
      expect(plan.map((b) => b.id), [1, 3, 4, 6, 7, 8]);
      expect(byId(plan, 7).startMin, at('19:00'));
    });

    test('an empty template gives an empty day', () {
      expect(planDay(templates: const [], weekday: 1), isEmpty);
    });
  });

  group('flexible day', () {
    test(
      'overtime until 20:00 pushes training, shortens it, and the project passes to tomorrow; sleep stays',
      () {
        final plan = planDay(
          templates: template,
          weekday: DateTime.tuesday,
          adjustments: [
            DayAdjustment(
              action: AdjustAction.extender,
              blockId: 2,
              endMin: at('20:00'),
            ),
          ],
        );
        final work = byId(plan, 2);
        expect(work.endMin, at('20:00'));
        expect(work.status, BlockStatus.movido);
        final training = byId(plan, 5);
        expect(training.startMin, at('20:00'));
        expect(training.endMin, at('21:00'));
        expect(training.status, BlockStatus.acortado);
        expect(byId(plan, 7).status, BlockStatus.manana);
        expect(
          byId(plan, 8).startMin,
          at('21:00'),
          reason: 'sleep only moves when the user moves it',
        );
        expect(
          byId(plan, 6).startMin,
          at('18:00'),
          reason: 'meals are not pushed',
        );
      },
    );

    test(
      'an added overtime block shortens the project to what is left before sleep',
      () {
        final plan = planDay(
          templates: template,
          weekday: DateTime.saturday,
          adjustments: [
            DayAdjustment(
              action: AdjustAction.agregar,
              kind: BlockKind.horasExtra,
              startMin: at('16:00'),
              endMin: at('19:45'),
            ),
          ],
        );
        final extra = plan.firstWhere((b) => b.kind == BlockKind.horasExtra);
        expect(extra.fromTemplate, isFalse);
        expect(extra.id, -1);
        final project = byId(plan, 7);
        expect(project.startMin, at('19:45'));
        expect(project.endMin, at('21:00'));
        expect(project.status, BlockStatus.acortado);
      },
    );

    test('less than the minimum left moves the block to tomorrow', () {
      final plan = planDay(
        templates: template,
        weekday: DateTime.saturday,
        minFlexibleMin: 30,
        adjustments: [
          DayAdjustment(
            action: AdjustAction.agregar,
            kind: BlockKind.horasExtra,
            startMin: at('18:30'),
            endMin: at('20:40'),
          ),
        ],
      );
      expect(byId(plan, 7).status, BlockStatus.manana);
      expect(byId(plan, 7).active, isFalse);
    });

    test(
      'skipping and moving apply only to that day; moving sleep is the user\'s choice',
      () {
        final plan = planDay(
          templates: template,
          weekday: DateTime.wednesday,
          adjustments: [
            const DayAdjustment(action: AdjustAction.saltar, blockId: 5),
            DayAdjustment(
              action: AdjustAction.mover,
              blockId: 8,
              startMin: at('22:00'),
            ),
          ],
        );
        expect(byId(plan, 5).status, BlockStatus.saltado);
        final sleep = byId(plan, 8);
        expect(sleep.startMin, at('22:00'));
        expect(sleep.minutes, 480, reason: 'moving keeps the duration');
        expect(
          byId(plan, 7).endMin,
          at('21:00'),
          reason: 'the project keeps its template time',
        );
        expect(
          planDay(
            templates: template,
            weekday: DateTime.thursday,
          ).every((b) => b.status == BlockStatus.normal),
          isTrue,
        );
      },
    );

    test('an end before the start means the next day', () {
      final plan = planDay(
        templates: template,
        weekday: DateTime.friday,
        adjustments: [
          DayAdjustment(
            action: AdjustAction.agregar,
            kind: BlockKind.trabajo,
            startMin: at('22:00'),
            endMin: at('06:00'),
          ),
        ],
      );
      final night = plan.firstWhere((b) => b.id == -1);
      expect(night.endMin, at('06:00') + 1440);
    });
  });

  group('now and next', () {
    final monday = planDay(templates: template, weekday: DateTime.monday);

    test('a meal inside work is the current block', () {
      final r = blockAt(today: monday, nowMin: at('08:10'));
      expect(r.current!.id, 3);
      expect(r.minutesLeft, 20);
      expect(r.next!.id, 4);
      expect(r.minutesToNext, at('13:00') - at('08:10'));
    });

    test('inside work without a meal', () {
      final r = blockAt(today: monday, nowMin: at('10:00'));
      expect(r.current!.kind, BlockKind.trabajo);
      expect(r.minutesLeft, at('16:00') - at('10:00'));
    });

    test('after midnight, yesterday\'s sleep is still the current block', () {
      final r = blockAt(today: monday, yesterday: monday, nowMin: at('02:00'));
      expect(r.current!.kind, BlockKind.dormir);
      expect(r.minutesLeft, 180);
      expect(r.next!.id, 1);
    });

    test('after the last block the next one comes from tomorrow', () {
      final r = blockAt(today: monday, tomorrow: monday, nowMin: at('23:00'));
      expect(r.current!.kind, BlockKind.dormir);
      expect(r.next!.id, 1);
      expect(r.minutesToNext, 360);
    });

    test('countdowns read in Spanish', () {
      expect(countdownEs(0), 'menos de 1 min');
      expect(countdownEs(12), '12 min');
      expect(countdownEs(65), '1 h 05 min');
    });

    test('kinds round-trip their codes', () {
      for (final k in BlockKind.values) {
        expect(BlockKind.parse(k.code), k);
      }
      for (final a in AdjustAction.values) {
        expect(AdjustAction.parse(a.code), a);
      }
      expect(BlockKind.parse('x'), BlockKind.otro);
      expect(AdjustAction.parse('x'), isNull);
    });
  });
}
