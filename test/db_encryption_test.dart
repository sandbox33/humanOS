import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/db_open.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'support/fixtures.dart';

/// Builds a plain v3.0-style database with sample rows (test data only).
Future<void> _plainDatabase(File file) async {
  final db = UserDb(NativeDatabase(file));
  await seedIfNeeded(db);
  await insertTestProfile(db);
  await db.into(db.bodyMetrics).insert(
        BodyMetricsCompanion.insert(date: '2026-10-01', weightKg: const Value(70.2)),
      );
  await db.into(db.dailyLogs).insert(
        DailyLogsCompanion.insert(date: '2026-10-01', workEffort: const Value('HIGH')),
      );
  final meal = await db.into(db.meals).insert(MealsCompanion.insert(date: '2026-10-01', block: 'LUNCH'));
  await db.into(db.mealItems).insert(
        MealItemsCompanion.insert(mealId: meal, foodId: const Value(3), grams: 150),
      );
  await db.close();
}

Map<String, int> _plainCounts(File file) {
  final db = raw.sqlite3.open(file.path);
  try {
    return tableRowCounts(db);
  } finally {
    db.close();
  }
}

void main() {
  late Directory dir;
  late File file;
  late Directory backups;
  String? storedKey;

  Future<DbPrepareReport> prepare() => prepareUserDbFile(
        file: file,
        backups: backups,
        readKey: () async => storedKey,
        writeKey: (k) async => storedKey = k,
        now: DateTime(2026, 10, 31, 8),
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('humanos-enc');
    file = File('${dir.path}/user.sqlite');
    backups = Directory('${dir.path}/backups');
    storedKey = null;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('the engine in this build encrypts (SQLite3MultipleCiphers)', () {
    final db = raw.sqlite3.openInMemory();
    try {
      final cipher = db.select('PRAGMA cipher');
      expect(cipher, isNotEmpty, reason: 'sqlite3 must be built with source: sqlite3mc');
    } finally {
      db.close();
    }
  });

  test('a plain v3.0 database is encrypted with identical row counts', () async {
    await _plainDatabase(file);
    expect(isPlainSqlite(file), isTrue);
    final before = _plainCounts(file);
    expect(before['profile'], 1);
    expect(before['meal_items'], 1);

    final report = await prepare();
    expect(report.encryptedNow, isTrue);
    expect(DbKey.isValid(storedKey), isTrue);
    expect(report.keyHex, storedKey);
    expect(isPlainSqlite(file), isFalse);
    expect(report.rowCounts, before);
    expect(File(report.backupPath!).existsSync(), isTrue);
    expect(isPlainSqlite(File(report.backupPath!)), isFalse);
    expect(File('${file.path}.cifrando').existsSync(), isFalse);

    final db = UserDb(NativeDatabase(file, setup: (d) => applyDbKey(d, report.keyHex)));
    addTearDown(db.close);
    expect((await db.select(db.profile).getSingle()).name, 'Persona de prueba');
    expect((await db.select(db.bodyMetrics).getSingle()).weightKg, 70.2);
    expect(await db.select(db.habits).get(), hasLength(7));
  });

  test('without the key the encrypted file cannot be read', () async {
    await _plainDatabase(file);
    await prepare();
    final noKey = raw.sqlite3.open(file.path);
    addTearDown(noKey.close);
    expect(() => noKey.select('SELECT count(*) FROM profile'), throwsA(isA<raw.SqliteException>()));

    final wrong = raw.sqlite3.open(file.path);
    addTearDown(wrong.close);
    applyDbKey(wrong, DbKey.generate());
    expect(() => wrong.select('SELECT count(*) FROM profile'), throwsA(isA<raw.SqliteException>()));
  });

  test('a second launch keeps the key and does not touch the file', () async {
    await _plainDatabase(file);
    final first = await prepare();
    final again = await prepare();
    expect(again.encryptedNow, isFalse);
    expect(again.keyHex, first.keyHex);
    expect(again.quarantinedPath, isNull);
  });

  test('an encrypted file without its key is moved aside, never deleted', () async {
    await _plainDatabase(file);
    await prepare();
    storedKey = null;
    final report = await prepare();
    expect(report.quarantinedPath, isNotNull);
    expect(File(report.quarantinedPath!).existsSync(), isTrue);
    expect(file.existsSync(), isFalse);
    expect(DbKey.isValid(storedKey), isTrue);
  });

  test('a new install creates an encrypted database from the start', () async {
    final report = await prepare();
    expect(report.encryptedNow, isFalse);
    final db = UserDb(NativeDatabase(file, setup: (d) => applyDbKey(d, report.keyHex)));
    await seedIfNeeded(db);
    await db.close();
    expect(isPlainSqlite(file), isFalse);
  });

  test('keys are 64 hex characters', () {
    final key = DbKey.generate();
    expect(DbKey.isValid(key), isTrue);
    expect(DbKey.isValid('xyz'), isFalse);
    expect(DbKey.isValid(null), isFalse);
    expect(DbKey.generate(), isNot(key));
  });
}
