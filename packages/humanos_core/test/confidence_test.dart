import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  test('parse falls back to baja', () {
    expect(Confidence.parse('alta'), Confidence.alta);
    expect(Confidence.parse('???'), Confidence.baja);
    expect(Confidence.parse(null), Confidence.baja);
  });

  test('min keeps the less certain level', () {
    expect(Confidence.alta.min(Confidence.media), Confidence.media);
    expect(Confidence.baja.min(Confidence.alta), Confidence.baja);
  });

  test('lower never goes below baja', () {
    expect(Confidence.alta.lower(), Confidence.media);
    expect(Confidence.media.lower(5), Confidence.baja);
  });
}
