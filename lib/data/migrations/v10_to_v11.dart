import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 10 → 11 (B6, the day's close): three new tables, empty.
Future<void> migrateV10ToV11(Migrator m, UserDb db) async {
  await m.createTable(db.dayCloses);
  await m.createTable(db.interactionCategories);
  await m.createTable(db.dayCloseInteractions);
}
