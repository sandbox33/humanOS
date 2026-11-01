import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/finanzas/data/finance_repository.dart';
import 'package:humanos/features/finanzas/domain/finance_model.dart';
import 'package:humanos/features/finanzas/presentation/finanzas_screen.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

// Invented amounts only.
void main() {
  late UserDb db;
  late FinanceRepository repo;
  final now = DateTime(2026, 10, 28, 19);

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    repo = FinanceRepository(db, () => now);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, {Widget child = const FinanzasScreen()}) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(db: db, now: now, child: child));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('nothing is preloaded and the disclaimer is always shown', (tester) async {
    await open(tester);
    expect(find.text(advisorDisclaimerEs), findsOneWidget);
    expect(find.textContaining('Sin metas todavía'), findsOneWidget);
    expect(await db.select(db.expenseCategories).get(), isEmpty);
    expect(await db.select(db.goals).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an expense is logged with the user category in cents', (tester) async {
    await open(tester);
    await tester.tap(find.text('REGISTRAR GASTO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '3,50');
    await tester.enterText(find.widgetWithText(TextField, 'Categoría (tuya)'), 'Pasaje');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('GUARDAR GASTO'));
    await tester.pumpAndSettle();

    final e = await db.select(db.expenses).getSingle();
    expect(e.amountCents, 350);
    expect(e.category, 'Pasaje');
    expect(e.date, '2026-10-28');
    expect((await db.select(db.expenseCategories).getSingle()).label, 'Pasaje');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unplanned purchase above the threshold suggests waiting; the user decides', (tester) async {
    await SettingsRepository(db).set(FinanceKey.pauseThresholdCents, '2000');
    await open(tester);
    await tester.tap(find.text('REGISTRAR GASTO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto'), '25');
    await tester.enterText(find.widgetWithText(TextField, 'Categoría (tuya)'), 'Ropa');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('GUARDAR GASTO'));
    await tester.pumpAndSettle();
    expect(find.text('¿ESPERAR ANTES DE COMPRAR?'), findsOneWidget);
    await tester.tap(find.text('ESPERAR'));
    await tester.pumpAndSettle();

    expect(await db.select(db.expenses).get(), isEmpty, reason: 'nothing is spent while waiting');
    final pause = await db.select(db.purchasePauses).getSingle();
    expect(pause.amountCents, 2500);
    expect(pause.untilTs, '2026-10-29T19:00:00');
    expect(find.text('> COMPRAS EN ESPERA'), findsOneWidget);
    expect(find.textContaining('Espera hasta 19:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('goals with sub-goals: the parent adds up its parts and completes with the real cost', (tester) async {
    final parent = await repo.addGoal(title: 'Equipo');
    final a = await repo.addGoal(title: 'Parte A', targetCents: 30000, parentId: parent);
    await repo.addGoal(title: 'Parte B', targetCents: 20000, parentId: parent);
    await repo.addSaved(a, 10000);
    await open(tester);
    expect(find.text('100,00 USD de 500,00 USD'), findsOneWidget);
    expect(find.text('100,00 USD de 300,00 USD'), findsOneWidget);

    await repo.complete(a, actualCents: 28000);
    await settle(tester);
    expect(find.text('COMPLETADAS'), findsOneWidget);
    expect(find.text('estimado 300,00 USD · real 280,00 USD'), findsOneWidget);
    final row = await (db.select(db.goals)..where((t) => t.id.equals(a))).getSingle();
    expect(row.completedAt, '2026-10-28T19:00:00');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('advice shows its numbers and rule, and a dismissed rule does not come back', (tester) async {
    await db.into(db.workEntries).insert(WorkEntriesCompanion.insert(
          date: '2026-10-27',
          label: 'Prueba',
          kind: 'eventual',
          minutes: 600,
          earnedCents: const Value(10000),
          createdAt: '2026-10-27T18:00:00',
        ));
    await repo.addExpense(date: DateTime(2026, 10, 27), category: 'Comida', amountCents: 2500);
    await open(tester);
    expect(find.textContaining('Esta semana guardaste el 75,0 %'), findsOneWidget);

    final stored = await SettingsRepository(db).get(FinanceKey.adviceDay);
    expect(stored, startsWith('2026-10-28:tasa_ahorro'));

    await tester.tap(find.text('NO MOSTRAR MÁS ESTA REGLA').first);
    await settle(tester);
    expect(find.textContaining('Esta semana guardaste'), findsNothing);
    expect(await SettingsRepository(db).get(FinanceKey.dismissedRules), contains('tasa_ahorro'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('after an income the user can set the configured share aside in one tap', (tester) async {
    await SettingsRepository(db).set(FinanceKey.splitPercent, '10');
    final goal = await repo.addGoal(title: 'Meta', targetCents: 50000);
    await open(
      tester,
      child: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(onPressed: () => offerIncomeSplit(context, ref, 4550), child: const Text('INGRESO')),
        ),
      ),
    );
    await tester.tap(find.text('INGRESO'));
    await tester.pumpAndSettle();
    expect(find.textContaining('¿Separas 4,55 USD (10 %)'), findsOneWidget);
    await tester.tap(find.text('SEPARAR'));
    await tester.pumpAndSettle();
    final row = await (db.select(db.goals)..where((t) => t.id.equals(goal))).getSingle();
    expect(row.savedCents, 455);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
