import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 6 → 7 (B2, screen time): only new tables, empty. Usage history
/// is imported from the phone on the first read.
Future<void> migrateV6ToV7(Migrator m, UserDb db) async {
  await m.createTable(db.appClasses);
  await m.createTable(db.appUsageDays);
}
