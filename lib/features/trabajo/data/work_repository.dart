import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';

String _two(int v) => v.toString().padLeft(2, '0');

/// Local wall-clock timestamp as stored: `YYYY-MM-DDTHH:MM:SS`.
String stampOf(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
    'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

DateTime? parseStamp(String? text) => text == null ? null : DateTime.tryParse(text);

/// Template statuses (user data with pause and archive).
enum TemplateStatus {
  activo('activo', 'ACTIVA'),
  pausado('pausado', 'PAUSADA'),
  archivado('archivado', 'ARCHIVADA');

  const TemplateStatus(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static TemplateStatus parse(String? code) =>
      TemplateStatus.values.firstWhere((s) => s.code == code, orElse: () => TemplateStatus.activo);
}

WorkEntry entryFromRow(WorkEntryRow r) => WorkEntry(
      id: r.id,
      date: parseIsoDate(r.date),
      label: r.label,
      kind: WorkKind.parse(r.kind),
      start: parseStamp(r.startTs),
      end: parseStamp(r.endTs),
      minutes: r.minutes,
      rateCentsPerHour: r.rateCentsPerHour,
      earnedCents: r.earnedCents,
      note: r.note,
    );

WorkSchedule scheduleOf(WorkTemplateRow t) {
  int? clock(String? text) {
    if (text == null) return null;
    try {
      return parseClock(text);
    } on FormatException {
      return null;
    }
  }

  return WorkSchedule(
    label: t.label,
    startMin: clock(t.startClock),
    endMin: clock(t.endClock),
    breakStartMin: clock(t.breakStart),
    breakMinutes: t.breakMinutes,
    daysMask: t.daysMask,
    heatExposure: t.heatExposure,
  );
}

/// `work_entries` and `work_templates`.
class WorkRepository {
  WorkRepository(this._db);
  final UserDb _db;

  Stream<List<WorkEntryRow>> watchEntriesSince(String fromDate) => (_db.select(_db.workEntries)
        ..where((t) => t.date.isBiggerOrEqualValue(fromDate))
        ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Stream<List<WorkTemplateRow>> watchTemplates() => (_db.select(_db.workTemplates)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<int> addEntry(WorkEntry e, {int? templateId, DateTime? now}) =>
      _db.into(_db.workEntries).insert(
            WorkEntriesCompanion.insert(
              date: isoDate(e.date),
              label: e.label,
              kind: e.kind.code,
              startTs: Value(e.start == null ? null : stampOf(e.start!)),
              endTs: Value(e.end == null ? null : stampOf(e.end!)),
              minutes: e.minutes,
              rateCentsPerHour: Value(e.rateCentsPerHour),
              earnedCents: Value(e.earnedCents),
              note: Value(e.note),
              createdAt: stampOf(now ?? DateTime.now()),
              templateId: Value(templateId),
            ),
          );

  Future<void> replaceEntry(int id, WorkEntry e) =>
      (_db.update(_db.workEntries)..where((t) => t.id.equals(id))).write(
        WorkEntriesCompanion(
          date: Value(isoDate(e.date)),
          label: Value(e.label),
          kind: Value(e.kind.code),
          startTs: Value(e.start == null ? null : stampOf(e.start!)),
          endTs: Value(e.end == null ? null : stampOf(e.end!)),
          minutes: Value(e.minutes),
          rateCentsPerHour: Value(e.rateCentsPerHour),
          earnedCents: Value(e.earnedCents),
          note: Value(e.note),
        ),
      );

  Future<void> deleteEntry(int id) => (_db.delete(_db.workEntries)..where((t) => t.id.equals(id))).go();

  Future<int> saveTemplate(WorkTemplatesCompanion t, {int? id}) async {
    if (id == null) return _db.into(_db.workTemplates).insert(t);
    await (_db.update(_db.workTemplates)..where((row) => row.id.equals(id))).write(t);
    return id;
  }

  Future<void> setTemplateStatus(int id, TemplateStatus status) =>
      (_db.update(_db.workTemplates)..where((t) => t.id.equals(id)))
          .write(WorkTemplatesCompanion(status: Value(status.code)));

  Future<void> deleteTemplate(int id) =>
      (_db.delete(_db.workTemplates)..where((t) => t.id.equals(id))).go();
}
