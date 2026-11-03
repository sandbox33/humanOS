import 'package:drift/drift.dart' show OrderingTerm, Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';
import '../../inicio/domain/schedule_model.dart';
import '../../registro/domain/intake.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;
import 'pantry_model.dart';

/// B4 settings (user data; nothing preset).
abstract final class FoodKey {
  /// '1' with a fridge, '0' without; absent = unknown (treated as without,
  /// the safer side for fresh food).
  static const hasFridge = 'has_fridge';

  /// The expense category a purchase is logged under (the last one used).
  static const purchaseCategory = 'purchase_expense_category';
}

String foodKeyOf({int? foodId, String? barcode}) => foodId != null ? 'f$foodId' : 'b${barcode ?? ''}';

final hasFridgeProvider = Provider<bool>(
  (ref) => (ref.watch(settingsMapProvider).value ?? const {})[FoodKey.hasFridge] == '1',
);

/// The user's handling flags by food key.
final handlingFlagsProvider = StreamProvider<Map<String, FoodHandling>>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.foodHandlingFlags).watch().map((rows) => {
        for (final r in rows)
          r.foodKey: FoodHandling(needsCold: r.needsCold, portable: r.portable, needsCooking: r.needsCooking),
      });
});

/// Stores the user's word on one food (null clears that column back to the
/// suggestion).
Future<void> setHandling(
  UserDb db,
  String foodKey, {
  required bool? needsCold,
  required bool? portable,
  required bool? needsCooking,
  required DateTime now,
}) =>
    db.into(db.foodHandlingFlags).insertOnConflictUpdate(FoodHandlingFlagsCompanion.insert(
          foodKey: foodKey,
          needsCold: Value(needsCold),
          portable: Value(portable),
          needsCooking: Value(needsCooking),
          updatedAt: stampOf(now),
        ));

/// The suggestion for a stock item from its food group, state and ripeness.
FoodHandling suggestionFor(Ref ref, StockView s) {
  final id = s.row.foodId;
  final record = id == null ? null : ref.read(referenceDbProvider)?.food(id);
  return suggestHandling(group: record?.group, state: record?.state, ripeness: record?.ripeness);
}

/// The handling of every stock item: the user's word over the suggestion.
final stockHandlingProvider = Provider<Map<String, FoodHandling>>((ref) {
  final flags = ref.watch(handlingFlagsProvider).value ?? const {};
  return {
    for (final s in ref.watch(stockViewProvider))
      s.key: (flags[foodKeyOf(foodId: s.row.foodId, barcode: s.row.barcode)] ?? const FoodHandling())
          .over(suggestionFor(ref, s)),
  };
});

/// Today's meal slots: from the user's schedule when it has meal blocks.
final scheduleMealSlotsProvider = Provider.family<List<MealSlot>, int>((ref, offset) {
  final params = ScheduleParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
  return slotsFromSchedule(ref.watch(dayPlanProvider(offset)), params);
});

/// The plan of one meal slot.
class SlotPlan {
  const SlotPlan({required this.slot, required this.kcal, required this.proteinG, this.plan, this.noteEs});

  final MealSlot slot;

  /// What this slot still needs.
  final double kcal;
  final double proteinG;
  final DietPlan? plan;
  final String? noteEs;

  Map<String, double> get grams => {
        for (final e in plan?.gramsByKey.entries ?? const <MapEntry<String, double>>[])
          if (e.value >= 1) e.key: e.value,
      };
}

/// Today's plan by meal: each slot gets its share of the day's energy and
/// protein (meal weights), minus what was already logged in it, from the
/// pantry foods that fit it (lunch-box food for mid-morning and
/// mid-afternoon; without a fridge, fresh food only on the day it was
/// bought). Grams used by one slot are not offered to the next.
final mealDayPlanProvider = Provider<List<SlotPlan>>((ref) {
  final status = ref.watch(energyStatusProvider);
  final slots = ref.watch(scheduleMealSlotsProvider(0));
  if (status == null || slots.isEmpty) return const [];
  final today = ref.watch(todayProvider);
  final iso = isoDate(today);
  final intake = ref.watch(dayIntakeProvider(iso)).value;
  final stock = ref.watch(stockViewProvider);
  final handling = ref.watch(stockHandlingProvider);
  final hasFridge = ref.watch(hasFridgeProvider);
  final a = ref.watch(currentAssumptionsProvider);
  final params = DietParams.fromAssumptions(a);
  final left = {for (final s in stock) s.key: s.row.gramsRemaining};
  final out = <SlotPlan>[];
  for (final slot in slots) {
    final eaten = intake?.blockTotals[slot.block];
    double positive(double v) => v < 0 ? 0 : v;
    final kcal = positive(status.targetKcal * slot.kcalShare - (eaten?.value(NutrientKey.energy) ?? 0));
    final protein = positive(status.macros.proteinPlanG * slot.kcalShare - (eaten?.value(NutrientKey.protein) ?? 0));
    if (kcal < 1 && protein < 1) {
      out.add(SlotPlan(slot: slot, kcal: 0, proteinG: 0, noteEs: 'Cubierta con lo que registraste.'));
      continue;
    }
    final foods = [
      for (final s in stock)
        if ((left[s.key] ?? 0) >= 1 &&
            fitsSlot(
              handling: handling[s.key] ?? const FoodHandling(),
              slot: slot.block,
              hasFridge: hasFridge,
              boughtToday: s.row.purchasedOn == iso,
            ))
          _limited(dietFoodOf(s), left[s.key]!),
    ];
    final plan = planDiet(
      foods: foods,
      targets: DietTargets(kcalMin: kcal, proteinMinG: protein, sodiumMaxMg: a[A.sodiumLimitMg] * slot.kcalShare),
      params: params,
    );
    if (plan.status == DietStatus.optimal) {
      for (final e in plan.gramsByKey.entries) {
        left[e.key] = (left[e.key] ?? 0) - e.value;
      }
    }
    out.add(SlotPlan(slot: slot, kcal: kcal, proteinG: protein, plan: plan));
  }
  return out;
});

