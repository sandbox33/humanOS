import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/despensa/data/pantry_repository.dart';
import 'package:humanos/features/registro/data/meals_repository.dart';
import 'package:humanos/features/registro/presentation/add_item_sheet.dart';
import 'package:humanos_core/humanos_core.dart';

import 'support/fixtures.dart';

void main() {
  late UserDb db;
  late MealsRepository meals;
  late PantryRepository pantry;

  setUp(() {
    db = memoryUserDb();
    meals = MealsRepository(db);
    pantry = PantryRepository(db);
  });
  tearDown(() => db.close());

  Future<double> remaining(int id) async =>
      (await (db.select(db.pantryItems)..where((t) => t.id.equals(id))).getSingle()).gramsRemaining;

  test('logging from the pantry decrements grams_remaining', () async {
    final id = await pantry.addItem(foodId: 4, grams: 500);
    final result = await meals.addItem(
      date: '2026-10-13',
      block: MealBlock.lunch,
      grams: 200,
      foodId: 4,
      pantryItemId: id,
    );
    expect(result.insufficient, isFalse);
    expect(await remaining(id), 300);
    expect(stockMessage(result), contains('Quedan 300 g'));
  });

  test('insufficient stock warns but never blocks the log', () async {
    final id = await pantry.addItem(foodId: 4, grams: 100);
    final result = await meals.addItem(
      date: '2026-10-13',
      block: MealBlock.dinner,
      grams: 150,
      foodId: 4,
      pantryItemId: id,
    );
    expect(result.insufficient, isTrue);
    expect(await remaining(id), 0);
    expect(stockMessage(result), contains('Stock insuficiente'));
    final logged = await meals.dayEntries('2026-10-13');
    expect(logged.single.items.single.grams, 150);
  });

  test('removing or editing an item gives the grams back to the pantry', () async {
    final id = await pantry.addItem(foodId: 4, grams: 400);
    await meals.addItem(date: '2026-10-13', block: MealBlock.lunch, grams: 100, foodId: 4, pantryItemId: id);
    var item = (await meals.dayEntries('2026-10-13')).single.items.single;
    await meals.updateItemGrams(item, 150);
    expect(await remaining(id), 250);
    item = (await meals.dayEntries('2026-10-13')).single.items.single;
    await meals.removeItem(item);
    expect(await remaining(id), 400);
    expect(await meals.dayEntries('2026-10-13'), isEmpty);
  });

  test('meal items store ids and grams only', () async {
    await meals.addItem(date: '2026-10-13', block: MealBlock.breakfast, grams: 120, recipeId: 1);
    final item = (await meals.dayEntries('2026-10-13')).single.items.single;
    expect(item.recipeId, 1);
    expect(item.grams, 120);
  });

  test('repeat the previous day and templates', () async {
    await meals.addItem(date: '2026-10-12', block: MealBlock.lunch, grams: 80, foodId: 5);
    expect(await meals.repeatDay(from: '2026-10-12', to: '2026-10-13'), 1);
    final template = await db.into(db.mealTemplates).insert(MealTemplatesCompanion.insert(nameEs: 'Prueba'));
    final items = (await meals.dayEntries('2026-10-13')).single.items;
    expect(await meals.saveAsTemplate(template, items), 1);
    expect(await meals.applyTemplate(template, '2026-10-14', MealBlock.dinner), 1);
  });
}
