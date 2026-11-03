import 'package:drift/drift.dart' show OrderingTerm, Value, Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../pantalla/domain/screen_model.dart';
import '../../trabajo/data/work_repository.dart' show parseStamp, stampOf;

/// B7 settings. Absent = off, nothing pending.
abstract final class TokenKey {
  static const enabled = 'tokens_enabled';
  static const pending = 'tokens_pending';
  static const pendingSince = 'tokens_pending_since';

  /// `YYYY-MM-DD` from which the ledger counts (the day tokens took effect).
  static const since = 'tokens_since';
}

/// Fixed event sources the app can see (besides each habit).
const tokenEventSources = {
  'entreno': 'Sesión de entreno registrada',
  'comida': 'Cada comida registrada',
  'cierre': 'Cierre del día',
};

TokenSwitch switchOf(Map<String, String> map) => TokenSwitch(
      enabled: map[TokenKey.enabled] == '1',
      pendingTarget: switch (map[TokenKey.pending]) {
        '1' => true,
        '0' => false,
        _ => null,
      },
      pendingSince: parseStamp(map[TokenKey.pendingSince]),
    );

final tokenSwitchProvider = Provider<TokenSwitch>(
  (ref) => switchOf(ref.watch(settingsMapProvider).value ?? const {}),
);

/// Whether tokens are on now (a pending change counts once its wait ends).
final tokensOnProvider = Provider<bool>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(tokenSwitchProvider).enabledAt(now, ref.watch(currentAssumptionsProvider).integer(A.tokensToggleWaitH));
});

final earnRulesProvider = StreamProvider<List<TokenEarnRuleRow>>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.tokenEarnRules).watch();
});

final costRulesProvider = StreamProvider<List<TokenCostRuleRow>>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.tokenCostRules).watch();
});

