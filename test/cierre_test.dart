import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/cierre/domain/close_model.dart';
import 'package:humanos/features/cierre/presentation/cierre_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

// Invented question, phrase and categories, only as test data.
void main() {
  late UserDb db;
  final now = DateTime(2026, 11, 20, 21, 30);

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(db: db, now: now, child: const CierreScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('nothing preset: no question, no categories; mood and energy are required', (tester) async {
    await open(tester);
    expect(find.textContaining('Escribe la pregunta'), findsOneWidget);
    expect(find.textContaining('Crea tus categorías'), findsOneWidget);
    await tester.tap(find.text('CERRAR EL DÍA'));
    await tester.pump();
    expect(find.text('Marca tu ánimo y tu energía.'), findsOneWidget);
    expect(await db.select(db.dayCloses).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a full close: scales, minutes by category, the question and the saved phrase', (tester) async {
    final settings = SettingsRepository(db);
    await settings.set(CloseKey.question, 'Pregunta de prueba');
    await settings.set(CloseKey.phrase, 'Frase de prueba');
    final category = await CloseRepository(db, () => now).addCategory('Categoría A');
    await open(tester);

    await tester.tap(find.text('4').first);
    await tester.tap(find.text('2').last);
    await tester.tap(find.byTooltip('Más 15 min con Categoría A'));
    await tester.tap(find.byTooltip('Más 15 min con Categoría A'));
    await tester.pump();
    expect(find.text('30 min'), findsOneWidget);
    expect(find.textContaining('Frase de prueba'), findsNothing);
    await tester.tap(find.text('SÍ'));
    await tester.pump();
    expect(find.text('Para la próxima vez: «Frase de prueba»'), findsOneWidget);
    await tester.tap(find.text('CERRAR EL DÍA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final row = await db.select(db.dayCloses).getSingle();
    expect(row.date, '2026-11-20');
    expect(row.mood, 4);
    expect(row.energy, 2);
    expect(row.honestyYes, isTrue);
    final minutes = await db.select(db.dayCloseInteractions).getSingle();
    expect(minutes.categoryId, category);
    expect(minutes.minutes, 30);
    await tester.pumpWidget(const SizedBox.shrink());

    // Opening again the same day shows what was saved.
    await open(tester);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('GUARDADO · CAMBIAR'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trends only after the minimum days, with how many days and correlation is not cause', (tester) async {
    for (var d = 1; d <= 13; d++) {
      await db.into(db.dayCloses).insert(DayClosesCompanion.insert(
            date: '2026-11-${d.toString().padLeft(2, '0')}',
            mood: 3,
            energy: 3,
            updatedAt: '2026-11-${d.toString().padLeft(2, '0')}T21:00:00',
          ));
    }
    await open(tester);
    expect(find.text('Aparecen con 14 días cerrados. Llevas 13.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await db.into(db.dayCloses).insert(DayClosesCompanion.insert(date: '2026-11-14', mood: 5, energy: 4, updatedAt: '2026-11-14T21:00:00'));
    await open(tester);
    expect(find.text('Días que se usan'), findsOneWidget);
    expect(find.text('14'), findsWidgets);
    expect(find.textContaining('Correlación no es causa'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
