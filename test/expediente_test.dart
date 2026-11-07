import 'package:flutter_test/flutter_test.dart';

import 'support/expediente_schema.dart';

// The project file HumanOS imports must keep the version 2 format.
void main() {
  test('docs/expediente/expediente.json follows docs/expediente/ESQUEMA.md (version 2)', () {
    expect(validateExpediente(readJson('docs/expediente/expediente.json')), isEmpty);
  });

  test('no id or brief of the version 1 file is lost', () {
    final v1 = readJson('docs/expediente/expediente_v1.json');
    expect(missingFromV1(v1, readJson('docs/expediente/expediente.json')), isEmpty);
  });

  test('public repository: no money signs or clock times in the file', () {
    expect(privacyFindings(readJson('docs/expediente/expediente.json')), isEmpty);
  });
}
