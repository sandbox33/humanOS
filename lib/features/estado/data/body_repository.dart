import 'package:drift/drift.dart';

import '../../../data/user_db.dart';

class BodyRepository {
  BodyRepository(this._db);
  final UserDb _db;

  Stream<List<BodyMetricRow>> watchAll() =>
      (_db.select(_db.bodyMetrics)..orderBy([(t) => OrderingTerm.asc(t.date)])).watch();

  Future<List<BodyMetricRow>> all() =>
      (_db.select(_db.bodyMetrics)..orderBy([(t) => OrderingTerm.asc(t.date)])).get();

  Future<void> setWeight(String date, double kg) => _upsert(
        date,
        BodyMetricsCompanion(weightKg: Value(kg)),
      );

  Future<void> setRestingHr(String date, double bpm) => _upsert(
        date,
        BodyMetricsCompanion(rhrBpm: Value(bpm)),
      );

  Future<void> setMeasures(String date, {double? gripKg, double? waistCm}) => _upsert(
        date,
        BodyMetricsCompanion(
          gripKg: gripKg == null ? const Value.absent() : Value(gripKg),
          waistCm: waistCm == null ? const Value.absent() : Value(waistCm),
        ),
      );

  /// Imports a weight from Health Connect unless the user already logged one.
  Future<bool> importWeightIfMissing(String date, double kg) async {
    final row = await (_db.select(_db.bodyMetrics)..where((t) => t.date.equals(date)))
        .getSingleOrNull();
    if (row?.weightKg != null) return false;
    await setWeight(date, kg);
    return true;
  }

  Future<void> _upsert(String date, BodyMetricsCompanion fields) async {
    await _db.transaction(() async {
      final exists = await (_db.select(_db.bodyMetrics)..where((t) => t.date.equals(date)))
              .getSingleOrNull() !=
          null;
      if (!exists) {
        await _db.into(_db.bodyMetrics).insert(BodyMetricsCompanion.insert(date: date));
      }
      await (_db.update(_db.bodyMetrics)..where((t) => t.date.equals(date))).write(fields);
    });
  }
}
