import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/asistente/domain/assistant_model.dart';
import 'package:humanos/features/asistente/presentation/asistente_screen.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fake_llm.dart';
import 'support/fixtures.dart';

class _MemoryTokens implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? token) async => value = token;
}

void main() {
  late UserDb db;
  final now = DateTime(2026, 10, 30, 9);

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, {FakeLlm? model, bool enabled = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    if (enabled) {
      await db.into(db.appSettings).insert(AppSettingsCompanion.insert(key: AssistantKey.enabled, value: '1'));
    }
    final extra = <Override>[
      tokenStoreProvider.overrideWithValue(_MemoryTokens()),
      modelManagerProvider.overrideWithValue(FakeModelManager(installed: model != null)),
      if (model != null) llmBridgeProvider.overrideWithValue(model),
    ];
    await tester.pumpWidget(testApp(db: db, now: now, extra: extra, child: const AsistenteScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> say(WidgetTester tester, String phrase) async {
    await tester.enterText(find.widgetWithText(TextField, 'Escribe lo que hiciste'), phrase);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('INTERPRETAR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the rules understand a weight and nothing is saved before confirming', (tester) async {
    await open(tester);
    await say(tester, 'peso 70,4');
    expect(find.text('> RESULTADO · PESO'), findsOneWidget);
    expect(find.text('70,4 kg'), findsOneWidget);
    expect(await db.select(db.bodyMetrics).get(), isEmpty);

    await tester.scrollUntilVisible(find.text('REVISAR Y GUARDAR'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(find.text('REVISAR Y GUARDAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();
    final saved = await db.select(db.bodyMetrics).getSingle();
    expect(saved.weightKg, 70.4);
    expect(saved.date, '2026-10-30');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the model is asked only when the rules find nothing, and its JSON is validated', (tester) async {
    final model = FakeLlm({
      'metí 250 g de yuca en el almuerzo': 'JSON: {"accion": "food_log", "grams": 250, "food": "yuca"}',
      'cuéntame algo': 'Claro, te cuento un chiste…',
    });
    await open(tester, model: model, enabled: true);

    await say(tester, 'peso 70,4');
    expect(model.prompts, isEmpty, reason: 'rules first');

    await say(tester, 'metí 250 g de yuca en el almuerzo');
    expect(model.prompts, hasLength(1));
    expect(find.text('> RESULTADO · COMIDA'), findsOneWidget);
    expect(find.text('yuca'), findsOneWidget);
    expect(find.text('250 g'), findsOneWidget);

    await say(tester, 'cuéntame algo');
    expect(find.textContaining('No es un registro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('without the user turning it on the model stays off until it passes the evaluation', (tester) async {
    final model = FakeLlm(const {});
    await open(tester, model: model);
    await say(tester, 'metí 250 g de yuca en el almuerzo');
    expect(model.prompts, isEmpty);
    expect(find.textContaining('No es un registro'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the evaluation runs the shipped phrases and is kept', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(
      find.text('EVALUAR (FRASES DE PRUEBA)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('EVALUAR (FRASES DE PRUEBA)'));
    // The phrases come from the app's assets (real file access).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final rows = {for (final r in await db.select(db.appSettings).get()) r.key: r.value};
    expect(rows[AssistantKey.evaluation], isNotNull);
    expect(find.textContaining('de 40)'), findsOneWidget);
    expect(find.text('solo reglas'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('records are described in Spanish', () {
    expect(
      describeIntentEs(const LogIntent(LogAction.workEntry, {'minutes': 240, 'rate_cents': 410, 'label': 'pintura'})),
      [('Trabajo', 'pintura'), ('Horas', '4 h'), ('Tarifa', '4,10 USD/h')],
    );
    expect(describeIntentEs(const LogIntent(LogAction.thermos, {})), [('Momento', 'sin dato')]);
  });
}
