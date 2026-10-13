import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/nutrition_resolver.dart';
import '../../../data/reference_models.dart';
import '../../../data/user_db.dart';
import '../../despensa/data/pantry_repository.dart';
import '../data/meals_repository.dart';

final mealsRepositoryProvider =
    Provider<MealsRepository>((ref) => MealsRepository(ref.watch(userDbProvider)));

final pantryRepositoryProvider =
    Provider<PantryRepository>((ref) => PantryRepository(ref.watch(userDbProvider)));

final cachedProductsProvider = StreamProvider<Map<String, ProductRecord>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchCachedProducts(),
);

final foodFlagsProvider = StreamProvider<Map<int, FoodFlags>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchFlags(),
);

final nutritionResolverProvider = Provider<NutritionResolver>(
  (ref) => NutritionResolver(
    reference: ref.watch(referenceDbProvider),
    cachedProducts: ref.watch(cachedProductsProvider).value ?? const {},
    flags: ref.watch(foodFlagsProvider).value ?? const {},
  ),
);

/// A logged item with its resolved food.
class LoggedItem {
  const LoggedItem({required this.row, required this.block, required this.food});
  final MealItemRow row;
  final MealBlock block;
  final ResolvedFood food;

  double? get kcal => food.profile.forGrams(NutrientKey.energy, row.grams);
  double? get proteinG => food.profile.forGrams(NutrientKey.protein, row.grams);
}

class DayIntake {
  DayIntake({required this.date, required this.items})
      : totals = NutrientTotals(),
        blockTotals = {} {
    for (final item in items) {
      totals.add(item.food.name, item.food.profile, item.row.grams);
      (blockTotals[item.block] ??= NutrientTotals())
          .add(item.food.name, item.food.profile, item.row.grams);
    }
  }

  final String date;
  final List<LoggedItem> items;
  final NutrientTotals totals;
  final Map<MealBlock, NutrientTotals> blockTotals;

  List<LoggedItem> inBlock(MealBlock block) =>
      items.where((i) => i.block == block).toList();

  bool get isEmpty => items.isEmpty;
}

DayIntake buildDayIntake(String date, List<MealEntry> entries, NutritionResolver resolver) =>
    DayIntake(
      date: date,
      items: [
        for (final e in entries)
          for (final row in e.items)
            LoggedItem(
              row: row,
              block: e.block,
              food: resolver.resolve(
                foodId: row.foodId,
                barcode: row.barcode,
                recipeId: row.recipeId,
              ),
            ),
      ],
    );

/// Intake of one day (`YYYY-MM-DD`), live.
final dayIntakeProvider = StreamProvider.family<DayIntake, String>((ref, date) {
  final resolver = ref.watch(nutritionResolverProvider);
  return ref
      .watch(mealsRepositoryProvider)
      .watchDay(date)
      .map((entries) => buildDayIntake(date, entries, resolver));
});

/// Interaction report for a block of a day (warnings only).
InteractionReport blockInteractions({
  required DayIntake day,
  required MealBlock block,
  required Map<MealBlock, int> blockMinutes,
  required InteractionParams params,
  required bool shiftDay,
}) {
  final items = day.inBlock(block);
  DateTime at(MealBlock b) {
    final base = parseIsoDate(day.date);
    return base.add(Duration(minutes: blockMinutes[b] ?? 0));
  }

  final meal = MealContext(
    block: block,
    at: at(block),
    items: [for (final i in items) i.food.toNutrientItem(i.row.grams)],
  );
  final others = [
    for (final other in MealBlock.values)
      if (other != block && day.inBlock(other).isNotEmpty)
        MealContext(
          block: other,
          at: at(other),
          items: [
            for (final i in day.inBlock(other)) i.food.toNutrientItem(i.row.grams),
          ],
        ),
  ];
  return checkInteractions(meal: meal, others: others, params: params, shiftDay: shiftDay);
}
