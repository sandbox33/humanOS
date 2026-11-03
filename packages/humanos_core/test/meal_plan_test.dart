import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// The brief's example day, only as test data.
PlannedBlock block(
  int id,
  BlockKind kind,
  int start,
  int end, {
  BlockStatus status = BlockStatus.normal,
}) => PlannedBlock(
  id: id,
  kind: kind,
  title: kind.labelEs,
  startMin: start,
  endMin: end,
  alarm: false,
  status: status,
);

void main() {
  final params = ScheduleParams.fromAssumptions(Assumptions.defaults());
  final day = [
    block(1, BlockKind.desayuno, 300, 330),
    block(2, BlockKind.trabajo, 420, 960),
    block(3, BlockKind.mediaManana, 480, 510),
    block(4, BlockKind.almuerzo, 780, 810),
    block(5, BlockKind.mediaTarde, 1080, 1110),
    block(6, BlockKind.dormir, 1260, 1740),
  ];

  group('meal slots from the schedule', () {
    test(
      'one slot per meal block, in order, with shares from the meal weights',
      () {
        final slots = slotsFromSchedule(day, params);
        expect(slots.map((s) => s.block), [
          MealBlock.breakfast,
          MealBlock.midMorning,
          MealBlock.lunch,
          MealBlock.afternoon,
        ]);
        expect(slots.map((s) => s.minuteOfDay), [300, 480, 780, 1080]);
        expect(slots.fold(0.0, (s, x) => s + x.kcalShare), closeTo(1, 1e-9));
        final expected =
            params.weights[MealBlock.lunch]! /
            [
              MealBlock.breakfast,
              MealBlock.midMorning,
              MealBlock.lunch,
              MealBlock.afternoon,
            ].fold(0.0, (s, b) => s + params.weights[b]!);
        expect(slots[2].kcalShare, closeTo(expected, 1e-9));
        expect(slots.first.contextEs, 'Desayuno');
      },
    );

    test(
      'skipped meals are left out; a day without meal blocks has no slots',
      () {
        final skipped = [...day]
          ..[3] = block(
            4,
            BlockKind.almuerzo,
            780,
            810,
            status: BlockStatus.saltado,
          );
        expect(
          slotsFromSchedule(skipped, params).map((s) => s.block),
          isNot(contains(MealBlock.lunch)),
        );
        expect(
          slotsFromSchedule([block(2, BlockKind.trabajo, 420, 960)], params),
          isEmpty,
        );
      },
    );

    test('the slot to log into is the last one started, with margin', () {
      final slots = slotsFromSchedule(day, params);
      expect(
        slotAt(slots, 200)!.block,
        MealBlock.breakfast,
        reason: 'before the first slot',
      );
      expect(
        slotAt(slots, 460)!.block,
        MealBlock.midMorning,
        reason: '20 min before 08:00',
      );
      expect(slotAt(slots, 900)!.block, MealBlock.lunch);
      expect(slotAt(const [], 900), isNull);
      expect(mealBlockOfKind(BlockKind.trabajo), isNull);
    });
  });

  group('food handling', () {
    test('suggestions from the food group and state; the user wins', () {
      final chicken = suggestHandling(group: 'Aves', state: 'raw');
      expect(chicken.needsCold, isTrue);
      expect(chicken.needsCooking, isTrue);
      expect(chicken.portable, isFalse);
      final nuts = suggestHandling(
        group: 'Frutos secos y semillas',
        state: 'raw',
      );
      expect(nuts.portable, isTrue);
      expect(nuts.needsCooking, isFalse);
      final greenPlantain = suggestHandling(
        group: 'Frutas y jugos',
        state: 'raw',
        ripeness: 'green',
      );
      expect(greenPlantain.needsCooking, isTrue);
      expect(greenPlantain.portable, isFalse);
      expect(suggestHandling().needsCold, isNull);
      final eggs = const FoodHandling(
        needsCold: false,
      ).over(suggestHandling(group: 'Lácteos y huevos'));
      expect(
        eggs.needsCold,
        isFalse,
        reason: 'the user says eggs keep without a fridge',
      );
    });

    test(
      'without a fridge, cold food only on the day it was bought; lunch boxes need portable food',
      () {
        const meat = FoodHandling(
          needsCold: true,
          portable: false,
          needsCooking: true,
        );
        expect(
          fitsSlot(
            handling: meat,
            slot: MealBlock.lunch,
            hasFridge: false,
            boughtToday: false,
          ),
          isFalse,
        );
        expect(
          fitsSlot(
            handling: meat,
            slot: MealBlock.lunch,
            hasFridge: false,
            boughtToday: true,
          ),
          isTrue,
        );
        expect(
          fitsSlot(
            handling: meat,
            slot: MealBlock.lunch,
            hasFridge: true,
            boughtToday: false,
          ),
          isTrue,
        );
        expect(
          fitsSlot(
            handling: meat,
            slot: MealBlock.midMorning,
            hasFridge: true,
            boughtToday: true,
          ),
          isFalse,
        );
        const banana = FoodHandling(
          needsCold: false,
          portable: true,
          needsCooking: false,
        );
        expect(
          fitsSlot(
            handling: banana,
            slot: MealBlock.afternoon,
            hasFridge: false,
            boughtToday: false,
          ),
          isTrue,
        );
        expect(
          fitsSlot(
            handling: const FoodHandling(),
            slot: MealBlock.afternoon,
            hasFridge: false,
            boughtToday: false,
          ),
          isFalse,
        );
      },
    );
  });

  test(
    'shopping list: grams missing, cost where priced, unpriced counted apart',
    () {
      final list = shoppingList(const [
        ShoppingNeed(
          key: 'a',
          name: 'Arroz',
          gramsNeeded: 1000,
          gramsInStock: 400,
          priceCentsPerKg: 150,
        ),
        ShoppingNeed(
          key: 'b',
          name: 'Huevo',
          gramsNeeded: 300,
          gramsInStock: 0,
        ),
        ShoppingNeed(
          key: 'c',
          name: 'Maní',
          gramsNeeded: 100,
          gramsInStock: 250,
          priceCentsPerKg: 600,
        ),
        ShoppingNeed(
          key: 'd',
          name: 'Leche',
          gramsNeeded: 250.4,
          gramsInStock: 0,
          priceCentsPerKg: 110,
        ),
      ]);
      expect(list.lines.map((l) => l.key), ['a', 'b', 'd']);
      expect(list.lines.first.grams, 600);
      expect(list.lines.first.costCents, 90);
      expect(list.lines[1].costCents, isNull);
      expect(list.lines[2].grams, 251);
      expect(list.knownCents, 90 + 28);
      expect(list.unpriced, 1);
    },
  );
}
