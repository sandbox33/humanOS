import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/inicio/data/schedule_repository.dart';
import 'package:humanos/features/inicio/presentation/apps_page.dart';
import 'package:humanos/features/pantalla/domain/screen_model.dart';
import 'package:humanos/features/pantalla/presentation/pantalla_screen.dart';
import 'package:humanos/services/launcher.dart';
import 'package:humanos/services/services.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_launcher.dart';
import 'support/fake_screen_time.dart';
import 'support/fixtures.dart';

// Invented apps and events only.
const juego = InstalledApp(package: 'test.juego', label: 'Juego Prueba');
const notas = InstalledApp(package: 'test.notas', label: 'Notas Prueba');
const red = InstalledApp(package: 'test.red', label: 'Red Prueba');

UsageEvent on(String p, DateTime at) => UsageEvent(package: p, type: UsageEventType.resumed, at: at);
UsageEvent off(String p, DateTime at) => UsageEvent(package: p, type: UsageEventType.paused, at: at);

void main() {
  late UserDb db;
  late FakeLauncher launcher;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    launcher = FakeLauncher(installed: const [juego, notas, red]);
  });
  tearDown(() => db.close());

  final usage = FakeScreenTime(
    usage: [
      // Yesterday (history the phone still keeps).
      on('test.juego', DateTime(2026, 11, 2, 20)),
      off('test.juego', DateTime(2026, 11, 2, 21)),
      // Today.
      on('test.juego', DateTime(2026, 11, 3, 5, 10)),
      off('test.juego', DateTime(2026, 11, 3, 5, 40)),
      on('test.notas', DateTime(2026, 11, 3, 8)),
      off('test.notas', DateTime(2026, 11, 3, 8, 45)),
    ],
    declared: const {'test.juego': 0, 'test.notas': 7, 'test.red': 4},
  );

  Future<void> open(WidgetTester tester, DateTime now, Widget child, {FakeScreenTime? source}) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      extra: [
        launcherProvider.overrideWithValue(launcher),
        screenTimeProvider.overrideWithValue(source ?? usage),
      ],
      child: child,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> morningBlock() async {
    final repo = ScheduleRepository(db, () => DateTime(2026, 11, 3));
    final id = await repo.addBlock(kind: BlockKind.otro, label: 'Mañana', startClock: '05:00', durationMin: 120, daysMask: 0x7F);
    final settings = SettingsRepository(db);
    await settings.set(ScreenKey.hideBlocks, '$id');
    await settings.set(ScreenKey.hideCategories, 'ocio,redes');
  }

  testWidgets('the first read imports the history the phone keeps; minutes per category and block', (tester) async {
    await morningBlock();
    await open(tester, DateTime(2026, 11, 3, 9), const PantallaScreen());

    final days = {for (final r in await db.select(db.appUsageDays).get()) '${r.date} ${r.package}': r.minutes};
    expect(days, {'2026-11-02 test.juego': 60, '2026-11-03 test.juego': 30, '2026-11-03 test.notas': 45});
    expect(await SettingsRepository(db).get(ScreenKey.syncedTo), '2026-11-03');

    expect(find.text('1 h 15 min'), findsWidgets, reason: "today's total, also in the 7-day trend");
    expect(find.text('Ocio'), findsWidgets);
    expect(find.text('Ocio 30 min'), findsOneWidget, reason: 'the morning block');
    expect(find.text('Categorías ocultas usadas en sus bloques'), findsOneWidget);
    expect(find.textContaining('(sugerida)'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the user corrects a suggested category', (tester) async {
    await open(tester, DateTime(2026, 11, 3, 9), const PantallaScreen());
    await tester.tap(find.text('Notas Prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Utilidades')));
    await tester.pumpAndSettle();
    final row = await db.select(db.appClasses).getSingle();
    expect(row.package, 'test.notas');
    expect(row.category, 'utilidades');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without the usage permission nothing is read and the screen says how to grant it', (tester) async {
    await open(tester, DateTime(2026, 11, 3, 9), const PantallaScreen(), source: FakeScreenTime(granted: false));
    expect(find.text('DAR ACCESO A USO'), findsOneWidget);
    expect(await db.select(db.appUsageDays).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a game is hidden at 05:30 and shown at 19:00', (tester) async {
    await morningBlock();
    await open(tester, DateTime(2026, 11, 3, 5, 30), const AppsPage());
    expect(find.text('Juego Prueba'), findsNothing);
    expect(find.text('Red Prueba'), findsNothing);
    expect(find.text('Notas Prueba'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await open(tester, DateTime(2026, 11, 3, 19), const AppsPage());
    expect(find.text('Juego Prueba'), findsOneWidget);
    await tester.tap(find.text('Juego Prueba'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(launcher.launched, ['test.juego'], reason: 'leisure opens straight away');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the optional 10 s pause before a social app, which can be cancelled', (tester) async {
    await SettingsRepository(db).setBool(ScreenKey.frictionSocial, true);
    await open(tester, DateTime(2026, 11, 3, 19), const AppsPage());
    await tester.tap(find.text('Red Prueba'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Se abre en 10 s.'), findsOneWidget);
    await tester.tap(find.text('NO ABRIR'));
    await tester.pumpAndSettle();
    expect(launcher.launched, isEmpty);

    await tester.tap(find.text('Red Prueba'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Se abre en 10 s.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(launcher.launched, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(launcher.launched, ['test.red']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
