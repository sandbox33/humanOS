import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/app.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/services/notifications.dart';
import 'package:humanos/services/services.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

void main() {
  late UserDb db;
  late SilentNotificationService notifications;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    notifications = SilentNotificationService();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    // Invented test template: every day 08:00–16:00, break 12:00 (30 min).
    await db.into(db.workTemplates).insert(WorkTemplatesCompanion.insert(
          label: 'Prueba',
          kind: 'estable',
          rateCentsPerHour: const Value(325),
          startClock: const Value('08:00'),
          endClock: const Value('16:00'),
          breakStart: const Value('12:00'),
          breakMinutes: const Value(30),
          daysMask: const Value(0x7F),
          heatExposure: const Value(true),
          createdAt: '2026-10-01T00:00:00',
        ));
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        userDbProvider.overrideWithValue(db),
        referenceDbProvider.overrideWithValue(fixtureReferenceDb()),
        notificationServiceProvider.overrideWithValue(notifications),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 30, 7, 0)),
      ],
      child: const HumanOsApp(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a template logs work in three taps with the break unpaid', (tester) async {
    await open(tester);
    await tester.tap(find.text('TRABAJO').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Prueba'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('GUARDAR'));
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final entry = await db.select(db.workEntries).getSingle();
    expect(entry.label, 'Prueba');
    expect(entry.minutes, 450);
    expect(entry.earnedCents, 2438); // 450 min × 3,25 / 60 = 24,375 → 24,38
    expect(entry.startTs, '2026-10-30T08:00:00');
    expect(entry.endTs, '2026-10-30T16:00:00');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no reminder falls inside work except in its break', (tester) async {
    await open(tester);
    await tester.pump(const Duration(seconds: 1));
    final scheduled = notifications.scheduled;
    expect(scheduled, isNotEmpty);
    for (final r in scheduled) {
      final day = DateTime(r.at.year, r.at.month, r.at.day);
      final start = day.add(const Duration(hours: 8));
      final end = day.add(const Duration(hours: 16));
      final breakStart = day.add(const Duration(hours: 12));
      final breakEnd = breakStart.add(const Duration(minutes: 30));
      final inWork = !r.at.isBefore(start) && r.at.isBefore(end);
      final inBreak = !r.at.isBefore(breakStart) && r.at.isBefore(breakEnd);
      expect(inWork && !inBreak, isFalse, reason: '${r.channel} ${r.at} ${r.title}');
    }
    final thermos = scheduled.where((r) => r.channel == ReminderChannel.hydration).toList();
    expect(thermos.map((r) => r.at), contains(DateTime(2026, 10, 30, 7, 30)));
    expect(thermos.map((r) => r.at), contains(DateTime(2026, 10, 30, 12)));
    for (final r in scheduled) {
      expect(r.body.contains('USD'), isFalse, reason: 'no money in notifications');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('the template schedule and silence windows come from user data', () async {
    final row = await db.select(db.workTemplates).getSingle();
    expect(row.daysMask, 0x7F);
    final windows = plannedWindows(DateTime(2026, 10, 30), [
      WorkSchedule(label: row.label, startMin: 8 * 60, endMin: 16 * 60, breakStartMin: 12 * 60, breakMinutes: 30, daysMask: row.daysMask),
    ]);
    expect(windows.single.silences(DateTime(2026, 10, 30, 10)), isTrue);
    expect(windows.single.silences(DateTime(2026, 10, 30, 12, 15)), isFalse);
  });
}
