import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 11 → 12 (B7, leisure tokens, off by default): three new tables,
/// empty. No rule is preloaded.
Future<void> migrateV11ToV12(Migrator m, UserDb db) async {
  await m.createTable(db.tokenEarnRules);
  await m.createTable(db.tokenCostRules);
  await m.createTable(db.tokenDays);
}
