import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/fichas/domain/token_model.dart';
import 'package:humanos/features/fichas/presentation/fichas_screen.dart';
import 'package:humanos/features/inicio/presentation/apps_page.dart';
import 'package:humanos/services/launcher.dart';
import 'package:humanos/services/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_launcher.dart';
import 'support/fixtures.dart';

// Invented rules, apps and minutes only.
const juego = InstalledApp(package: 'test.juego', label: 'Juego Prueba');

void main() {
  late UserDb db;
  late FakeLauncher launcher;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    launcher = FakeLauncher(installed: const [juego]);
    // A day with a close and 61 minutes of a game the user classed as leisure.
    await db.into(db.dayCloses).insert(DayClosesCompanion.insert(date: '2026-11-20', mood: 4, energy: 3, updatedAt: '2026-11-20T21:00:00'));
    await db.into(db.appClasses).insert(AppClassesCompanion.insert(package: 'test.juego', category: 'ocio', updatedAt: '2026-11-20'));
    await db.into(db.appUsageDays).insert(AppUsageDaysCompanion.insert(date: '2026-11-20', package: 'test.juego', minutes: 61));
    await db.into(db.tokenEarnRules).insert(TokenEarnRulesCompanion.insert(source: 'cierre', tokens: 2));
    await db.into(db.tokenCostRules).insert(TokenCostRulesCompanion.insert(category: 'ocio', tokens: 1, perMinutes: 30));
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, DateTime now, {Widget child = const FichasScreen()}) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      extra: [launcherProvider.overrideWithValue(launcher)],
      child: child,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('off by default: leisure without tokens records nothing', (tester) async {
    await open(tester, DateTime(2026, 11, 20, 22));
    expect(find.text('APAGADAS'), findsOneWidget);
    expect(find.text('El ocio no tiene límite ni contador.'), findsOneWidget);
    expect(await db.select(db.tokenDays).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('turning on waits its delay; then habits earn and leisure spends; off keeps the history',
      (tester) async {
    await open(tester, DateTime(2026, 11, 19, 21));
    await tester.tap(find.text('PEDIR ENCENDER'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await SettingsRepository(db).get(TokenKey.pending), '1');
    expect(find.text('APAGADAS'), findsOneWidget, reason: 'the change waits 24 h');
    expect(find.textContaining('Cambio pedido: encender'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    // A day later the change is in force and the day is counted.
    await open(tester, DateTime(2026, 11, 20, 22));
    expect(find.text('ENCENDIDAS'), findsOneWidget);
    expect(await SettingsRepository(db).get(TokenKey.since), '2026-11-20');
    final day = {for (final r in await db.select(db.tokenDays).get()) r.source: (r.earned, r.spent)};
    expect(day, {'cierre': (2, 0), 'gasto:ocio': (0, 3)});
    expect(find.text('-1 fichas'), findsOneWidget);

    await tester.tap(find.text('PEDIR APAGAR'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, DateTime(2026, 11, 21, 23));
    expect(find.text('APAGADAS'), findsOneWidget);
    expect(await db.select(db.tokenDays).get(), hasLength(2), reason: 'turning off never deletes the history');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no tokens left: opening priced leisure asks, never blocks', (tester) async {
    final settings = SettingsRepository(db);
    await settings.set(TokenKey.enabled, '1');
    await settings.set(TokenKey.since, '2026-11-20');
    await open(tester, DateTime(2026, 11, 20, 22), child: const AppsPage());
    await tester.tap(find.text('Juego Prueba'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('SIN FICHAS'), findsOneWidget);
    await tester.tap(find.text('NO ABRIR'));
    await tester.pumpAndSettle();
    expect(launcher.launched, isEmpty);

    await tester.tap(find.text('Juego Prueba'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('ABRIR IGUAL'));
    await tester.pumpAndSettle();
    expect(launcher.launched, ['test.juego']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
