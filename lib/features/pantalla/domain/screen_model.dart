import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../services/services.dart';
import '../../inicio/domain/schedule_model.dart';
import '../data/screen_repository.dart';

/// Screen-time settings (user data; nothing preset).
abstract final class ScreenKey {
  /// Template block ids during which the chosen categories are hidden.
  static const hideBlocks = 'screen_hide_blocks';

  /// Category codes hidden in those blocks.
  static const hideCategories = 'screen_hide_categories';

  /// 10 s pause before opening an app of the "redes" category.
  static const frictionSocial = 'screen_friction_redes';

  /// Last day already imported from the phone's usage events.
  static const syncedTo = 'screen_synced_to';
}

/// Days of history asked for on the first read (the phone keeps fewer or
/// more; whatever it returns is imported).
const historyDays = 10;

/// Seconds of the optional pause before a social app opens.
const socialFrictionSeconds = 10;

final screenRepositoryProvider = Provider<ScreenRepository>(
  (ref) => ScreenRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final appClassesProvider = StreamProvider<Map<String, AppCategory>>(
  (ref) => ref.watch(screenRepositoryProvider).watchClasses(),
);

/// The category each installed app declares (first suggestion only).
final declaredCategoriesProvider = FutureProvider<Map<String, int>>((ref) async {
  final source = ref.watch(screenTimeProvider);
  if (source == null) return const {};
  try {
    return await source.appCategories();
  } on Object {
    return const {};
  }
});

/// The user's class of each app, or the suggestion while they have not
/// decided.
final effectiveClassesProvider = Provider<Map<String, AppCategory>>((ref) {
  final stored = ref.watch(appClassesProvider).value ?? const {};
  final declared = ref.watch(declaredCategoriesProvider).value ?? const {};
  return {
    for (final e in declared.entries) e.key: suggestCategory(e.value),
    ...stored,
  };
});

/// Today's usage intervals from the last read of the phone's events.
class TodayUsage extends Notifier<List<UsageInterval>?> {
  @override
  List<UsageInterval>? build() => null;

  void set(List<UsageInterval> intervals) => state = intervals;
}

final todayUsageProvider = NotifierProvider<TodayUsage, List<UsageInterval>?>(TodayUsage.new);

final usageDaysProvider = StreamProvider((ref) {
  final from = isoDate(addDays(ref.watch(todayProvider), -6));
  return ref.watch(screenRepositoryProvider).watchDaysSince(from);
});

final hideRuleProvider = Provider<HideRule>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  return HideRule(
    blockIds: {
      for (final p in (map[ScreenKey.hideBlocks] ?? '').split(',')) ?int.tryParse(p),
    },
    categories: {
      for (final p in (map[ScreenKey.hideCategories] ?? '').split(','))
        if (p.isNotEmpty) AppCategory.parse(p),
    },
  );
});

final socialFrictionProvider = Provider<bool>(
  (ref) => (ref.watch(settingsMapProvider).value ?? const {})[ScreenKey.frictionSocial] == '1',
);

/// Categories hidden from the home screen right now.
final hiddenNowProvider = Provider<Set<AppCategory>>((ref) {
  final now = ref.watch(minuteTickProvider).value ?? ref.watch(clockProvider)();
  return hiddenCategoriesAt(
    rule: ref.watch(hideRuleProvider),
    nowMin: now.hour * 60 + now.minute,
    today: ref.watch(dayPlanProvider(0)),
    yesterday: ref.watch(dayPlanProvider(-1)),
  );
});

/// Reads the phone's usage events since the last imported day (the first
/// time, the history the phone still keeps), stores minutes per app per
/// day and keeps today's intervals for the per-block view. Without the
/// usage permission nothing happens.
Future<void> syncAppUsage(WidgetRef ref) async {
  final source = ref.read(screenTimeProvider);
  if (source == null) return;
  final settings = ref.read(settingsRepositoryProvider);
  final now = ref.read(clockProvider)();
  final today = dateOnly(now);
  final synced = await settings.get(ScreenKey.syncedTo);
  var first = synced == null ? addDays(today, -historyDays) : parseIsoDate(synced);
  if (first.isAfter(today)) first = today;
  // A little earlier, so an app already open at midnight is paired.
  final events = await source.events(first.subtract(const Duration(hours: 2)), now);
  if (events == null) return;
  final intervals = intervalsFromEvents(events, until: now);
  final repo = ref.read(screenRepositoryProvider);
  for (var day = first; !day.isAfter(today); day = addDays(day, 1)) {
    final byApp = minutesByApp(intervals, day);
    // Days before the phone's history are left as they are (unknown).
    if (byApp.isEmpty && day.isBefore(today)) continue;
    await repo.replaceDay(isoDate(day), byApp);
  }
  await settings.set(ScreenKey.syncedTo, isoDate(today));
  ref.read(todayUsageProvider.notifier).set([
    for (final i in intervals)
      if (i.end.isAfter(today)) i,
  ]);
}
