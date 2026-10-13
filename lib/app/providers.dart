import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../data/reference_db.dart';
import '../data/settings.dart';
import '../data/user_db.dart';

/// The user database. Overridden in `main()` and in tests.
final userDbProvider = Provider<UserDb>(
  (ref) => throw StateError('userDbProvider se configura en main()'),
);

/// The installed reference database, or null when the build has none.
final referenceDbProvider = Provider<ReferenceDb?>((ref) => null);

/// Wall clock, replaceable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Today's calendar day. Refreshed when the app resumes and every minute.
class TodayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(ref.watch(clockProvider)());

  void refresh() {
    final now = dateOnly(ref.read(clockProvider)());
    if (now != state) state = now;
  }
}

final todayProvider = NotifierProvider<TodayNotifier, DateTime>(TodayNotifier.new);

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository(ref.watch(userDbProvider)));

final settingsMapProvider = StreamProvider<Map<String, String>>(
  (ref) => ref.watch(settingsRepositoryProvider).watchAll(),
);

final settingsProvider = Provider<AppSettingsState>((ref) {
  final map = ref.watch(settingsMapProvider).value;
  return map == null ? const AppSettingsState() : AppSettingsState.fromMap(map);
});

/// Every model constant, from the SUPUESTOS table (catalogue defaults for
/// keys not stored yet).
final assumptionsProvider = StreamProvider<Assumptions>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.assumptionRows).watch().map(
        (rows) => Assumptions({for (final r in rows) r.key: r.value}),
      );
});

/// Assumptions available synchronously (defaults until the stream emits).
final currentAssumptionsProvider = Provider<Assumptions>(
  (ref) => ref.watch(assumptionsProvider).value ?? Assumptions.defaults(),
);

final profileProvider = StreamProvider<ProfileRow?>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.profile).watchSingleOrNull();
});

/// Frame-time watchdog: once frames exceed 16 ms the CRT effect stays off
/// for the rest of the session.
class CrtGovernor extends Notifier<bool> {
  @override
  bool build() => false;

  void markDegraded() {
    if (!state) state = true;
  }
}

final crtGovernorProvider = NotifierProvider<CrtGovernor, bool>(CrtGovernor.new);

final crtEnabledProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider).crtHeaders && !ref.watch(crtGovernorProvider),
);

/// What happened to the reference database at launch (diagnosis screen).
class ReferenceStatus {
  const ReferenceStatus({required this.installed, this.updated = false, this.errorEs});
  final bool installed;

  /// The copy was (re)written from the APK in this launch.
  final bool updated;
  final String? errorEs;
}

final referenceStatusProvider =
    Provider<ReferenceStatus>((ref) => const ReferenceStatus(installed: false));
