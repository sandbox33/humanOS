import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

LogIntent? rules(String phrase) => parseByRules(phrase);

void main() {
  group('rules: work', () {
    test('hours, label and rate', () {
      expect(
        rules('4 horas de pintura a 4,10'),
        const LogIntent(LogAction.workEntry, {
          'minutes': 240,
          'rate_cents': 410,
          'label': 'pintura',
        }),
      );
      expect(rules('trabajé 3 horas y media en la bodega')!.fields, {
        'minutes': 210,
        'label': 'bodega',
      });
      expect(rules('trabajé media hora')!.fields, {'minutes': 30});
      expect(rules('45 min de trabajo extra')!.fields, {'minutes': 45});
    });

    test('a clock range reads the afternoon and crosses midnight', () {
      expect(rules('trabajé de 8 a 4')!.fields, {
        'start': '08:00',
        'end': '16:00',
      });
      expect(rules('turno de 22 a 6')!.fields, {
        'start': '22:00',
        'end': '06:00',
      });
      expect(rules('chamba de 7:30 a 15:45 a 5 la hora')!.fields, {
        'start': '07:30',
        'end': '15:45',
        'rate_cents': 500,
      });
    });

    test('a total without hours keeps the rate empty', () {
      expect(rules('hice un trabajo de 20 dólares')!.fields, {
        'total_cents': 2000,
      });
      expect(rules(r'me pagaron $35,50 por arreglar una puerta')!.fields, {
        'total_cents': 3550,
      });
    });

    test('the label keeps the user spelling', () {
      expect(
        rules('5 horas de Jardinería a 3,80')!.fields['label'],
        'Jardinería',
      );
    });
  });

  group('rules: weight, state, thermos, food', () {
    test('weight', () {
      expect(
        rules('peso 70,4'),
        const LogIntent(LogAction.weight, {'kg': 70.4}),
      );
      expect(rules('hoy pesé 71.2 kg')!.fields, {'kg': 71.2});
      expect(rules('estoy en 69 kilos')!.fields, {'kg': 69.0});
      expect(rules('peso 7'), isNull, reason: 'out of range');
    });

    test('state 1–5', () {
      expect(rules('me siento 4')!.fields, {'value': 4});
      expect(rules('ánimo 2 de 5')!.fields, {'value': 2});
      expect(rules('estoy muy bien')!.fields, {'value': 5});
      expect(rules('ando regular')!.fields, {'value': 3});
    });

    test('thermos: the moment, or a draft that asks for it', () {
      expect(rules('termo en la pausa')!.fields, {'moment': 'pausa'});
      expect(rules('llené el termo antes de salir')!.fields, {
        'moment': 'antes',
      });
      final draft = rules('llené el termo')!;
      expect(draft.action, LogAction.thermos);
      expect(validateLogJson(draft.toJson()).ok, isFalse);
    });

    test('food with grams, units or neither', () {
      expect(rules('comí 200 g de arroz')!.fields, {
        'grams': 200.0,
        'food': 'arroz',
      });
      expect(rules('desayuné dos huevos')!.fields, {
        'quantity': 2.0,
        'food': 'huevos',
      });
      expect(rules('almorcé lentejas con arroz')!.fields, {
        'food': 'lentejas con arroz',
      });
    });

    test('anything else is not a record (no chat, no advice)', () {
      for (final phrase in [
        'hola qué tal',
        'me duele la rodilla',
        'qué debería comer hoy',
        '',
      ]) {
        expect(rules(phrase), isNull, reason: phrase);
      }
    });
  });

  group('schema validation', () {
    test('a valid record passes and numbers are normalised', () {
      final v = validateLogJson({'accion': 'weight', 'kg': 70});
      expect(v.ok, isTrue);
      expect(v.intent!.fields['kg'], 70.0);
    });

    test('unknown actions and fields, wrong types and ranges fail', () {
      expect(validateLogJson({'accion': 'chat'}).ok, isFalse);
      expect(
        validateLogJson({'accion': 'weight', 'kg': 70, 'nota': 'x'}).ok,
        isFalse,
      );
      expect(validateLogJson({'accion': 'state', 'value': 6}).ok, isFalse);
      expect(validateLogJson({'accion': 'state', 'value': '4'}).ok, isFalse);
      expect(
        validateLogJson({
          'accion': 'work_entry',
          'start': '8:00',
          'end': '16:00',
        }).ok,
        isFalse,
      );
      expect(validateLogJson('texto').ok, isFalse);
    });

    test('work needs hours or a total, and a rate needs hours', () {
      expect(
        validateLogJson({'accion': 'work_entry', 'rate_cents': 400}).ok,
        isFalse,
      );
      expect(
        validateLogJson({'accion': 'work_entry', 'start': '08:00'}).ok,
        isFalse,
      );
      expect(
        validateLogJson({'accion': 'work_entry', 'total_cents': 1500}).ok,
        isTrue,
      );
      expect(
        validateLogJson({
          'accion': 'work_entry',
          'minutes': 60,
          'rate_cents': 400,
        }).ok,
        isTrue,
      );
    });
  });

  test('the first JSON object of a model answer', () {
    expect(extractJsonObject('JSON: {"accion": "weight", "kg": 70.5} listo'), {
      'accion': 'weight',
      'kg': 70.5,
    });
    expect(extractJsonObject('{"a": "llave } dentro", "b": {"c": 1}} y más'), {
      'a': 'llave } dentro',
      'b': {'c': 1},
    });
    expect(extractJsonObject('sin json'), isNull);
    expect(extractJsonObject('{roto'), isNull);
  });
}
