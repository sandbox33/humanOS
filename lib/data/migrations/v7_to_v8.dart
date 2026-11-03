import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 7 → 8 (B3, DNS filter): one new table, empty. No domain is
/// preloaded.
Future<void> migrateV7ToV8(Migrator m, UserDb db) async {
  await m.createTable(db.dnsDomains);
}
