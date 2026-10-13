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

  testWidgets('the app opens on ESTADO with the Spanish bottom navigation', (tester) async {
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

    for (final label in ['ESTADO', 'REGISTRO', 'HEAVY', 'TURNO', 'MÁS']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('PESARME'), findsWidgets);
    expect(find.textContaining('Registra tu peso'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    for (final label in ['DESPENSA', 'ÍNDICE', 'HÁBITOS', 'AJUSTES']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
