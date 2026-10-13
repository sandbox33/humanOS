import 'package:drift/drift.dart';

@DataClassName('HabitRow')
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get alias => text()();
  TextColumn get icon => text()();
  RealColumn get weight => real()();
  BoolColumn get isMinimum => boolean()();
  TextColumn get metric => text().withDefault(const Constant('check'))();
  RealColumn get target => real().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Extension: where an automatic value comes from (null = manual).
  TextColumn get source => text().nullable()();
}

@DataClassName('HabitLogRow')
class HabitLogs extends Table {
  IntColumn get habitId => integer().references(Habits, #id)();
  TextColumn get date => text()();
  RealColumn get value => real()();

  @override
  Set<Column<Object>> get primaryKey => {habitId, date};
}

@DataClassName('StreakStateRow')
class StreakState extends Table {
  TextColumn get kind => text()();
  IntColumn get current => integer()();
  IntColumn get best => integer()();
  IntColumn get repairTokens => integer()();

  @override
  Set<Column<Object>> get primaryKey => {kind};
}

@DataClassName('AttributeRow')
class Attributes extends Table {
  TextColumn get date => text()();
  TextColumn get attr => text().check(attr.isIn(
      const ['FUERZA', 'RESISTENCIA', 'RECUPERACION', 'DISCIPLINA']))();
  RealColumn get value => real()();

  @override
  Set<Column<Object>> get primaryKey => {date, attr};
}
