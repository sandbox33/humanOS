/// Meals of the user's day (B4): the meal blocks of the schedule become the
/// day's meal slots, foods are suited to each slot by how they keep and
/// travel, and what the plan needs and the pantry lacks becomes a
/// shopping list. Every rule here can be overridden by the user.
library;

import 'day_schedule.dart';
import 'interaction_rules.dart' show MealBlock;
import 'schedule.dart' show MealSlot, ScheduleParams;

/// The meal block a schedule block stands for; null for non-meals.
MealBlock? mealBlockOfKind(BlockKind kind) => switch (kind) {
  BlockKind.desayuno => MealBlock.breakfast,
  BlockKind.mediaManana => MealBlock.midMorning,
  BlockKind.almuerzo => MealBlock.lunch,
  BlockKind.mediaTarde => MealBlock.afternoon,
  BlockKind.cena => MealBlock.dinner,
  _ => null,
};

/// The meal slots of a day from the user's schedule: one per active meal
/// block, at its time, with its share of the day's energy taken from the
/// meal weights (SUPUESTOS → HORARIO DE COMIDAS). Empty when the day has
/// no meal block.
List<MealSlot> slotsFromSchedule(
  List<PlannedBlock> plan,
  ScheduleParams params,
) {
  final meals = [
    for (final b in plan)
      if (b.active)
        if (mealBlockOfKind(b.kind) case final block?) (b, block),
  ]..sort((x, y) => x.$1.startMin.compareTo(y.$1.startMin));
  if (meals.isEmpty) return const [];
  final total = meals.fold(0.0, (s, m) => s + (params.weights[m.$2] ?? 0));
  return [
    for (final (b, block) in meals)
      MealSlot(
        block: block,
        minuteOfDay: b.startMin % (24 * 60),
        kcalShare: total == 0
            ? 1 / meals.length
            : (params.weights[block] ?? 0) / total,
        contextEs: b.title,
      ),
  ];
}

/// The slot to log into at [nowMin]: the last one already started (with
/// [marginMin] of margin before its time), else the first of the day.
MealSlot? slotAt(List<MealSlot> slots, int nowMin, {int marginMin = 30}) {
  if (slots.isEmpty) return null;
  var best = slots.first;
  for (final s in slots) {
    if (s.minuteOfDay <= nowMin + marginMin) best = s;
  }
  return best;
}

/// How a food keeps and travels. A null field is "not known": the
/// suggestion decides until the user does.
class FoodHandling {
  const FoodHandling({this.needsCold, this.portable, this.needsCooking});

  /// Spoils without a fridge (fresh meat, fish, fresh dairy…).
  final bool? needsCold;

  /// Can go in a lunch box for mid-morning or mid-afternoon.
  final bool? portable;

  /// Must be cooked before eating (raw grains, legumes, meat…).
  final bool? needsCooking;

  /// The user's choice where there is one, the suggestion otherwise.
  FoodHandling over(FoodHandling suggestion) => FoodHandling(
    needsCold: needsCold ?? suggestion.needsCold,
    portable: portable ?? suggestion.portable,
    needsCooking: needsCooking ?? suggestion.needsCooking,
  );
}

const _coldGroups = {
  'Aves',
  'Cerdo',
  'Res',
  'Pescados y mariscos',
  'Cordero, ternera y caza',
  'Embutidos',
  'Lácteos y huevos',
};
const _portableGroups = {
  'Frutas y jugos',
  'Frutos secos y semillas',
  'Panadería',
  'Snacks',
  'Cereales de desayuno',
};
const _cookGroups = {
  'Cereales y pastas',
  'Leguminosas',
  'Aves',
  'Cerdo',
  'Res',
  'Pescados y mariscos',
  'Cordero, ternera y caza',
};

/// First suggestion from the food's group and state in the reference
/// database; the user corrects any food (eggs or long-life milk keep
/// without a fridge, for example).
FoodHandling suggestHandling({String? group, String? state, String? ripeness}) {
  if (group == null) return const FoodHandling();
  final raw = state == 'raw';
  final green = ripeness == 'green';
  return FoodHandling(
    needsCold: _coldGroups.contains(group),
    portable: _portableGroups.contains(group) && !green,
    needsCooking: (raw && _cookGroups.contains(group)) || green,
  );
}

/// Whether a food fits a slot. Without a fridge, a food that needs cold is
/// used only on the day it was bought (bought and cooked the same day).
/// Mid-morning and mid-afternoon take only lunch-box food that needs no
/// cooking.
bool fitsSlot({
  required FoodHandling handling,
  required MealBlock slot,
  required bool hasFridge,
  required bool boughtToday,
}) {
  if (!hasFridge && (handling.needsCold ?? false) && !boughtToday) return false;
  if (slot == MealBlock.midMorning || slot == MealBlock.afternoon) {
    return (handling.portable ?? false) && !(handling.needsCooking ?? false);
  }
  return true;
}

/// One thing to buy.
class ShoppingLine {
  const ShoppingLine({
    required this.key,
    required this.name,
    required this.grams,
    this.costCents,
  });

  final String key;
  final String name;
  final double grams;

  /// Null when the food has no known price.
  final int? costCents;
}

/// What the plan still needs beyond what is in stock.
class ShoppingNeed {
  const ShoppingNeed({
    required this.key,
    required this.name,
    required this.gramsNeeded,
    required this.gramsInStock,
    this.priceCentsPerKg,
  });

  final String key;
  final String name;
  final double gramsNeeded;
  final double gramsInStock;
  final int? priceCentsPerKg;
}

/// The shopping list: grams to buy per food (rounded up to the gram) and
/// its cost where a price is known; the total adds only known costs and
/// says how many lines have no price.
({List<ShoppingLine> lines, int knownCents, int unpriced}) shoppingList(
  List<ShoppingNeed> needs,
) {
  final lines = <ShoppingLine>[];
  var known = 0, unpriced = 0;
  for (final n in needs) {
    final missing = n.gramsNeeded - n.gramsInStock;
    if (missing <= 0) continue;
    final grams = missing.ceilToDouble();
    final price = n.priceCentsPerKg;
    final cost = price == null ? null : (grams * price / 1000).round();
    if (cost == null) {
      unpriced++;
    } else {
      known += cost;
    }
    lines.add(
      ShoppingLine(key: n.key, name: n.name, grams: grams, costCents: cost),
    );
  }
  return (lines: lines, knownCents: known, unpriced: unpriced);
}