final tokenDaysProvider = StreamProvider<List<TokenDayRow>>((ref) {
  final db = ref.watch(userDbProvider);
  return (db.select(db.tokenDays)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
});

/// Balance of the whole ledger (history included, also after turning off).
final tokenBalanceProvider = Provider<int>((ref) {
  final rows = ref.watch(tokenDaysProvider).value ?? const <TokenDayRow>[];
  return rows.fold(0, (s, r) => s + r.earned - r.spent);
});

/// Asks to turn tokens on or off; the change waits its delay.
Future<void> askTokenSwitch(WidgetRef ref, bool on) async {
  final settings = ref.read(settingsRepositoryProvider);
  final current = ref.read(tokenSwitchProvider);
  if (current.pendingTarget == null && current.enabled == on) return;
  if (current.pendingTarget != null && current.enabled == on) {
    // Asking back the state in force cancels the pending change.
    await settings.remove(TokenKey.pending);
    await settings.remove(TokenKey.pendingSince);
    return;
  }
  await settings.set(TokenKey.pending, on ? '1' : '0');
  await settings.set(TokenKey.pendingSince, stampOf(ref.read(clockProvider)()));
}

/// Applies a matured change and, while tokens are on, rewrites the ledger
/// of each day since they took effect from the user's own records. Off,
/// nothing is read or written (history stays as it was).
Future<void> syncTokens(WidgetRef ref) async {
  final settings = ref.read(settingsRepositoryProvider);
  final map = {
    for (final k in [TokenKey.enabled, TokenKey.pending, TokenKey.pendingSince, TokenKey.since])
      if (await settings.get(k) case final v?) k: v,
  };
  final now = ref.read(clockProvider)();
  final wait = ref.read(currentAssumptionsProvider).integer(A.tokensToggleWaitH);
  final sw = switchOf(map);
  final matures = sw.maturesAt(wait);
  if (matures != null && !now.isBefore(matures)) {
    await settings.set(TokenKey.enabled, sw.pendingTarget! ? '1' : '0');
    if (sw.pendingTarget!) map[TokenKey.since] = isoDate(matures);
    if (sw.pendingTarget!) await settings.set(TokenKey.since, isoDate(matures));
    await settings.remove(TokenKey.pending);
    await settings.remove(TokenKey.pendingSince);
  }
  if (!sw.enabledAt(now, wait)) return;
  final since = map[TokenKey.since];
  if (since == null) return;

  final db = ref.read(userDbProvider);
  final earnRules = [
    for (final r in await db.select(db.tokenEarnRules).get()) EarnRule(source: r.source, tokens: r.tokens),
  ];
  final costRules = [
    for (final r in await db.select(db.tokenCostRules).get())
      CostRule(category: AppCategory.parse(r.category), tokens: r.tokens, perMinutes: r.perMinutes),
  ];
  final classes = await ref.read(screenRepositoryProvider).classes();
  final today = dateOnly(now);
  for (var day = parseIsoDate(since); !day.isAfter(today); day = addDays(day, 1)) {
    final date = isoDate(day);
    final events = <String, int>{
      'entreno': await _count(db, 'SELECT COUNT(*) AS n FROM sessions WHERE date = ?', date),
      'comida': await _count(
        db,
        'SELECT COUNT(DISTINCT m.id) AS n FROM meals m JOIN meal_items i ON i.meal_id = m.id WHERE m.date = ?',
        date,
      ),
      'cierre': await _count(db, 'SELECT COUNT(*) AS n FROM day_closes WHERE date = ?', date),
    };
    for (final r in await db.customSelect(
      'SELECT l.habit_id AS id FROM habit_logs l JOIN habits h ON h.id = l.habit_id '
      'WHERE l.date = ? AND l.value > 0 AND (h.target IS NULL OR l.value >= h.target)',
      variables: [Variable.withString(date)],
    ).get()) {
      events['habit:${r.data['id']}'] = 1;
    }
    final minutes = <AppCategory, int>{};
    for (final u in await (db.select(db.appUsageDays)..where((t) => t.date.equals(date))).get()) {
      final c = classes[u.package] ?? AppCategory.sinClasificar;
      minutes[c] = (minutes[c] ?? 0) + u.minutes;
    }
    final earned = earnedByRule(events, earnRules);
    final spent = spentByCategory(minutes, costRules);
    await db.transaction(() async {
      await (db.delete(db.tokenDays)..where((t) => t.date.equals(date))).go();
      for (final e in earned.entries) {
        await db.into(db.tokenDays).insert(TokenDaysCompanion.insert(date: date, source: e.key, earned: Value(e.value)));
      }
      for (final e in spent.entries) {
        await db.into(db.tokenDays).insert(
              TokenDaysCompanion.insert(date: date, source: 'gasto:${e.key.code}', spent: Value(e.value)),
            );
      }
    });
  }
}

Future<int> _count(UserDb db, String sql, String date) async =>
    (await db.customSelect(sql, variables: [Variable.withString(date)]).getSingle()).data['n'] as int;

/// Whether opening an app of [category] should ask first: tokens on, the
/// category priced by the user and no tokens left. Read from the database,
/// not from providers that may still be loading.
Future<bool> outOfTokensFor(WidgetRef ref, AppCategory category) async {
  final settings = ref.read(settingsRepositoryProvider);
  final map = {
    for (final k in [TokenKey.enabled, TokenKey.pending, TokenKey.pendingSince])
      if (await settings.get(k) case final v?) k: v,
  };
  final wait = ref.read(currentAssumptionsProvider).integer(A.tokensToggleWaitH);
  if (!switchOf(map).enabledAt(ref.read(clockProvider)(), wait)) return false;
  final db = ref.read(userDbProvider);
  final priced = await (db.select(db.tokenCostRules)..where((t) => t.category.equals(category.code))).getSingleOrNull();
  if (priced == null) return false;
  final row = await db.customSelect('SELECT COALESCE(SUM(earned) - SUM(spent), 0) AS b FROM token_days').getSingle();
  return (row.data['b'] as int) <= 0;
}
