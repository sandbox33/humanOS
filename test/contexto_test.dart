import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/alarmas/presentation/alarmas_screen.dart';
import 'package:humanos/features/contexto/domain/context_model.dart';
import 'package:humanos/features/contexto/presentation/contexto_screen.dart';
import 'package:humanos/services/device_context.dart';
import 'package:humanos/services/notifications.dart';
import 'package:humanos/services/services.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_device_context.dart';
import 'support/fixtures.dart';

void main() {
  late UserDb db;
  late FakeDeviceContext device;
  late SilentNotificationService scheduler;
  // A Friday; invented coordinates in open ocean.
  final now = DateTime(2026, 10, 30, 9);
  const point = GeoPoint(latitude: 10.5, longitude: -20.25, accuracyM: 12);

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    device = FakeDeviceContext(location: point);
    scheduler = SilentNotificationService();
  });
  tearDown(() => db.close());

  List<Override> overrides() => [
        deviceContextProvider.overrideWithValue(device),
        notificationServiceProvider.overrideWithValue(scheduler),
        alarmServiceProvider.overrideWithValue(scheduler),
      ];

  Future<int> zone(String name, String kind, {String status = 'activo', double lat = 10.5}) =>
      db.into(db.zones).insert(ZonesCompanion.insert(
            name: name,
            kind: kind,
            latitude: lat,
            longitude: -20.25,
            radiusM: 200,
            status: Value(status),
            createdAt: '2026-10-01T00:00:00',
          ));

  Future<void> setting(String key, String value) =>
      db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));

  /// Pumps [screen] and returns a ref that keeps the given providers loaded.
  Future<WidgetRef> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    late WidgetRef captured;
    await tester.pumpWidget(testApp(
      db: db,
      now: now,
      extra: overrides(),
      child: Consumer(builder: (context, ref, _) {
        captured = ref;
        ref.watch(zonesProvider);
        ref.watch(settingsProvider);
        ref.watch(eventReminderRowsProvider);
        ref.watch(alarmRowsProvider);
        ref.watch(contextEventRowsProvider);
        return screen;
      }),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return captured;
  }

  testWidgets('zones are opt-in and the explanation comes before any permission', (tester) async {
    await pump(tester, const ContextoScreen());
    await tester.tap(find.widgetWithText(SwitchListTile, 'ZONAS ACTIVADAS'));
    await tester.pumpAndSettle();
    expect(find.text('UBICACIÓN'), findsOneWidget);
    expect(device.calls, isEmpty, reason: 'nothing is asked before the explanation');

    await tester.tap(find.text('ENTENDIDO, CONTINUAR'));
    await tester.pumpAndSettle();
    expect(device.calls, ['requestForeground']);
    await tester.tap(find.text('CONTINUAR'));
    await tester.pumpAndSettle();
    expect(device.calls, ['requestForeground', 'requestBackground']);

    final settings = {for (final r in await db.select(db.appSettings).get()) r.key: r.value};
    expect(settings[SettingKey.zonesEnabled], '1');
    expect(settings[SettingKey.zonesDisclosureAt], isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('declining the explanation asks for nothing and keeps zones off', (tester) async {
    await pump(tester, const ContextoScreen());
    await tester.tap(find.widgetWithText(SwitchListTile, 'ZONAS ACTIVADAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AHORA NO'));
    await tester.pumpAndSettle();
    expect(device.calls, isEmpty);
    expect((await db.select(db.appSettings).get()).where((r) => r.key == SettingKey.zonesEnabled), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a zone is created from the current location with the default radius', (tester) async {
    await pump(tester, const ContextoScreen());
    await tester.ensureVisible(find.text('NUEVA ZONA'));
    await tester.tap(find.text('NUEVA ZONA'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre neutro'), 'Zona A');
    await tester.tap(find.text('USAR MI UBICACIÓN ACTUAL'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GUARDAR'));
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final saved = await db.select(db.zones).getSingle();
    expect(saved.name, 'Zona A');
    expect(saved.kind, 'chamba');
    expect(saved.latitude, 10.5);
    expect(saved.longitude, -20.25);
    expect(saved.radiusM, 200);
    expect(saved.status, 'activo');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a sixth active zone is refused', (tester) async {
    for (var i = 0; i < 5; i++) {
      await zone('Zona $i', 'otro', lat: 10 + i);
    }
    await pump(tester, const ContextoScreen());
    await tester.ensureVisible(find.text('NUEVA ZONA'));
    await tester.tap(find.text('NUEVA ZONA'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre neutro'), 'Zona extra');
    await tester.enterText(find.widgetWithText(TextField, 'O escribe o pega «latitud, longitud»'), '20.5, -30.25');
    await tester.ensureVisible(find.text('GUARDAR'));
    await tester.tap(find.text('GUARDAR'));
    await tester.pump();
    expect(find.textContaining('máximo de zonas activas'), findsOneWidget);
    expect(await db.select(db.zones).get(), hasLength(5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only active zones reach the phone, with the silence flag of their kind', (tester) async {
    final work = await zone('Zona A', 'chamba');
    final gym = await zone('Zona B', 'entreno', lat: 11);
    final home = await zone('Zona C', 'descanso', lat: 12);
    await zone('Zona D', 'otro', status: 'pausado', lat: 13);
    final ref = await pump(tester, const SizedBox.shrink());

    await syncZones(ref);
    expect(device.registered.last, isEmpty, reason: 'zones are off by default');

    await setting(SettingKey.zonesEnabled, '1');
    await tester.pump();
    await syncZones(ref);
    final sent = {for (final z in device.registered.last) z.id: z.silences};
    expect(sent, {work: true, gym: true, home: false});

    await setting(SettingKey.batteryWithoutZonesPct, '4');
    await setting(SettingKey.batteryWithZonesPct, '9');
    await setting(SettingKey.batteryLimitPct, '3');
    await tester.pump();
    await syncZones(ref);
    expect(device.registered.last, isEmpty, reason: 'over the battery limit');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('transitions from the phone set the mode; one tap corrects it', (tester) async {
    final gym = await zone('Zona B', 'entreno');
    await setting(SettingKey.zonesEnabled, '1');
    device.pendingTransitions.add(NativeTransition(
      zoneId: gym,
      transition: ContextTransition.enter,
      at: now.subtract(const Duration(minutes: 10)),
    ));
    final ref = await pump(tester, const ContextoScreen());
    expect(await drainTransitions(ref), 1);
    await tester.pump();
    expect(ref.read(modeDecisionProvider).mode, ContextMode.entreno);
    expect(ref.read(modeDecisionProvider).source, ModeSource.ubicacion);

    await tester.tap(find.widgetWithText(ChoiceChip, ContextMode.descanso.labelEs));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final correction = await db.select(db.modeCorrections).getSingle();
    expect(correction.inferred, 'entreno');
    expect(correction.corrected, 'descanso');
    expect(correction.locationMode, 'entreno');
    expect(device.manual.last.silencing, isFalse);
    expect(ref.read(modeDecisionProvider).mode, ContextMode.descanso);
    expect(ref.read(modeDecisionProvider).source, ModeSource.correccion);

    final event = await db.select(db.contextEvents).getSingle();
    expect(event.source, 'geocerca');
    expect(event.transition, 'entrar');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('"Llegué" stores a manual transition with its notes and fires the reminders', (tester) async {
    await pump(tester, const ContextoScreen());
    await tester.tap(find.text('LLEGUÉ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '¿Qué vas a hacer? (opcional)'), 'Leer');
    await tester.tap(find.widgetWithText(ChoiceChip, '4').last);
    await tester.pump();
    await tester.ensureVisible(find.text('GUARDAR'));
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final event = await db.select(db.contextEvents).getSingle();
    expect(event.source, 'manual');
    expect(event.transition, 'entrar');
    expect(event.plan, 'Leer');
    expect(event.feeling, 4);
    expect((await db.select(db.stateCheckins).getSingle()).value, 4);
    expect(device.fired, [('llegar', null)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('event reminders reach the phone with their zones', (tester) async {
    final work = await zone('Zona A', 'chamba');
    final paused = await zone('Zona C', 'descanso', status: 'pausado', lat: 12);
    Future<void> reminder(String message, String trigger, {String? kind, int? zoneId, String status = 'activo'}) =>
        db.into(db.eventReminders).insert(EventRemindersCompanion.insert(
              message: message,
              trigger: trigger,
              zoneKind: Value(kind),
              zoneId: Value(zoneId),
              status: Value(status),
              createdAt: '2026-10-01T00:00:00',
            ));
    await reminder('Agua', 'llegar');
    await reminder('Ropa', 'salir', kind: 'chamba');
    await reminder('Sin zona de ese tipo', 'llegar', kind: 'entreno');
    await reminder('Zona pausada', 'llegar', zoneId: paused);
    await reminder('Pausado', 'llegar', status: 'pausado');
    final ref = await pump(tester, const SizedBox.shrink());

    await syncEventReminders(ref);
    final sent = {for (final r in device.eventReminders.last) r.message: (r.trigger, r.zoneIds)};
    expect(sent, {
      'Agua': ('llegar', <int>[]),
      'Ropa': ('salir', [work]),
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active alarms reach the phone; the next ring is shown and the sound can be tested', (tester) async {
    Future<void> alarm(String label, String clock, int mask, {String status = 'activo'}) =>
        db.into(db.morningAlarms).insert(MorningAlarmsCompanion.insert(
              label: label,
              clock: clock,
              daysMask: mask,
              snoozeMinutes: 5,
              status: Value(status),
              createdAt: '2026-10-01T00:00:00',
            ));
    await alarm('Despertar', '05:30', daysMaskOf([1, 2, 3, 4, 5]));
    await alarm('Otra', '14:00', 0x7F, status: 'pausado');
    final ref = await pump(tester, const AlarmasScreen());

    await syncAlarms(ref);
    expect(scheduler.alarms.map((a) => (a.label, a.minuteOfDay, a.daysMask)), [('Despertar', 330, 0x1F)]);
    // Friday 09:00 → Monday 05:30.
    expect(find.textContaining('2 nov 05:30'), findsOneWidget);
    await tester.ensureVisible(find.text('PROBAR SONIDO AHORA'));
    await tester.tap(find.text('PROBAR SONIDO AHORA'));
    await tester.pump();
    expect(scheduler.rung, ['Prueba de alarma']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('battery test: the extra use of zones against the user limit', () {
    const off = AppSettingsState();
    expect(off.batteryZonesCostPct, isNull);
    expect(off.batteryOverLimit, isFalse);
    final measured = AppSettingsState.fromMap({
      SettingKey.batteryWithoutZonesPct: '4',
      SettingKey.batteryWithZonesPct: '6',
      SettingKey.batteryLimitPct: '3',
    });
    expect(measured.batteryZonesCostPct, 2);
    expect(measured.batteryOverLimit, isFalse);
    expect(
      AppSettingsState.fromMap({
        SettingKey.batteryWithoutZonesPct: '4',
        SettingKey.batteryWithZonesPct: '8',
        SettingKey.batteryLimitPct: '3',
      }).batteryOverLimit,
      isTrue,
    );
  });
}
