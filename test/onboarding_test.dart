import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/app.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

void main() {
  late UserDb db;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
  });
  tearDown(() => db.close());

  testWidgets('a new install asks for the profile and then opens the app', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        userDbProvider.overrideWithValue(db),
        referenceDbProvider.overrideWithValue(fixtureReferenceDb()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 9)),
      ],
      child: const HumanOsApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('TU PERFIL'), findsOneWidget);

    Future<void> type(String label, String value) async {
      await tester.enterText(find.widgetWithText(TextFormField, label), value);
    }

    await type('Nombre o apodo', 'Prueba');
    await type('Año de nacimiento', '1995');
    await type('Estatura', '170');
    await type('Peso de hoy', '68,5');
    await type('Peso meta', '72');
    await tester.ensureVisible(find.text('GUARDAR Y ENTRAR'));
    await tester.tap(find.text('GUARDAR Y ENTRAR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final profile = await db.select(db.profile).getSingle();
    expect(profile.name, 'Prueba');
    expect(profile.heightCm, 170);
    final weight = await db.select(db.bodyMetrics).getSingle();
    expect(weight.weightKg, 68.5);
    expect(weight.date, '2026-10-13');

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ESTADO'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid numbers are refused without saving', (tester) async {
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        userDbProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 9)),
      ],
      child: const HumanOsApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre o apodo'), 'Prueba');
    await tester.enterText(find.widgetWithText(TextFormField, 'Estatura'), '20');
    await tester.ensureVisible(find.text('GUARDAR Y ENTRAR'));
    await tester.tap(find.text('GUARDAR Y ENTRAR'));
    await tester.pump();
    expect(find.text('Entre 120 y 230 cm'), findsOneWidget);
    expect(await db.select(db.profile).getSingleOrNull(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
