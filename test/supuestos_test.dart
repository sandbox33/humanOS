import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/ajustes/presentation/supuestos_page.dart';
import 'package:humanos_core/humanos_core.dart';
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

  Future<double> stored() async =>
      (await (db.select(db.assumptionRows)..where((t) => t.key.equals(A.proteinGPerKg))).getSingle())
          .value;

  testWidgets('SUPUESTOS edits are validated against the catalogue range', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(db: db, child: const SupuestosPage()));
    await tester.pump();

    final title = find.text('Proteína diaria por kg');
    await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);

    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fuera de rango'), findsOneWidget);
    expect(await stored(), 1.8);

    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2,0');
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    expect(await stored(), 2.0);
    expect(find.textContaining('RESTAURAR'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