DietFood _limited(DietFood f, double maxGrams) => DietFood(
      key: f.key,
      name: f.name,
      maxGrams: maxGrams,
      priceCentsPerKg: f.priceCentsPerKg,
      kcalPerG: f.kcalPerG,
      proteinPerG: f.proteinPerG,
      sodiumMgPerG: f.sodiumMgPerG,
      fatPerG: f.fatPerG,
      isBeverage: f.isBeverage,
    );

/// What the day's plan asks to cook: foods that need cooking in the
/// lunch and dinner slots, to cook once early and reheat at midday.
final cookTodayProvider = Provider<Map<String, double>>((ref) {
  final handling = ref.watch(stockHandlingProvider);
  final out = <String, double>{};
  for (final p in ref.watch(mealDayPlanProvider)) {
    if (p.slot.block != MealBlock.lunch && p.slot.block != MealBlock.dinner) continue;
    for (final e in p.grams.entries) {
      if (handling[e.key]?.needsCooking ?? false) out[e.key] = (out[e.key] ?? 0) + e.value;
    }
  }
  return out;
});

/// The shopping list: for every food eaten in the last 7 days, the grams
/// for the days to cover at that pace minus what is in stock, priced with
/// its last known price.
final shoppingListProvider = FutureProvider((ref) async {
  final db = ref.watch(userDbProvider);
  final today = ref.watch(todayProvider);
  final days = ref.watch(currentAssumptionsProvider).integer(A.shoppingCoverDays);
  final stock = ref.watch(stockViewProvider);
  final from = isoDate(addDays(today, -7));
  final rows = await db.customSelect(
    'SELECT mi.food_id AS food_id, mi.barcode AS barcode, SUM(mi.grams) AS grams '
    'FROM meal_items mi JOIN meals m ON m.id = mi.meal_id '
    'WHERE m.date >= ? AND m.date < ? AND (mi.food_id IS NOT NULL OR mi.barcode IS NOT NULL) '
    'GROUP BY mi.food_id, mi.barcode',
    variables: [Variable.withString(from), Variable.withString(isoDate(today))],
  ).get();
  final resolver = ref.read(nutritionResolverProvider);
  final needs = <ShoppingNeed>[];
  for (final r in rows) {
    final foodId = r.data['food_id'] as int?;
    final barcode = r.data['barcode'] as String?;
    final key = foodKeyOf(foodId: foodId, barcode: barcode);
    final same = stock.where((s) => foodKeyOf(foodId: s.row.foodId, barcode: s.row.barcode) == key).toList();
    final price = (await (db.select(db.pantryItems)
              ..where((t) => (foodId != null ? t.foodId.equals(foodId) : t.barcode.equals(barcode!)) &
                  t.priceCentsPerKg.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull())
        ?.priceCentsPerKg;
    needs.add(ShoppingNeed(
      key: key,
      name: resolver.resolve(foodId: foodId, barcode: barcode).name,
      gramsNeeded: (r.data['grams'] as num).toDouble() / 7 * days,
      gramsInStock: same.fold(0.0, (s, x) => s + x.row.gramsRemaining),
      priceCentsPerKg: price,
    ));
  }
  return shoppingList(needs);
});

/// The one cooking reminder of the day: at the user's COCINAR block, or at
/// the first meal when there is none. Cook once what lunch and dinner
/// need, keep the lunch portion and reheat it at midday. Null when nothing
/// needs cooking.
({DateTime at, String body})? cookReminderFor(WidgetRef ref, DateTime day) {
  final cook = ref.read(cookTodayProvider);
  if (cook.isEmpty) return null;
  final plan = ref.read(dayPlanProvider(0));
  final cooking = plan.where((b) => b.active && b.kind == BlockKind.cocinar).firstOrNull;
  final slots = ref.read(scheduleMealSlotsProvider(0));
  final minute = cooking?.startMin ?? (slots.isEmpty ? null : slots.first.minuteOfDay);
  if (minute == null) return null;
  final names = {for (final s in ref.read(stockViewProvider)) s.key: s.food.name};
  final list = [for (final e in cook.entries) '${names[e.key] ?? e.key} ${e.value.round()} g'].join(', ');
  return (
    at: day.add(Duration(minutes: minute)),
    body: 'Cocina una vez: $list. Aparta la porción del almuerzo y recaliéntala al mediodía hasta que humee.',
  );
}
