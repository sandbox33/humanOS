import 'dart:io';

import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  test('keys are unique', () {
    final keys = assumptionCatalog.map((d) => d.key).toList();
    expect(keys.toSet().length, keys.length);
  });

  test('every assumption has a Spanish title and explanation', () {
    for (final def in assumptionCatalog) {
      expect(def.titleEs.trim(), isNotEmpty, reason: def.key);
      expect(def.explainEs.trim().length, greaterThan(20), reason: def.key);
    }
  });

  test('defaults are inside their editable range', () {
    for (final def in assumptionCatalog) {
      expect(def.accepts(def.value), isTrue, reason: def.key);
      expect(def.min <= def.max, isTrue, reason: def.key);
    }
  });

  test('every key constant used by the engines exists in the catalog', () {
    final source = File('lib/src/assumptions.dart').readAsStringSync();
    final constants = RegExp(
      r"static const \w+ = '([a-z0-9_]+)';",
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(constants, isNotEmpty);
    for (final key in constants) {
      expect(assumptionsByKey.containsKey(key), isTrue, reason: key);
    }
  });

  test('unknown keys throw instead of becoming zero', () {
    expect(() => Assumptions.defaults()['no_existe'], throwsArgumentError);
  });

  test('stored values override defaults', () {
    final a = Assumptions.defaults().copyWith({A.proteinGPerKg: 2.0});
    expect(a[A.proteinGPerKg], 2.0);
    expect(a[A.fatKcalFraction], 0.30);
  });

  test('no fixed HRV baseline, per-hour electrolytes or K from Na', () {
    final keys = assumptionsByKey.keys.join(' ');
    expect(keys.contains('hrv_baseline_ms'), isFalse);
    expect(keys.contains('potassium'), isFalse);
    expect(keys.contains('na_mg_per_h'), isFalse);
  });

  test('engines are pure: no Flutter imports in lib/', () {
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      expect(text.contains('package:flutter'), isFalse, reason: file.path);
      expect(text.contains('dart:ui'), isFalse, reason: file.path);
    }
  });
}
