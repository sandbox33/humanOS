import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/ajustes/presentation/food_goals_panel.dart';
import 'package:humanos/features/despensa/domain/meal_day.dart';
import 'package:humanos/features/despensa/presentation/receipt_page.dart';
import 'package:humanos/features/estado/domain/targets.dart';
import 'package:humanos/features/inicio/data/schedule_repository.dart';
import 'package:humanos/features/inicio/presentation/inicio_screen.dart';
import 'package:humanos/services/services.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_launcher.dart';
import 'support/fixtures.dart';

// Invented values only (fixture foods: 4 black beans, 5 precooked corn
// flour, barcode product: canned tuna).
const tuna = '7861234567890';

void main() {
  late UserDb db;
  final now = DateTime(2026, 11, 3, 13, 5);
  const today = '2026-11-03';

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(date: today, weightKg: const Value(70)));
    await SettingsRepository(db).set(SettingKey.kcalTargetFixed, '2000');
    final schedule = ScheduleRepository(db, () => now);
    await schedule.addBlock(kind: BlockKind.almuerzo, startClock: '13:00', daysMask: 0x7F);
    await schedule.addBlock(kind: BlockKind.mediaTarde, startClock: '18:00', daysMask: 0x7F);
  });
  tearDown(() => db.close());

  Future<int> stock({int? foodId, String? barcode, required String purchasedOn}) => db.into(db.pantryItems).insert(
        PantryItemsCompanion.insert(
          gramsRemaining: 1000,
          foodId: Value(foodId),
          barcode: Value(barcode),
          purchasedOn: Value(purchasedOn),
        ),
      );

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: [
      userDbProvider.overrideWithValue(db),
      referenceDbProvider.overrideWithValue(fixtureReferenceDb()),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    c.listen(mealDayPlanProvider, (_, _) {});
    c.listen(energyStatusProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return c;
  }

  test('a fixed energy target wins over the estimate', () async {
    final c = await container();
    final status = c.read(energyStatusProvider)!;
    expect(status.targetKcal, 2000);
    expect(status.modeEs, contains('META FIJA'));
  });

  test('meals come from the schedule; lunch boxes take only portable food; no fridge keeps fresh food to its day',
      () async {
    final beans = await stock(foodId: 4, purchasedOn: today);
    final flour = await stock(foodId: 5, purchasedOn: today);
    final oldTuna = await stock(barcode: tuna, purchasedOn: '2026-11-02');
    final t = DateTime(2026, 11, 3);
    await setHandling(db, 'f5', needsCold: false, portable: true, needsCooking: false, now: t);
    await setHandling(db, 'f4', needsCold: false, portable: false, needsCooking: false, now: t);
    await setHandling(db, 'b$tuna', needsCold: true, portable: false, needsCooking: false, now: t);

    final c = await container();
    final plans = c.read(mealDayPlanProvider);
    expect(plans.map((p) => p.slot.block), [MealBlock.lunch, MealBlock.afternoon]);
    expect(plans.first.slot.contextEs, 'Almuerzo');

    final lunch = plans.first.grams.keys.toSet();
    final afternoon = plans.last.grams.keys.toSet();
    expect(afternoon.difference({'p$flour'}), isEmpty, reason: 'only the portable flour travels');
    expect(lunch, isNot(contains('p$oldTuna')), reason: 'without a fridge, fresh food bought yesterday is out');
    expect(lunch.union(afternoon), isNot(contains('p$oldTuna')));
    expect(beans, isPositive);

    await SettingsRepository(db).set(FoodKey.hasFridge, '1');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final withFridge = c.read(mealDayPlanProvider);
    expect(withFridge.last.grams.keys.toSet().difference({'p$flour'}), isEmpty);
  });

  testWidgets('METAS DE COMIDA: fixed energy and protein per kg, each with RESTABLECER', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(db: db, now: now, child: const Scaffold(body: SingleChildScrollView(child: FoodGoalsPanel()))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Meta fija tuya: 2000 kcal'), findsOneWidget);

    await tester.tap(find.text('RESTABLECER AL CÁLCULO DE LA APP'));
    await tester.pumpAndSettle();
    expect(await SettingsRepository(db).get(SettingKey.kcalTargetFixed), isNull);
    expect(find.textContaining('Calculada por la app'), findsOneWidget);

    await tester.tap(find.text('PROTEÍNA POR KG'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1,7');
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    final row = await (db.select(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg))).getSingle();
    expect(row.value, 1.7);
    await tester.tap(find.text('RESTABLECER A 2,0'));
    await tester.pumpAndSettle();
    final back = await (db.select(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg))).getSingle();
    expect(back.value, 2.0);

    await tester.tap(find.text('TENGO REFRIGERADORA'));
    await tester.pumpAndSettle();
    expect(await SettingsRepository(db).get(FoodKey.hasFridge), '1');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('receipt lines: remembered links, grams asked, price per kg stored, unlinked lines left out',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await db.into(db.receiptLinks).insert(ReceiptLinksCompanion.insert(
          lineKey: receiptKey('FREJOL NEGRO'),
          foodId: const Value(4),
          updatedAt: '2026-11-01T10:00:00',
        ));
    final purchase = await db.into(db.purchases).insert(PurchasesCompanion.insert(date: today));
    final receipt = parseReceipt('FREJOL NEGRO 2KG   4.00\nCOSA RARA   1.00\nTOTAL   5.00');
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      reference: fixtureReferenceDb(),
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ReceiptLinesPage(purchaseId: purchase, receipt: receipt),
            )),
            child: const Text('ABRIR'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    expect(find.text('Frijol negro cocido'), findsOneWidget, reason: 'linked once, remembered');
    expect(find.text('sin vincular'), findsOneWidget);

    await tester.tap(find.text('AÑADIR A LA DESPENSA'));
    await tester.pumpAndSettle();
    final item = await db.select(db.pantryItems).getSingle();
    expect(item.foodId, 4);
    expect(item.gramsRemaining, 2000);
    expect(item.priceCentsPerKg, 200);
    expect(item.purchasedOn, today);
    expect(item.purchaseId, purchase);
  });

  testWidgets('COMER AHORA logs the current meal in one tap and takes it from the pantry', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await SettingsRepository(db).set(FoodKey.hasFridge, '1');
    await stock(foodId: 5, purchasedOn: today);
    await stock(barcode: tuna, purchasedOn: today);
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      reference: fixtureReferenceDb(),
      extra: [launcherProvider.overrideWithValue(FakeLauncher())],
      child: const InicioScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('> COMER AHORA · ALMUERZO'), findsOneWidget);

    await tester.tap(find.text('LO COMÍ'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    final items = await db.select(db.mealItems).get();
    expect(items, isNotEmpty);
    final meal = await db.select(db.meals).getSingle();
    expect(meal.block, MealBlock.lunch.code);
    expect(meal.date, today);
    final left = {for (final p in await db.select(db.pantryItems).get()) p.id: p.gramsRemaining};
    for (final i in items) {
      expect(left[i.pantryItemId], closeTo(1000 - i.grams, 1e-9));
    }
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
