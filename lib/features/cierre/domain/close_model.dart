import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../pantalla/domain/screen_model.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

/// B6 settings (the user's own words; nothing preset).
abstract final class CloseKey {
  /// The honesty question; absent until the user writes one.
  static const question = 'close_honesty_question';

  /// The phrase shown after a "sí", written by the user for next time.
  static const phrase = 'close_honesty_phrase';
}

class CloseRepository {
  CloseRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  Stream<List<DayCloseRow>> watchCloses() =>
      (_db.select(_db.dayCloses)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  Stream<List<DayCloseInteractionRow>> watchInteractions() => _db.select(_db.dayCloseInteractions).watch();

  Stream<List<InteractionCategoryRow>> watchCategories() => (_db.select(_db.interactionCategories)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<int> addCategory(String label) => _db.into(_db.interactionCategories).insert(
        InteractionCategoriesCompanion.insert(label: label.trim(), createdAt: stampOf(_now())),
      );

  Future<void> archiveCategory(int id) => (_db.update(_db.interactionCategories)..where((t) => t.id.equals(id)))
      .write(const InteractionCategoriesCompanion(status: Value('archivado')));

  /// Saves (or replaces) the close of [date].
  Future<void> save({
    required String date,
    required int mood,
    required int energy,
    required Map<int, int> minutes,
    bool? honestyYes,
    String? honestyNote,
  }) =>
      _db.transaction(() async {
        await _db.into(_db.dayCloses).insertOnConflictUpdate(DayClosesCompanion.insert(
              date: date,
              mood: mood,
              energy: energy,
              honestyYes: Value(honestyYes),
              honestyNote: Value(honestyNote == null || honestyNote.trim().isEmpty ? null : honestyNote.trim()),
              updatedAt: stampOf(_now()),
            ));
        await (_db.delete(_db.dayCloseInteractions)..where((t) => t.date.equals(date))).go();
        for (final e in minutes.entries) {
          if (e.value <= 0) continue;
          await _db.into(_db.dayCloseInteractions).insert(
                DayCloseInteractionsCompanion.insert(date: date, categoryId: e.key, minutes: e.value),
              );
        }
      });
}

final closeRepositoryProvider = Provider<CloseRepository>(
  (ref) => CloseRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final closeRowsProvider = StreamProvider<List<DayCloseRow>>((ref) => ref.watch(closeRepositoryProvider).watchCloses());

final closeInteractionRowsProvider = StreamProvider<List<DayCloseInteractionRow>>(
  (ref) => ref.watch(closeRepositoryProvider).watchInteractions(),
);

final interactionCategoriesProvider = StreamProvider<List<InteractionCategoryRow>>(
  (ref) => ref.watch(closeRepositoryProvider).watchCategories(),
);

/// Every closed day as the engine sees it.
final closesProvider = Provider<List<DayClose>>((ref) {
  final minutes = <String, Map<int, int>>{};
  for (final r in ref.watch(closeInteractionRowsProvider).value ?? const <DayCloseInteractionRow>[]) {
    (minutes[r.date] ??= {})[r.categoryId] = r.minutes;
  }
  return [
    for (final r in ref.watch(closeRowsProvider).value ?? const <DayCloseRow>[])
      DayClose(
        date: parseIsoDate(r.date),
        mood: r.mood,
        energy: r.energy,
        interactionMinutes: minutes[r.date] ?? const {},
        honestyYes: r.honestyYes,
      ),
  ];
});

final closeTrendsProvider = Provider<CloseTrends?>((ref) {
  final a = ref.watch(currentAssumptionsProvider);
  return closeTrends(
    ref.watch(closesProvider),
    minDays: a.integer(A.closeTrendMinDays),
    window: a.integer(A.closeTrendWindowDays),
  );
});

/// Reference for the minutes with people: today's minutes in the apps the
/// user classed as communication (calls with the screen off do not count;
/// the call log is not read).
final communicationMinutesTodayProvider = Provider<int?>((ref) {
  final intervals = ref.watch(todayUsageProvider);
  if (intervals == null) return null;
  final classes = ref.watch(effectiveClassesProvider);
  final byApp = minutesByApp(intervals, ref.watch(todayProvider));
  return minutesByCategory(byApp, classes)[AppCategory.comunicacion] ?? 0;
});
