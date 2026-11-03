import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 5 → 6 (B1, the day's schedule): only new tables, empty. The user
/// builds the template; no block or time is preloaded.
Future<void> migrateV5ToV6(Migrator m, UserDb db) async {
  await m.createTable(db.scheduleBlocks);
  await m.createTable(db.scheduleAdjustments);
}
