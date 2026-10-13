import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';

/// A finished set ready to be stored.
class SetDraft {
  const SetDraft({
    required this.exerciseId,
    required this.loadKg,
    required this.reps,
    required this.validReps,
    required this.reachedFailure,
    this.tutS,
    this.restPauseReps = 0,
    this.isWarmup = false,
    this.tapsMs = const [],
  });

  final int exerciseId;
  final double loadKg;
  final int reps;
  final int validReps;
  final bool reachedFailure;
  final double? tutS;
  final int restPauseReps;
  final bool isWarmup;
  final List<int> tapsMs;
}

class TrainingRepository {
  TrainingRepository(this._db);
  final UserDb _db;

  Stream<List<SessionRow>> watchSessions() => (_db.select(_db.sessions)
        ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Stream<List<SetRow>> watchSets() => _db.select(_db.sets).watch();

  Stream<List<PersonalRecordRow>> watchRecords() => _db.select(_db.personalRecords).watch();

  /// History in the engine's format.
  static List<SessionRecord> toHistory(List<SessionRow> sessions, List<SetRow> sets) {
    final bySession = <int, List<SetRecord>>{};
    for (final s in sets) {
      (bySession[s.sessionId] ??= []).add(SetRecord(
        exerciseId: s.exerciseId,
        loadKg: s.loadKg,
        reps: s.reps,
        validReps: s.validReps,
        reachedFailure: s.reachedFailure,
        isWarmup: s.isWarmup,
        restPauseReps: s.restPauseReps,
      ));
    }
    return [
      for (final s in sessions)
        SessionRecord(
          date: parseIsoDate(s.date),
          template: TrainingTemplate.parse(s.template),
          mode: SessionMode.parse(s.mode),
          readiness: ReadinessBand.parse(s.readiness),
          overridden: s.readinessOverridden,
          sets: bySession[s.id] ?? const [],
        ),
    ];
  }

  /// Stores a session with its sets and updates personal records.
  Future<int> saveSession({
    required String date,
    required TrainingTemplate template,
    required SessionMode mode,
    required ReadinessBand? readiness,
    required bool overridden,
    required List<SetDraft> sets,
    double? avgHr,
    double? maxHr,
    String? notes,
    Map<int, ({double loadKg, int reps, double e1rm})> newRecords = const {},
  }) {
    return _db.transaction(() async {
      final sessionId = await _db.into(_db.sessions).insert(SessionsCompanion.insert(
            date: date,
            template: template.code,
            readiness: Value(readiness?.code),
            readinessOverridden: Value(overridden),
            avgHr: Value(avgHr),
            maxHr: Value(maxHr),
            notes: Value(notes),
            mode: Value(mode.code),
          ));
      for (final s in sets) {
        await _db.into(_db.sets).insert(SetsCompanion.insert(
              sessionId: sessionId,
              exerciseId: s.exerciseId,
              loadKg: s.loadKg,
              reps: s.reps,
              validReps: s.validReps,
              reachedFailure: s.reachedFailure,
              tutS: Value(s.tutS),
              restPauseReps: Value(s.restPauseReps),
              isWarmup: Value(s.isWarmup),
              repTimestamps: Value(s.tapsMs.isEmpty ? null : jsonEncode(s.tapsMs)),
            ));
      }
      for (final entry in newRecords.entries) {
        await _db.into(_db.personalRecords).insertOnConflictUpdate(
              PersonalRecordsCompanion(
                exerciseId: Value(entry.key),
                loadKg: Value(entry.value.loadKg),
                reps: Value(entry.value.reps),
                e1rm: Value(entry.value.e1rm),
                date: Value(date),
              ),
            );
      }
      return sessionId;
    });
  }

  Future<void> deleteSession(int id) =>
      (_db.delete(_db.sessions)..where((t) => t.id.equals(id))).go();
}
