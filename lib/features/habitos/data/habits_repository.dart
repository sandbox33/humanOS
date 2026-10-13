import 'package:drift/drift.dart';

import '../../../data/user_db.dart';

class HabitsRepository {
  HabitsRepository(this._db);
  final UserDb _db;

  Stream<List<HabitRow>> watchHabits() =>
      (_db.select(_db.habits)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Stream<List<HabitLogRow>> watchLogs() => _db.select(_db.habitLogs).watch();

  Future<List<HabitRow>> habits() => _db.select(_db.habits).get();

  Future<void> setValue(int habitId, String date, double value) =>
      _db.into(_db.habitLogs).insertOnConflictUpdate(
            HabitLogsCompanion.insert(habitId: habitId, date: date, value: value),
          );

  Future<void> clearValue(int habitId, String date) => (_db.delete(_db.habitLogs)
        ..where((t) => t.habitId.equals(habitId) & t.date.equals(date)))
      .go();

  Future<void> updateHabit(HabitRow habit, {String? alias, double? target, bool? active, double? weight}) =>
      (_db.update(_db.habits)..where((t) => t.id.equals(habit.id))).write(HabitsCompanion(
        alias: alias == null ? const Value.absent() : Value(alias),
        target: target == null ? const Value.absent() : Value(target),
        active: active == null ? const Value.absent() : Value(active),
        weight: weight == null ? const Value.absent() : Value(weight),
      ));

  Future<void> saveStreak(String kind, {required int current, required int best, required int tokens}) =>
      _db.into(_db.streakState).insertOnConflictUpdate(StreakStateCompanion.insert(
            kind: kind,
            current: current,
            best: best,
            repairTokens: tokens,
          ));

  Stream<List<AttributeRow>> watchAttributes() =>
      (_db.select(_db.attributes)..orderBy([(t) => OrderingTerm.asc(t.date)])).watch();

  Future<void> saveAttribute(String date, String attr, double value) =>
      _db.into(_db.attributes).insertOnConflictUpdate(
            AttributesCompanion.insert(date: date, attr: attr, value: value),
          );
}
