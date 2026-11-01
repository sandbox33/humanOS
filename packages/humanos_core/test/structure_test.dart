import 'dart:io';

import 'package:test/test.dart';

/// Checkpoint CP2: every engine file in lib/src has its own test file.
void main() {
  test('every lib/src file has a matching test', () {
    // Paths relative to lib/src, sub-folders included (advisor/…).
    final sources = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path.substring('lib/src/'.length).replaceAll('.dart', ''))
        .toList();
    expect(sources, isNotEmpty);
    for (final name in sources) {
      expect(
        File('test/${name}_test.dart').existsSync(),
        isTrue,
        reason: 'Falta test/${name}_test.dart',
      );
    }
  });

  test('the public library exports every engine', () {
    final barrel = File('lib/humanos_core.dart').readAsStringSync();
    for (final file in Directory(
      'lib/src',
    ).listSync(recursive: true).whereType<File>()) {
      final name = file.path.substring('lib/src/'.length);
      expect(barrel.contains("export 'src/$name';"), isTrue, reason: name);
    }
  });
}
