import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 4 → 5 (finance advisor): only new tables. Expenses, categories
/// and goals start empty; nothing is preloaded.
Future<void> migrateV4ToV5(Migrator m, UserDb db) async {
  await m.createTable(db.expenseCategories);
  await m.createTable(db.expenses);
  await m.createTable(db.goals);
  await m.createTable(db.purchasePauses);
}
