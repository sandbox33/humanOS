import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show TemplateStatus, parseStamp, stampOf;

ContextZone zoneOf(ZoneRow r) => ContextZone(
      id: r.id,
      name: r.name,
      kind: ContextMode.parse(r.kind),
      latitude: r.latitude,
      longitude: r.longitude,
      radiusM: r.radiusM,
      active: TemplateStatus.parse(r.status) == TemplateStatus.activo,
    );

/// Zone transitions only (the manual buttons without a zone are not part
/// of the geofence history).
List<ZoneEvent> zoneEventsOf(List<ContextEventRow> rows) => [
      for (final r in rows)
        if (r.zoneId != null)
          if (ContextTransition.parse(r.transition) case final t?)
            if (parseStamp(r.at) case final at?) ZoneEvent(zoneId: r.zoneId!, transition: t, at: at),
    ];

/// Zones, transitions, corrections, state check-ins and event reminders.
class ContextRepository {
  ContextRepository(this._db);
  final UserDb _db;

  Stream<List<ZoneRow>> watchZones() => (_db.select(_db.zones)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<int> saveZone(ZonesCompanion zone, {int? id}) async {
    if (id == null) return _db.into(_db.zones).insert(zone);
    await (_db.update(_db.zones)..where((t) => t.id.equals(id))).write(zone);
    return id;
  }

  Future<void> setZoneStatus(int id, TemplateStatus status) =>
      (_db.update(_db.zones)..where((t) => t.id.equals(id))).write(ZonesCompanion(status: Value(status.code)));

  /// The zone goes; its past transitions stay (without coordinates).
  Future<void> deleteZone(int id) => (_db.delete(_db.zones)..where((t) => t.id.equals(id))).go();

  /// Transitions of the last [days] days, newest first.
  Stream<List<ContextEventRow>> watchEvents({required DateTime now, int days = 3}) =>
      (_db.select(_db.contextEvents)
            ..where((t) => t.at.isBiggerOrEqualValue(stampOf(now.subtract(Duration(days: days)))))
            ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)]))
          .watch();

  Future<void> addEvent({
    required DateTime at,
    required ContextTransition transition,
    required String source,
    int? zoneId,
    String? plan,
    String? company,
    int? feeling,
  }) =>
      _db.into(_db.contextEvents).insert(ContextEventsCompanion.insert(
            at: stampOf(at),
            transition: transition.code,
            source: source,
            zoneId: Value(zoneId),
            plan: Value(plan),
            company: Value(company),
            feeling: Value(feeling),
          ));

  Stream<ModeCorrectionRow?> watchLatestCorrection() => (_db.select(_db.modeCorrections)
        ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<void> addCorrection({
    required DateTime at,
    required ContextMode inferred,
    required ContextMode corrected,
    required ContextMode? locationMode,
  }) =>
      _db.into(_db.modeCorrections).insert(ModeCorrectionsCompanion.insert(
            at: stampOf(at),
            inferred: inferred.code,
            corrected: corrected.code,
            locationMode: Value(locationMode?.code),
          ));

  Stream<StateCheckinRow?> watchLatestCheckin() => (_db.select(_db.stateCheckins)
        ..orderBy([(t) => OrderingTerm.desc(t.at), (t) => OrderingTerm.desc(t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<void> addCheckin(DateTime at, int value) =>
      _db.into(_db.stateCheckins).insert(StateCheckinsCompanion.insert(at: stampOf(at), value: value));

  Stream<List<EventReminderRow>> watchEventReminders() =>
      (_db.select(_db.eventReminders)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  Future<int> saveEventReminder(EventRemindersCompanion r, {int? id}) async {
    if (id == null) return _db.into(_db.eventReminders).insert(r);
    await (_db.update(_db.eventReminders)..where((t) => t.id.equals(id))).write(r);
    return id;
  }

  Future<void> setEventReminderStatus(int id, TemplateStatus status) =>
      (_db.update(_db.eventReminders)..where((t) => t.id.equals(id)))
          .write(EventRemindersCompanion(status: Value(status.code)));

  Future<void> deleteEventReminder(int id) =>
      (_db.delete(_db.eventReminders)..where((t) => t.id.equals(id))).go();

  Stream<List<MorningAlarmRow>> watchAlarms() =>
      (_db.select(_db.morningAlarms)..orderBy([(t) => OrderingTerm.asc(t.clock), (t) => OrderingTerm.asc(t.id)]))
          .watch();

  Future<int> saveAlarm(MorningAlarmsCompanion a, {int? id}) async {
    if (id == null) return _db.into(_db.morningAlarms).insert(a);
    await (_db.update(_db.morningAlarms)..where((t) => t.id.equals(id))).write(a);
    return id;
  }

  Future<void> setAlarmStatus(int id, TemplateStatus status) =>
      (_db.update(_db.morningAlarms)..where((t) => t.id.equals(id)))
          .write(MorningAlarmsCompanion(status: Value(status.code)));

  Future<void> deleteAlarm(int id) => (_db.delete(_db.morningAlarms)..where((t) => t.id.equals(id))).go();
}
