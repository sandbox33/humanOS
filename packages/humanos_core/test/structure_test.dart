import 'dart:io';

import 'package:test/test.dart';

/// Checkpoint CP2: every engine file in lib/src has its own test file.
void main() {
  test('every lib/src file has a matching test', () {
    final sources = Directory('lib/src')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.dart', ''))
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
    for (final file in Directory('lib/src').listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      expect(barrel.contains("export 'src/$name';"), isTrue, reason: name);
    }
  });
}
