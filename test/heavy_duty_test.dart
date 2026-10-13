import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/heavy_duty/presentation/session_page.dart';
import 'package:humanos/services/screen_awake.dart';
import 'package:humanos/services/services.dart';
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

  testWidgets('one-handed set: giant counter, volume keys, failure-safe cue and screen on',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final screen = NoopScreenAwake();
    await tester.pumpWidget(testApp(
      db: db,
      reference: fixtureReferenceDb(),
      child: const SessionPage(
        template: TrainingTemplate.b,
        mode: SessionMode.normal,
        band: null,
        overridden: false,
      ),
      extra: [
        screenAwakeProvider.overrideWithValue(screen),
        currentAssumptionsProvider.overrideWithValue(
          Assumptions.defaults().copyWith({A.tapDebounceMs: 0}),
        ),
      ],
    ));
    await tester.pump();
    expect(screen.on, isTrue, reason: 'the screen stays on during a session');

    // Big 3 → first work set (Romanian deadlift, not safe to failure).
    await tester.tap(find.text('SIGUIENTE'));
    await tester.pump();
    expect(find.textContaining('NO AL FALLO'), findsOneWidget);

    await tester.tap(find.text('EMPEZAR SERIE'));
    await tester.pump();
    final counter = find.byKey(const Key('rep-counter'));
    expect(tester.getSize(counter).height, greaterThanOrEqualTo(120));
    for (var i = 0; i < 3; i++) {
      await tester.tap(counter);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.text('TERMINAR SERIE'));
    await tester.pump();
    expect(find.text('LLEGUÉ AL FALLO TÉCNICO'), findsNothing,
        reason: 'no failure toggle for an exercise that is not safe to failure');
    expect(find.textContaining('REST-PAUSE'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(screen.on, isFalse);
  });
}
