import 'package:drift/drift.dart';

import '../user_db.dart';

/// Schema 3 → 4: `app_settings.updated_at` (the theme and every other
/// setting record when they changed). Existing rows keep their values; their
/// date is unknown, so it stays NULL.
Future<void> migrateV3ToV4(Migrator m, UserDb db) async {
  await m.addColumn(db.appSettings, db.appSettings.updatedAt);
}
