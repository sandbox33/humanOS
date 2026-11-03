import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

/// The user's blocked and allowed domains.
class DnsRepository {
  DnsRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  Stream<List<DnsDomainRow>> watchAll() =>
      (_db.select(_db.dnsDomains)..orderBy([(t) => OrderingTerm.asc(t.domain)])).watch();

  Future<List<DnsDomainRow>> all() =>
      (_db.select(_db.dnsDomains)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Adds [domain] to [list]; a domain already in the other list moves.
  Future<void> put(String domain, DnsList list) => _db.into(_db.dnsDomains).insert(
        DnsDomainsCompanion.insert(domain: domain, list: list.code, createdAt: stampOf(_now())),
        onConflict: DoUpdate((_) => DnsDomainsCompanion(list: Value(list.code)), target: [_db.dnsDomains.domain]),
      );

  Future<void> remove(int id) => (_db.delete(_db.dnsDomains)..where((t) => t.id.equals(id))).go();
}
