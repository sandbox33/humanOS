import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/habitos/presentation/habitos_screen.dart';
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

  testWidgets('a broken streak shows the best streak and days in 30, not a red zero',
      (tester) async {
    final today = DateTime(2026, 10, 13);
    final habits = {for (final h in await db.select(db.habits).get()) h.alias: h.id};
    Future<void> log(String alias, int daysAgo, double value) => db.into(db.habitLogs).insert(
          HabitLogsCompanion.insert(
            habitId: habits[alias]!,
            date: isoDate(addDays(today, -daysAgo)),
            value: value,
          ),
        );
    // Five completed minimum days, then two failed days (streak broken).
    for (var d = 7; d >= 3; d--) {
      await log('P100', d, 120);
      await log('BÁSCULA', d, 1);
      await log('CLARO', d, 1);
    }
    for (final d in [2, 1]) {
      await log('P100', d, 40);
      await log('BÁSCULA', d, 0);
      await log('CLARO', d, 1);
    }

    await tester.pumpWidget(testApp(db: db, child: const HabitosScreen(), now: DateTime(2026, 10, 13, 9)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('MEJOR RACHA 5'), findsOneWidget);
    expect(find.textContaining('días cumplidos en 30'), findsWidgets);
    expect(find.text('0 DÍAS'), findsNothing);
    expect(find.textContaining('MISIÓN MÍNIMA'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
