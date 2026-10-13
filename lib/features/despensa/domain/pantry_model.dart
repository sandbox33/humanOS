import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/nutrients.dart';
import '../../../data/nutrition_resolver.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/targets.dart';
import '../../registro/domain/intake.dart';
import '../../turno/domain/hydration.dart';
import '../data/pantry_repository.dart';

final pantryStockProvider = StreamProvider<List<PantryItemRow>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchStock(),
);

final purchasesProvider = StreamProvider<List<PurchaseRow>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchPurchases(),
);

final openBatchesProvider = StreamProvider<List<CookedBatchRow>>(
  (ref) => ref.watch(pantryRepositoryProvider).watchOpenBatches(),
);

class StockView {
  const StockView({required this.row, required this.food, required this.daysToExpiry});
  final PantryItemRow row;
  final ResolvedFood food;
  final int? daysToExpiry;

  String get key => 'p${row.id}';
}

final stockViewProvider = Provider<List<StockView>>((ref) {
  final rows = ref.watch(pantryStockProvider).value ?? const <PantryItemRow>[];
  final resolver = ref.watch(nutritionResolverProvider);
  final today = ref.watch(todayProvider);
  return [
    for (final r in rows)
      StockView(
        row: r,
        food: resolver.resolve(foodId: r.foodId, barcode: r.barcode),
        daysToExpiry: daysToExpiry(r, today),
      ),
  ];
});

/// What is still missing today (never negative).
final todayGapProvider = Provider<NutritionGap?>((ref) {
  final status = ref.watch(energyStatusProvider);
  if (status == null) return null;
  final intake = ref.watch(dayIntakeProvider(isoDate(ref.watch(todayProvider)))).value;
  final eatenKcal = intake?.totals.value(NutrientKey.energy) ?? 0;
  final eatenProtein = intake?.totals.value(NutrientKey.protein) ?? 0;
  double positive(double v) => v < 0 ? 0 : v;
  return NutritionGap(
    kcal: positive(status.targetKcal - eatenKcal),
    proteinG: positive(status.macros.proteinPlanG - eatenProtein),
  );
});

PantryCandidate candidateOf(StockView s) {
  final p = s.food.profile;
  return PantryCandidate(
    key: s.key,
    name: s.food.name,
    gramsAvailable: s.row.gramsRemaining,
    kcalPer100g: p.per100g(NutrientKey.energy),
    proteinPer100g: p.per100g(NutrientKey.protein),
    nrf93Per100kcal: s.food.properties?.nrf93Per100kcal,
    priceUsdPerKg: s.row.priceUsdPerKg,
    diaas: s.food.properties?.diaas,
    nova: s.food.nova,
    userExcluded: s.food.flags.excluded,
    daysToExpiry: s.daysToExpiry,
    foodConfidence: s.food.properties?.confidence ??
        (s.food.barcode != null ? Confidence.media : Confidence.baja),
  );
}

/// "MEJOR OPCIÓN AHORA".
final bestOptionsProvider = Provider<List<ScoredCandidate>>((ref) {
  final stock = ref.watch(stockViewProvider);
  final gap = ref.watch(todayGapProvider) ?? const NutritionGap(kcal: 0, proteinG: 0);
  final params = ScorerParams.fromAssumptions(ref.watch(currentAssumptionsProvider));
  return scorePantry([for (final s in stock) candidateOf(s)], gap: gap, params: params);
});

DietFood dietFoodOf(StockView s) {
  final p = s.food.profile;
  double? perGram(NutrientKey k) {
    final v = p.per100g(k);
    return v == null ? null : v / 100;
  }

  final price = s.row.priceUsdPerKg;
  return DietFood(
    key: s.key,
    name: s.food.name,
    maxGrams: s.row.gramsRemaining,
    costUsdPerG: price == null ? null : price / 1000,
    kcalPerG: perGram(NutrientKey.energy),
    proteinPerG: perGram(NutrientKey.protein),
    sodiumMgPerG: perGram(NutrientKey.sodium),
    fatPerG: perGram(NutrientKey.fat),
    isBeverage: s.food.isBeverage,
  );
}

/// Cheapest plan for what is missing today (or the whole day).
DietPlan planForToday(WidgetRef ref, {required bool wholeDay}) {
  final a = ref.read(currentAssumptionsProvider);
  final status = ref.read(energyStatusProvider);
  final gap = ref.read(todayGapProvider);
  final kcal = wholeDay ? (status?.targetKcal ?? 0) : (gap?.kcal ?? 0);
  final protein = wholeDay ? (status?.macros.proteinPlanG ?? 0) : (gap?.proteinG ?? 0);
  return planDiet(
    foods: [for (final s in ref.read(stockViewProvider)) dietFoodOf(s)],
    targets: DietTargets(
      kcalMin: kcal,
      proteinMinG: protein,
      sodiumMaxMg: a[A.sodiumLimitMg] + ref.read(sweatSodiumTodayProvider),
    ),
    params: DietParams.fromAssumptions(a),
  );
}
