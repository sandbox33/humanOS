import 'package:humanos_core/src/red_flags.dart';
import 'package:test/test.dart';

void main() {
  test('chest pain, fainting and blood route to medical care', () {
    for (final (text, kind) in [
      ('Tengo dolor en el pecho desde ayer', RedFlagKind.chestPain),
      ('me duele el pecho al subir', RedFlagKind.chestPain),
      ('Me desmayé en el taller', RedFlagKind.fainting),
      ('casi me desmayo', RedFlagKind.fainting),
      ('perdí el conocimiento', RedFlagKind.fainting),
      ('vi sangre en la orina', RedFlagKind.blood),
      ('me sangra la nariz', RedFlagKind.blood),
      ('no puedo respirar bien', RedFlagKind.breathing),
      ('creo que fue un golpe de calor', RedFlagKind.heatStroke),
    ]) {
      final r = detectRedFlags(text);
      expect(r.kinds, contains(kind), reason: text);
      expect(r.messageEs, contains('Busca atención médica'));
    }
  });

  test('ordinary messages pass through', () {
    for (final text in [
      '¿Cuánta proteína me falta?',
      'comí 3 huevos',
      'Quiero mejorar mi press de pecho',
      'el pecho de pollo está en la nevera',
    ]) {
      final r = detectRedFlags(text);
      expect(r.any, isFalse, reason: text);
      expect(r.messageEs, isNull);
    }
  });

  test('the message names the Ecuadorian emergency number', () {
    expect(redFlagMessageEs, contains('911'));
  });
}
