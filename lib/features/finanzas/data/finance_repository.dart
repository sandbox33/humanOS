import 'package:drift/drift.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;

Expense expenseFromRow(ExpenseRow r) => Expense(
      date: parseIsoDate(r.date),
      category: r.category,
      amountCents: r.amountCents,
      planned: r.planned,
      impulse: r.impulse,
      note: r.note,
    );

Goal goalFromRow(GoalRow r) => Goal(
      id: r.id,
      parentId: r.parentId,
      title: r.title,
      targetCents: r.targetCents,
      savedCents: r.savedCents,
      priority: r.priority,
      status: GoalStatus.parse(r.status),
      actualCents: r.actualCents,
    );

/// Expenses, categories, goals and pauses. Every row is the user's.
class FinanceRepository {
  FinanceRepository(this._db, this._now);
  final UserDb _db;
  final DateTime Function() _now;

  // ------------------------------------------------------------ expenses

  Stream<List<ExpenseRow>> watchExpensesSince(String fromDate) => (_db.select(_db.expenses)
        ..where((t) => t.date.isBiggerOrEqualValue(fromDate))
        ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
      .watch();

  Future<int> addExpense({
    required DateTime date,
    required String category,
    required int amountCents,
    bool planned = false,
    bool impulse = false,
    String? note,
  }) =>
      _db.into(_db.expenses).insert(ExpensesCompanion.insert(
            date: isoDate(date),
            category: category.trim(),
            amountCents: amountCents,
            planned: Value(planned),
            impulse: Value(impulse),
            note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
            createdAt: stampOf(_now()),
          ));

  Future<void> deleteExpense(int id) => (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------- categories

  Stream<List<ExpenseCategoryRow>> watchCategories() => (_db.select(_db.expenseCategories)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  /// Creates [label] or brings an archived one back; returns its label.
  Future<String> ensureCategory(String label) async {
    final clean = label.trim();
    final existing =
        await (_db.select(_db.expenseCategories)..where((t) => t.label.equals(clean))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.expenseCategories).insert(
            ExpenseCategoriesCompanion.insert(label: clean, createdAt: stampOf(_now())),
          );
    } else if (existing.status != 'activo') {
      await (_db.update(_db.expenseCategories)..where((t) => t.id.equals(existing.id)))
          .write(const ExpenseCategoriesCompanion(status: Value('activo')));
    }
    return clean;
  }

  Future<void> archiveCategory(int id) => (_db.update(_db.expenseCategories)..where((t) => t.id.equals(id)))
      .write(const ExpenseCategoriesCompanion(status: Value('archivado')));

  // --------------------------------------------------------------- goals

  Future<List<GoalRow>> goals() =>
      (_db.select(_db.goals)..orderBy([(t) => OrderingTerm.asc(t.priority), (t) => OrderingTerm.asc(t.id)])).get();

  Stream<List<GoalRow>> watchGoals() =>
      (_db.select(_db.goals)..orderBy([(t) => OrderingTerm.asc(t.priority), (t) => OrderingTerm.asc(t.id)])).watch();

  /// New goals go to the end of the user's order.
  Future<int> addGoal({required String title, int? targetCents, int? parentId}) async {
    final last = await (_db.selectOnly(_db.goals)..addColumns([_db.goals.priority.max()])).getSingle();
    final priority = (last.read(_db.goals.priority.max()) ?? -1) + 1;
    return _db.into(_db.goals).insert(GoalsCompanion.insert(
          title: title.trim(),
          targetCents: Value(targetCents),
          parentId: Value(parentId),
          priority: Value(priority),
          createdAt: stampOf(_now()),
        ));
  }

  Future<void> updateGoal(int id, {String? title, Value<int?> targetCents = const Value.absent()}) =>
      (_db.update(_db.goals)..where((t) => t.id.equals(id))).write(GoalsCompanion(
        title: title == null ? const Value.absent() : Value(title.trim()),
        targetCents: targetCents,
      ));

  /// Adds [cents] (may be negative to correct) to what is saved; never
  /// below zero.
  Future<void> addSaved(int id, int cents) => _db.transaction(() async {
        final g = await (_db.select(_db.goals)..where((t) => t.id.equals(id))).getSingle();
        final next = g.savedCents + cents;
        await (_db.update(_db.goals)..where((t) => t.id.equals(id)))
            .write(GoalsCompanion(savedCents: Value(next < 0 ? 0 : next)));
      });

  Future<void> setStatus(int id, GoalStatus status) => (_db.update(_db.goals)..where((t) => t.id.equals(id)))
      .write(GoalsCompanion(status: Value(status.code)));

  /// Completion keeps the real cost next to the estimate.
  Future<void> complete(int id, {int? actualCents}) => (_db.update(_db.goals)..where((t) => t.id.equals(id)))
      .write(GoalsCompanion(
        status: Value(GoalStatus.completado.code),
        completedAt: Value(stampOf(_now())),
        actualCents: Value(actualCents),
      ));

  /// Swaps [id] with its neighbour among goals of the same parent
  /// ([up] = earlier).
  Future<void> move(int id, {required bool up}) => _db.transaction(() async {
        final all = await (_db.select(_db.goals)
              ..orderBy([(t) => OrderingTerm.asc(t.priority), (t) => OrderingTerm.asc(t.id)]))
            .get();
        final me = all.firstWhere((g) => g.id == id);
        final siblings = [for (final g in all) if (g.parentId == me.parentId) g];
        final i = siblings.indexWhere((g) => g.id == id);
        final j = up ? i - 1 : i + 1;
        if (j < 0 || j >= siblings.length) return;
        // Rewrite the siblings' order 0..n so ties disappear.
        final order = [...siblings]..removeAt(i);
        order.insert(j, me);
        for (var k = 0; k < order.length; k++) {
          await (_db.update(_db.goals)..where((t) => t.id.equals(order[k].id)))
              .write(GoalsCompanion(priority: Value(k)));
        }
      });

  // -------------------------------------------------------------- pauses

  Stream<List<PurchasePauseRow>> watchPauses() => (_db.select(_db.purchasePauses)
        ..where((t) => t.status.equals('esperando'))
        ..orderBy([(t) => OrderingTerm.asc(t.untilTs)]))
      .watch();

  Future<int> addPause({required String category, required int amountCents, required DateTime until, String? note}) =>
      _db.into(_db.purchasePauses).insert(PurchasePausesCompanion.insert(
            category: category.trim(),
            amountCents: amountCents,
            note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
            createdAt: stampOf(_now()),
            untilTs: stampOf(until),
          ));

  /// The user decided: [bought] logs the expense today (unplanned).
  Future<void> resolvePause(PurchasePauseRow p, {required bool bought}) => _db.transaction(() async {
        await (_db.update(_db.purchasePauses)..where((t) => t.id.equals(p.id)))
            .write(PurchasePausesCompanion(status: Value(bought ? 'comprado' : 'descartado')));
        if (bought) {
          await addExpense(date: _now(), category: p.category, amountCents: p.amountCents, note: p.note);
        }
      });
}
