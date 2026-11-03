import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 2 → 3 (location context and morning alarms). Only new tables:
/// no existing row changes.
Future<void> migrateV2ToV3(Migrator m, UserDb db) async {
  await m.createTable(db.zones);
  await m.createTable(db.contextEvents);
  await m.createTable(db.modeCorrections);
  await m.createTable(db.stateCheckins);
  await m.createTable(db.eventReminders);
  await m.createTable(db.morningAlarms);
}
