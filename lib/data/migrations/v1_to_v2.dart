import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart' show A, Assumptions;

import '../user_db.dart';

/// Assumption keys of schema 1 that no longer exist (the sweat-rate test,
/// the hydration goal and the RHR part of RECUPERACIÓN).
const removedAssumptionKeysV2 = [
  'sweat_replace_min_frac',
  'sweat_replace_max_frac',
  'sweat_na_mmol_l',
  'body_mass_loss_warn_pct',
  'hydration_goal_fraction',
  'attr_rhr_zero_sd',
];

/// Label of the template and entries created from the old fixed shift.
const migratedWorkLabel = 'Trabajo';

String _two(int v) => v.toString().padLeft(2, '0');

int? _clockMinutes(Object? text) {
  if (text is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String _stamp(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}T${_two(t.hour)}:${_two(t.minute)}:00';

/// Schema 1 → 2 (flexible work). Every row survives:
///
/// * the fixed shift of the profile becomes the user's first work template
///   (same hours, every day planned, editable) and every logged workday
///   (effort LOW/MEDIUM/HIGH) becomes a work entry with those hours and
///   unknown earnings;
/// * heat hours become integer minutes; money becomes integer cents;
/// * the sweat-test columns are dropped (the app keeps an encrypted copy of
///   the file taken before the migration);
/// * NUTRICIÓN joins the attribute list.
Future<void> migrateV1ToV2(Migrator m, UserDb db) async {
  final now = DateTime.now();
  final shift = await db
      .customSelect('SELECT shift_start, shift_end, lunch_start FROM profile WHERE id = 1')
      .getSingleOrNull();
  final lunchRow = await db
      .customSelect("SELECT value FROM assumptions WHERE key = 'lunch_duration_min'")
      .getSingleOrNull();

  await m.createTable(db.workTemplates);
  await m.createTable(db.workEntries);

  final old = shift?.data ?? const <String, Object?>{};
  final start = _clockMinutes(old['shift_start']);
  final end = _clockMinutes(old['shift_end']);
  final lunch = _clockMinutes(old['lunch_start']);
  if (start != null && end != null) {
    // v3.0 always seeded this assumption; its catalog value covers a file
    // where it is missing.
    final breakMinutes =
        ((lunchRow?.data['value'] as num?) ?? Assumptions.defaults()[A.lunchDurationMin]).round();
    final heat = await db
        .customSelect('SELECT 1 FROM daily_logs WHERE heat_hours > 0 LIMIT 1')
        .getSingleOrNull();
    final templateId = await db.into(db.workTemplates).insert(
          WorkTemplatesCompanion.insert(
            label: migratedWorkLabel,
            kind: 'estable',
            startClock: Value(old['shift_start']! as String),
            endClock: Value(old['shift_end']! as String),
            breakStart: Value(lunch == null ? null : old['lunch_start']! as String),
            breakMinutes: Value(lunch == null || breakMinutes <= 0 ? null : breakMinutes),
            daysMask: const Value(0x7F),
            heatExposure: Value(heat != null),
            createdAt: _stamp(now),
          ),
        );
    var span = end - start;
    if (span <= 0) span += 24 * 60;
    final paid = (lunch != null && breakMinutes > 0 && span > breakMinutes) ? span - breakMinutes : span;
    final workdays = await db
        .customSelect(
          "SELECT date FROM daily_logs WHERE work_effort IN ('LOW', 'MEDIUM', 'HIGH') ORDER BY date",
        )
        .get();
    for (final row in workdays) {
      final date = row.data['date'] as String;
      final parts = date.split('-').map(int.parse).toList();
      final begin = DateTime(parts[0], parts[1], parts[2]).add(Duration(minutes: start));
      final finish = begin.add(Duration(minutes: span));
      await db.into(db.workEntries).insert(
            WorkEntriesCompanion.insert(
              date: date,
              label: migratedWorkLabel,
              kind: 'estable',
              startTs: Value(_stamp(begin)),
              endTs: Value(_stamp(finish)),
              minutes: paid,
              note: const Value('Migrado del registro de turno de la v3.0'),
              createdAt: _stamp(now),
              templateId: Value(templateId),
            ),
          );
    }
  }

  // Profile: the fixed shift columns go away.
  await m.alterTable(TableMigration(db.profile));

  // Daily logs: sweat test out, heat in minutes, new 1-tap columns.
  await m.alterTable(
    TableMigration(
      db.dailyLogs,
      columnTransformer: {
        db.dailyLogs.heatMinutes: const CustomExpression<int>('CAST(ROUND(heat_hours * 60) AS INTEGER)'),
      },
      newColumns: [
        db.dailyLogs.heatMinutes,
        db.dailyLogs.sweatFeel,
        db.dailyLogs.effortFeel,
        db.dailyLogs.mood,
        db.dailyLogs.thermoPre,
        db.dailyLogs.thermoBreak,
      ],
    ),
  );

  // Money in integer cents.
  await m.alterTable(
    TableMigration(
      db.purchases,
      columnTransformer: {
        db.purchases.totalCents: const CustomExpression<int>('CAST(ROUND(total_usd * 100) AS INTEGER)'),
      },
      newColumns: [db.purchases.totalCents],
    ),
  );
  await m.alterTable(
    TableMigration(
      db.pantryItems,
      columnTransformer: {
        db.pantryItems.priceCentsPerKg: const CustomExpression<int>(
          'CAST(ROUND(price_usd_per_kg * 100) AS INTEGER)',
        ),
      },
      newColumns: [db.pantryItems.priceCentsPerKg],
    ),
  );

  // Attributes: NUTRICIÓN joins the CHECK list.
  await m.alterTable(TableMigration(db.attributes));

  await db.customStatement(
    'DELETE FROM assumptions WHERE key IN '
    '(${List.filled(removedAssumptionKeysV2.length, '?').join(', ')})',
    removedAssumptionKeysV2,
  );

  // H2O counts the thermos reminders acknowledged (before work, break).
  await db.customStatement(
    "UPDATE habits SET source = 'hydration_ack', metric = 'min', target = 2 "
    "WHERE source = 'hydration_pct'",
  );
}
