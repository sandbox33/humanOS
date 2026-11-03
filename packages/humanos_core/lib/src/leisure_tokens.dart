/// Leisure tokens (B7), optional and off by default. When the user turns
/// them on, the habits they choose earn tokens and the leisure they choose
/// spends them, by their own rules. Off, leisure has no limit and nothing
/// is counted. Turning them on or off waits a delay the user sets, and
/// turning them off never deletes the history.
library;

import 'screen_time.dart' show AppCategory;

/// On/off with its pending change.
class TokenSwitch {
  const TokenSwitch({
    required this.enabled,
    this.pendingTarget,
    this.pendingSince,
  });

  /// The state in force before any pending change.
  final bool enabled;

  /// The state asked for, waiting its delay; null when none.
  final bool? pendingTarget;
  final DateTime? pendingSince;

  /// When the pending change takes effect, or null without one.
  DateTime? maturesAt(int waitHours) =>
      pendingTarget == null || pendingSince == null
      ? null
      : pendingSince!.add(Duration(hours: waitHours));

  /// Whether tokens are on at [now]: the pending change counts once its
  /// delay has passed.
  bool enabledAt(DateTime now, int waitHours) {
    final at = maturesAt(waitHours);
    if (at != null && !now.isBefore(at)) return pendingTarget!;
    return enabled;
  }
}

/// A habit or event that earns tokens.
class EarnRule {
  const EarnRule({required this.source, required this.tokens});

  /// `habit:<id>`, `entreno`, `comida` or `cierre`.
  final String source;
  final int tokens;
}

/// What a kind of leisure costs: [tokens] for each started block of
/// [perMinutes] minutes.
class CostRule {
  const CostRule({
    required this.category,
    required this.tokens,
    required this.perMinutes,
  });

  final AppCategory category;
  final int tokens;
  final int perMinutes;
}

/// Tokens earned in a day: each rule's tokens times how many times its
/// event happened ([events] by source).
Map<String, int> earnedByRule(Map<String, int> events, List<EarnRule> rules) =>
    {
      for (final r in rules)
        if ((events[r.source] ?? 0) > 0) r.source: r.tokens * events[r.source]!,
    };

/// Tokens spent in a day: for each priced category, its tokens for each
/// started block of minutes used.
Map<AppCategory, int> spentByCategory(
  Map<AppCategory, int> minutes,
  List<CostRule> rules,
) => {
  for (final r in rules)
    if ((minutes[r.category] ?? 0) > 0 && r.perMinutes > 0)
      r.category:
          r.tokens *
          ((minutes[r.category]! + r.perMinutes - 1) ~/ r.perMinutes),
};

/// One day of the ledger.
class TokenDay {
  const TokenDay({
    required this.date,
    required this.earned,
    required this.spent,
  });

  final DateTime date;
  final int earned;
  final int spent;
}

/// The balance of the ledger (it may go below zero: tokens never block).
int tokenBalance(Iterable<TokenDay> days) =>
    days.fold(0, (s, d) => s + d.earned - d.spent);
