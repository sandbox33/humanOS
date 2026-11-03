// Drift column checks reference their own getter by design.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

/// The user's DNS lists (B3): domains to block and domains that must keep
/// working. Nothing is preloaded.
@DataClassName('DnsDomainRow')
class DnsDomains extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get domain => text().unique()();
  TextColumn get list => text().check(list.isIn(const ['bloquear', 'permitir']))();
  TextColumn get createdAt => text()();
}
