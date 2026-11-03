import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented rules only.
void main() {
  group('switch with its wait', () {
    final asked = DateTime(2026, 11, 20, 21);

    test('off by default; a change takes effect only after the wait', () {
      expect(const TokenSwitch(enabled: false).enabledAt(asked, 24), isFalse);
      final pending = TokenSwitch(
        enabled: false,
        pendingTarget: true,
        pendingSince: asked,
      );
      expect(
        pending.enabledAt(
          asked.add(const Duration(hours: 23, minutes: 59)),
          24,
        ),
        isFalse,
      );
      expect(
        pending.enabledAt(asked.add(const Duration(hours: 24)), 24),
        isTrue,
      );
      expect(pending.maturesAt(24), DateTime(2026, 11, 21, 21));
      expect(const TokenSwitch(enabled: true).maturesAt(24), isNull);
    });

    test('turning off waits too', () {
      final pending = TokenSwitch(
        enabled: true,
        pendingTarget: false,
        pendingSince: asked,
      );
      expect(
        pending.enabledAt(asked.add(const Duration(hours: 1)), 24),
        isTrue,
      );
      expect(
        pending.enabledAt(asked.add(const Duration(hours: 25)), 24),
        isFalse,
      );
    });
  });

  test(
    'earning: each chosen event times its tokens; unchosen events earn nothing',
    () {
      const rules = [
        EarnRule(source: 'entreno', tokens: 3),
        EarnRule(source: 'comida', tokens: 1),
        EarnRule(source: 'habit:4', tokens: 2),
      ];
      final earned = earnedByRule({
        'entreno': 1,
        'comida': 4,
        'cierre': 1,
      }, rules);
      expect(earned, {'entreno': 3, 'comida': 4});
    },
  );

  test(
    'spending: tokens per started block of minutes, only priced categories',
    () {
      const rules = [
        CostRule(category: AppCategory.ocio, tokens: 1, perMinutes: 30),
        CostRule(category: AppCategory.redes, tokens: 2, perMinutes: 15),
      ];
      final spent = spentByCategory({
        AppCategory.ocio: 61,
        AppCategory.redes: 15,
        AppCategory.trabajo: 300,
      }, rules);
      expect(spent, {AppCategory.ocio: 3, AppCategory.redes: 2});
      expect(spentByCategory({AppCategory.ocio: 0}, rules), isEmpty);
    },
  );

  test('the balance may go below zero (tokens never block)', () {
    final days = [
      TokenDay(date: DateTime(2026, 11, 1), earned: 5, spent: 2),
      TokenDay(date: DateTime(2026, 11, 2), earned: 0, spent: 6),
    ];
    expect(tokenBalance(days), -3);
    expect(tokenBalance(const []), 0);
  });
}
