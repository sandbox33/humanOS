import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 9 → 10 (B5, money from real income): two new tables, empty.
Future<void> migrateV9ToV10(Migrator m, UserDb db) async {
  await m.createTable(db.payWeeks);
  await m.createTable(db.cashCounts);
}
