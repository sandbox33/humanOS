import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

int? _clock(String? text) {
  if (text == null) return null;
  try {
    return parseClock(text);
  } on FormatException {
    return null;
  }
}

/// Active template rows as engine blocks (rows with a broken time are left
/// out rather than guessed).
List<BlockTemplate> templatesOf(List<ScheduleBlockRow> rows) => [
      for (final r in rows)
        if (r.status == 'activo' && _clock(r.startClock) != null)
          BlockTemplate(
            id: r.id,
            kind: BlockKind.parse(r.kind),
            label: r.label,
            startMin: _clock(r.startClock)!,
            durationMin: r.durationMin,
            daysMask: r.daysMask,
            alarm: r.alarm,
          ),
    ];

DayAdjustment? adjustmentOf(ScheduleAdjustmentRow r) {
  final action = AdjustAction.parse(r.action);
  if (action == null) return null;
  return DayAdjustment(
    action: action,
    blockId: r.blockId,
    startMin: _clock(r.startClock),
    endMin: _clock(r.endClock),
    kind: r.kind == null ? null : BlockKind.parse(r.kind),
    label: r.label,
    alarm: r.alarm,
  );
}

/// The weekly template and the one-day adjustments.
class ScheduleRepository {
  ScheduleRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  Stream<List<ScheduleBlockRow>> watchBlocks() =>
      (_db.select(_db.scheduleBlocks)..orderBy([(t) => OrderingTerm.asc(t.startClock), (t) => OrderingTerm.asc(t.id)]))
          .watch();

  Future<int> addBlock({
    required BlockKind kind,
    required String startClock,
    required int daysMask,
    String? label,
    int? durationMin,
    bool alarm = false,
  }) =>
      _db.into(_db.scheduleBlocks).insert(ScheduleBlocksCompanion.insert(
            kind: kind.code,
            label: Value(label == null || label.trim().isEmpty ? null : label.trim()),
            startClock: startClock,
            durationMin: Value(durationMin),
            daysMask: daysMask,
            alarm: Value(alarm),
            createdAt: stampOf(_now()),
          ));

  Future<void> updateBlock(
    int id, {
    required BlockKind kind,
    required String startClock,
    required int daysMask,
    String? label,
    int? durationMin,
    bool alarm = false,
  }) =>
      (_db.update(_db.scheduleBlocks)..where((t) => t.id.equals(id))).write(ScheduleBlocksCompanion(
        kind: Value(kind.code),
        label: Value(label == null || label.trim().isEmpty ? null : label.trim()),
        startClock: Value(startClock),
        durationMin: Value(durationMin),
        daysMask: Value(daysMask),
        alarm: Value(alarm),
      ));

  Future<void> setStatus(int id, String status) =>
      (_db.update(_db.scheduleBlocks)..where((t) => t.id.equals(id))).write(ScheduleBlocksCompanion(status: Value(status)));

  /// Adjustments of the dates between [from] and [to] (inclusive).
  Stream<List<ScheduleAdjustmentRow>> watchAdjustments(String from, String to) => (_db.select(_db.scheduleAdjustments)
        ..where((t) => t.date.isBetweenValues(from, to))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<int> addAdjustment({
    required DateTime date,
    required AdjustAction action,
    int? blockId,
    String? startClock,
    String? endClock,
    BlockKind? kind,
    String? label,
    bool alarm = false,
  }) =>
      _db.into(_db.scheduleAdjustments).insert(ScheduleAdjustmentsCompanion.insert(
            date: isoDate(date),
            action: action.code,
            blockId: Value(blockId),
            startClock: Value(startClock),
            endClock: Value(endClock),
            kind: Value(kind?.code),
            label: Value(label),
            alarm: Value(alarm),
            createdAt: stampOf(_now()),
          ));

  /// Back to the template for [date].
  Future<void> clearDay(DateTime date) =>
      (_db.delete(_db.scheduleAdjustments)..where((t) => t.date.equals(isoDate(date)))).go();
}
