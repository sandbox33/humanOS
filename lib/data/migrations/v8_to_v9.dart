import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 8 → 9 (B4, meals and pantry): two new tables, empty.
Future<void> migrateV8ToV9(Migrator m, UserDb db) async {
  await m.createTable(db.foodHandlingFlags);
  await m.createTable(db.receiptLinks);
}
