import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/app/app.dart';
import 'package:humanos/app/providers.dart';
import 'package:humanos/app/theme.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Normal text needs 4.5:1 for WCAG AA.
const aaNormal = 4.5;

void main() {
  final variants = <(String, ThemeData)>[
    for (final accent in AccentColor.values) ('wasteland/${accent.code}', buildTheme(accent)),
    ('grimorio', buildTheme(AccentColor.phosphor, theme: HosThemeId.grimorio)),
  ];

  for (final (name, theme) in variants) {
    test('$name: every text colour reaches WCAG AA on the surfaces it is drawn on', () {
      final s = theme.colorScheme;
      final look = theme.extension<HosLook>()!;
      final surfaces = {
        'fondo': theme.scaffoldBackgroundColor,
        'superficie': s.surface,
        'superficie alta': look.surfaceHigh,
      };
      final texts = {
        'texto': theme.textTheme.bodyMedium!.color!,
        'texto secundario': theme.textTheme.bodySmall!.color!,
        'títulos': theme.textTheme.headlineLarge!.color!,
        'etiquetas': theme.textTheme.labelLarge!.color!,
        'botón contorno': s.primary,
        'secundario': s.secondary,
        'error': s.error,
        'pista': theme.inputDecorationTheme.hintStyle!.color!,
        'OK': look.ok,
        'aviso': look.warn,
        'peligro': look.danger,
      };
      final failures = <String>[];
      void check(String what, Color fg, Color bg) {
        final ratio = contrast(fg, bg);
        if (ratio < aaNormal) failures.add('$what: ${ratio.toStringAsFixed(2)}');
      }

      for (final t in texts.entries) {
        for (final b in surfaces.entries) {
          check('${t.key} sobre ${b.key}', t.value, b.value);
        }
      }
      check('texto de botón lleno', s.onPrimary, s.primary);
      check('texto sobre secundario', s.onSecondary, s.secondary);
      check('texto sobre error', s.onError, s.error);
      final bar = theme.navigationBarTheme;
      check('barra inferior', bar.iconTheme!.resolve({})!.color!, bar.backgroundColor!);
      check('barra superior', theme.appBarTheme.foregroundColor!, theme.appBarTheme.backgroundColor!);
      check('aviso inferior', theme.snackBarTheme.contentTextStyle!.color!, theme.snackBarTheme.backgroundColor!);
      expect(failures, isEmpty);
    });
  }

  test('each theme draws only with fonts declared in pubspec with their OFL licence', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final spec in ThemeRegistry.all) {
      for (final family in spec.fonts) {
        expect(pubspec, contains('- family: $family'), reason: family);
      }
    }
    final assets = RegExp(r'asset: (assets/fonts/\S+\.ttf)').allMatches(pubspec).map((m) => m.group(1)!);
    for (final path in assets) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    for (final licence in ['VT323', 'ShareTechMono', 'IBMPlexMono', 'Cinzel', 'IMFellEnglish']) {
      final text = File('assets/fonts/OFL-$licence.txt').readAsStringSync();
      expect(text, contains('SIL Open Font License'), reason: licence);
    }
  });

  test('an unknown stored theme falls back to WASTELAND', () {
    expect(HosThemeId.parse(null), HosThemeId.wasteland);
    expect(HosThemeId.parse('otro'), HosThemeId.wasteland);
    expect(HosThemeId.parse('grimorio'), HosThemeId.grimorio);
  });

  group('live switch', () {
    late UserDb db;

    setUpAll(() => initializeDateFormatting('es'));
    setUp(() async {
      db = memoryUserDb();
      await seedIfNeeded(db);
      await insertTestProfile(db);
    });
    tearDown(() => db.close());

    testWidgets('changing the theme setting rebuilds the app without restarting', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            userDbProvider.overrideWithValue(db),
            referenceDbProvider.overrideWithValue(fixtureReferenceDb()),
            clockProvider.overrideWithValue(() => DateTime(2026, 10, 13, 9)),
          ],
          child: const HumanOsApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      ThemeData current() => Theme.of(tester.element(find.text('ESTADO').first));
      expect(current().brightness, Brightness.dark);
      expect(current().extension<HosLook>()!.terminal, isTrue);

      await tester.runAsync(() => SettingsRepository(db).set(SettingKey.theme, HosThemeId.grimorio.code));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(current().brightness, Brightness.light);
      expect(current().extension<HosLook>()!.terminal, isFalse);
      expect(find.text('ESTADO'), findsWidgets, reason: 'same screen, no restart');

      final stored = await tester.runAsync(
        () => (db.select(db.appSettings)..where((t) => t.key.equals(SettingKey.theme))).getSingle(),
      );
      expect(stored!.updatedAt, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
