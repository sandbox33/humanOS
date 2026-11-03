import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/inicio/data/schedule_repository.dart';
import 'package:humanos/features/inicio/domain/schedule_model.dart';
import 'package:humanos/features/inicio/presentation/apps_page.dart';
import 'package:humanos/features/inicio/presentation/inicio_screen.dart';
import 'package:humanos/features/inicio/presentation/safe_app_list.dart';
import 'package:humanos/services/launcher.dart';
import 'package:humanos/services/services.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_launcher.dart';
import 'support/fixtures.dart';

// Invented apps and the brief's example day, only as test data.
final apps = [
  const InstalledApp(package: 'test.mensajes', label: 'Mensajes Prueba'),
  const InstalledApp(package: 'test.mapas', label: 'Mapas Prueba'),
];

void main() {
  late UserDb db;
  late FakeLauncher launcher;
  late ScheduleRepository repo;
  final now = DateTime(2026, 11, 3, 8, 10); // Tuesday

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    launcher = FakeLauncher(installed: apps);
    repo = ScheduleRepository(db, () => now);
  });
  tearDown(() => db.close());

  Future<void> exampleDay() async {
    const weekdays = 0x1F, everyDay = 0x7F;
    await repo.addBlock(kind: BlockKind.desayuno, startClock: '05:00', daysMask: everyDay, alarm: true);
    await repo.addBlock(kind: BlockKind.trabajo, startClock: '07:00', durationMin: 540, daysMask: weekdays);
    await repo.addBlock(kind: BlockKind.mediaManana, startClock: '08:00', daysMask: everyDay);
    await repo.addBlock(kind: BlockKind.almuerzo, startClock: '13:00', daysMask: everyDay);
    await repo.addBlock(kind: BlockKind.mediaTarde, startClock: '18:00', daysMask: everyDay);
    await repo.addBlock(kind: BlockKind.proyecto, startClock: '19:00', daysMask: everyDay);
    await repo.addBlock(kind: BlockKind.dormir, startClock: '21:00', daysMask: everyDay, alarm: true);
  }

  Future<void> open(WidgetTester tester, {Widget child = const InicioScreen()}) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      extra: [launcherProvider.overrideWithValue(launcher)],
      child: child,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without a template the home screen invites to build the day; nothing is preset', (tester) async {
    await open(tester);
    expect(find.text('08:10'), findsOneWidget);
    expect(find.text('ARMAR MI HORARIO'), findsOneWidget);
    expect(await db.select(db.scheduleBlocks).get(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the current block in large type with its countdown, and the next one', (tester) async {
    await exampleDay();
    await open(tester);
    expect(find.text('MEDIA MAÑANA'), findsOneWidget);
    expect(find.text('Quedan 20 min'), findsOneWidget);
    expect(find.text('Sigue: Almuerzo'), findsOneWidget);
    expect(find.text('a las 13:00 · en 4 h 50 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('holding the clock 5 s opens the home-screen choice; a shorter hold does not', (tester) async {
    await open(tester);
    final clock = find.text('08:10');
    var gesture = await tester.startGesture(tester.getCenter(clock));
    await tester.pump(const Duration(seconds: 4));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(launcher.homeSettingsOpened, 0);

    gesture = await tester.startGesture(tester.getCenter(clock));
    await tester.pump(const Duration(seconds: 5));
    await gesture.up();
    expect(launcher.homeSettingsOpened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the phone is always there; the user pins the apps they want', (tester) async {
    await open(tester);
    await tester.tap(find.text('TELÉFONO'));
    expect(launcher.dialerOpened, 1);
    expect(find.text('MENSAJES PRUEBA'), findsNothing);

    await tester.tap(find.text('TODAS LAS APPS'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Mensajes Prueba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fijar en INICIO'));
    await tester.pumpAndSettle();
    expect(await SettingsRepository(db).get(LauncherKey.pinned), 'test.mensajes');

    await tester.tap(find.text('Mapas Prueba'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(launcher.launched, ['test.mapas']);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MENSAJES PRUEBA'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(launcher.launched.last, 'test.mensajes');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('searching apps ignores accents and case', (tester) async {
    await open(tester, child: const AppsPage());
    await tester.enterText(find.byType(TextField), 'MAPÁS');
    await tester.pump();
    expect(find.text('Mapas Prueba'), findsOneWidget);
    expect(find.text('Mensajes Prueba'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overtime today recalculates the day; the template is untouched', (tester) async {
    await exampleDay();
    final work = (await db.select(db.scheduleBlocks).get()).firstWhere((b) => b.kind == 'trabajo');
    await repo.addAdjustment(date: now, action: AdjustAction.extender, blockId: work.id, endClock: '20:00');
    await open(tester);
    await tester.tap(find.text('AJUSTAR HOY'));
    await tester.pumpAndSettle();
    expect(find.text('07:00–20:00 · Trabajo'), findsOneWidget);
    // The project is pushed after work and shortened up to sleep.
    expect(find.text('20:00–21:00 · Proyecto'), findsOneWidget);
    expect(find.text('ACORTADO'), findsOneWidget);
    expect(find.text('21:00–05:00 · Dormir'), findsOneWidget);

    await tester.tap(find.text('VOLVER AL HORARIO DE SIEMPRE'));
    await tester.pumpAndSettle();
    expect(find.text('07:00–16:00 · Trabajo'), findsOneWidget);
    expect(await db.select(db.scheduleAdjustments).get(), isEmpty);
    expect((await db.select(db.scheduleBlocks).get()).firstWhere((b) => b.id == work.id).durationMin, 540);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('block alarms: template weekdays, and a moved block rings today at its new time only', () {
    final templates = [
      const BlockTemplate(id: 1, kind: BlockKind.desayuno, startMin: 300, daysMask: 0x7F, alarm: true),
      const BlockTemplate(id: 2, kind: BlockKind.dormir, startMin: 1260, daysMask: 0x7F, alarm: true),
      const BlockTemplate(id: 3, kind: BlockKind.almuerzo, startMin: 780, daysMask: 0x7F),
    ];
    final tuesday = DateTime(2026, 11, 3);
    final plan = planDay(
      templates: templates,
      weekday: tuesday.weekday,
      adjustments: const [DayAdjustment(action: AdjustAction.mover, blockId: 2, startMin: 1320)],
    );
    final alarms = blockAlarms(templates: templates, today: plan, date: tuesday, snoozeMinutes: 5);
    final byId = {for (final a in alarms) a.id: a};
    expect(byId.keys.toSet(), {100001, 100002, 200002});
    expect(byId[100001]!.daysMask, 0x7F);
    expect(byId[100002]!.daysMask, 0x7F & ~0x02, reason: 'no template ring on Tuesday');
    expect(byId[200002]!.daysMask, 0x02);
    expect(byId[200002]!.minuteOfDay, 1320);
    expect(alarms.any((a) => a.label == 'Almuerzo'), isFalse, reason: 'only blocks marked with an alarm');
  });

  testWidgets('safe mode: a plain list of apps, the phone and the way out', (tester) async {
    await tester.pumpWidget(SafeAppList(launcher: launcher, reason: 'Prueba'));
    await tester.pump();
    await tester.pump();
    expect(find.text('HUMANOS · MODO SEGURO'), findsOneWidget);
    await tester.tap(find.text('Mapas Prueba'));
    await tester.tap(find.text('> TELÉFONO'));
    await tester.tap(find.text('> ELEGIR OTRA PANTALLA DE INICIO'));
    expect(launcher.launched, ['test.mapas']);
    expect(launcher.dialerOpened, 1);
    expect(launcher.homeSettingsOpened, 1);
  });
}
