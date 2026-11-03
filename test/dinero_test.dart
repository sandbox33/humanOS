import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/finanzas/data/finance_repository.dart';
import 'package:humanos/features/finanzas/domain/finance_model.dart';
import 'package:humanos/features/finanzas/domain/pay_model.dart';
import 'package:humanos/features/finanzas/presentation/pay_panels.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

// Invented amounts only.
void main() {
  late UserDb db;
  final now = DateTime(2026, 11, 15, 19);

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(db: db, now: now, child: Scaffold(body: SingleChildScrollView(child: child))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a pay with its overtime part gives the real value of each hour', (tester) async {
    await open(tester, const PayPanel());
    expect(find.text('sin dato'), findsWidgets);
    await tester.tap(find.text('REGISTRAR PAGO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Monto cobrado'), '250');
    await tester.enterText(find.widgetWithText(TextField, 'Horas normales'), '40');
    await tester.enterText(find.widgetWithText(TextField, 'Horas extra'), '5');
    await tester.enterText(find.widgetWithText(TextField, 'Parte de horas extra (si el pago la muestra)'), '50');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('GUARDAR PAGO'));
    await tester.pumpAndSettle();

    final row = await db.select(db.payWeeks).getSingle();
    expect(row.amountCents, 25000);
    expect(row.normalMinutes, 2400);
    expect(row.overtimeMinutes, 300);
    expect(row.overtimeCents, 5000);
    expect(find.text('5,00 USD/h'), findsOneWidget);
    expect(find.text('10,00 USD/h'), findsOneWidget);
    expect(find.text('desglose del pago'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cash counted, minus what was spent after it: days it lasts and the next income warning',
      (tester) async {
    final finance = FinanceRepository(db, () => DateTime(2026, 11, 14, 12));
    for (var d = 1; d <= 14; d++) {
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            date: '2026-11-${d.toString().padLeft(2, '0')}',
            category: 'Prueba',
            amountCents: 500,
            createdAt: '2026-11-${d.toString().padLeft(2, '0')}T12:00:00',
          ));
    }
    await db.into(db.cashCounts).insert(CashCountsCompanion.insert(countedAt: '2026-11-14T08:00:00', cents: 5000));
    await finance.addExpense(date: DateTime(2026, 11, 14), category: 'Prueba', amountCents: 500);
    // The day-14 expense above was logged at 12:00, after the count, as well.
    await SettingsRepository(db).set(PayKey.nextIncome, '2026-11-30');
    await open(tester, const CashPanel());
    expect(find.text('40,00 USD'), findsOneWidget, reason: '50 − 5 − 5 logged after the count');
    expect(find.text('5,36 USD'), findsOneWidget, reason: '75 USD in the 14 days before today');
    expect(find.text('7 días'), findsOneWidget);
    expect(find.textContaining('no llega a tu próximo ingreso'), findsOneWidget);

    await tester.tap(find.text('RESTABLECER FECHA'));
    await tester.pumpAndSettle();
    expect(await SettingsRepository(db).get(PayKey.nextIncome), isNull);
    expect(find.textContaining('no llega'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GASTÉ: amount and one tap on a category', (tester) async {
    await FinanceRepository(db, () => now).ensureCategory('Pasaje');
    await open(tester, Builder(
      builder: (context) => TextButton(onPressed: () => QuickExpenseSheet.show(context), child: const Text('ABRIR')),
    ));
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0,75');
    await tester.tap(find.text('Pasaje'));
    await tester.pumpAndSettle();
    final e = await db.select(db.expenses).getSingle();
    expect(e.amountCents, 75);
    expect(e.category, 'Pasaje');
    expect(e.date, '2026-11-15');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('income: recorded pay replaces the work entries of its week, never both', () async {
    await db.into(db.workEntries).insert(WorkEntriesCompanion.insert(
          date: '2026-11-10',
          label: 'Prueba',
          kind: 'eventual',
          minutes: 480,
          earnedCents: const Value(4000),
          createdAt: '2026-11-10T18:00:00',
        ));
    await db.into(db.workEntries).insert(WorkEntriesCompanion.insert(
          date: '2026-11-03',
          label: 'Prueba',
          kind: 'eventual',
          minutes: 480,
          earnedCents: const Value(3000),
          createdAt: '2026-11-03T18:00:00',
        ));
    await db.into(db.payWeeks).insert(PayWeeksCompanion.insert(
          paidOn: '2026-11-14',
          amountCents: 21000,
          normalMinutes: 2400,
          overtimeMinutes: 0,
          createdAt: '2026-11-14T18:00:00',
        ));
    final c = ProviderContainer(overrides: [
      userDbProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    c.listen(incomeProvider, (_, _) {});
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final income = c.read(incomeProvider);
    expect(income.map((m) => m.cents).toList()..sort(), [3000, 21000]);
  });
}
