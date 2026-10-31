import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'user_db.dart';

/// The database key: 32 random bytes, hex encoded, kept in the Android
/// Keystore through flutter_secure_storage. If the app data is wiped, the
/// key is gone with it and the database cannot be opened again: the backup
/// exported with a password is the way back.
abstract final class DbKey {
  static const storageName = 'user_db_key_v1';

  static String generate([Random? random]) {
    final rng = random ?? Random.secure();
    return [
      for (var i = 0; i < 32; i++) rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static bool isValid(String? hex) => hex != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(hex);
}

/// Risk notice shown in AJUSTES and DIAGNÓSTICO.
const String dbKeyRiskEs =
    'Tus datos están cifrados con una clave que vive solo en este teléfono. '
    'Si borras los datos de la app o la desinstalas, esa clave se pierde y la '
    'base no se puede abrir nunca más. Tu respaldo es la copia cifrada con '
    'contraseña: expórtala de vez en cuando y guárdala fuera del teléfono.';

/// First statement of every connection (SQLite3MultipleCiphers).
void applyDbKey(raw.CommonDatabase db, String keyHex) {
  db.execute("PRAGMA hexkey = '$keyHex'");
}

const _sqliteMagic = 'SQLite format 3\u0000';

/// Whether [file] is a plain (unencrypted) SQLite database.
bool isPlainSqlite(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) return false;
  final handle = file.openSync();
  try {
    return ascii.decode(handle.readSync(16), allowInvalid: true) == _sqliteMagic;
  } finally {
    handle.closeSync();
  }
}

/// Rows per user table, used to prove that nothing was lost.
Map<String, int> tableRowCounts(raw.CommonDatabase db) {
  final tables = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      .map((r) => r['name'] as String)
      .toList()
    ..sort();
  return {
    for (final t in tables) t: db.select('SELECT count(*) AS n FROM "$t"').first['n'] as int,
  };
}

class DbOpenException implements Exception {
  const DbOpenException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What happened while preparing the file.
class DbPrepareReport {
  const DbPrepareReport({
    required this.keyHex,
    required this.encryptedNow,
    required this.rowCounts,
    required this.backupPath,
    required this.quarantinedPath,
  });

  final String keyHex;

  /// A plain database (HumanOS v3.0) was encrypted during this launch.
  final bool encryptedNow;

  /// Rows per table verified during that encryption (empty otherwise).
  final Map<String, int> rowCounts;

  /// Encrypted copy kept in `backups/` before any change of the file.
  final String? backupPath;

  /// An encrypted file whose key was missing, moved aside (never deleted).
  final String? quarantinedPath;
}

/// Encrypts a plain database without risking it:
///
/// 1. fold the WAL into the file and copy it;
/// 2. encrypt the copy (`PRAGMA hexrekey`, outside WAL mode);
/// 3. reopen the copy with the key and compare the row count of every
///    table with the original;
/// 4. keep an encrypted copy in [backups];
/// 5. only then replace the plain file.
Map<String, int> encryptPlainDatabase(
  File file,
  String keyHex, {
  required Directory backups,
  required String stamp,
}) {
  final plain = raw.sqlite3.open(file.path);
  final Map<String, int> before;
  try {
    plain.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    plain.execute('PRAGMA journal_mode = DELETE');
    before = tableRowCounts(plain);
  } finally {
    plain.close();
  }

  final tmp = File('${file.path}.cifrando');
  if (tmp.existsSync()) tmp.deleteSync();
  file.copySync(tmp.path);
  final copy = raw.sqlite3.open(tmp.path);
  try {
    copy.execute("PRAGMA hexrekey = '$keyHex'");
  } finally {
    copy.close();
  }
  if (isPlainSqlite(tmp)) {
    tmp.deleteSync();
    throw const DbOpenException(
      'Este APK no trae el motor cifrado (SQLite3MultipleCiphers): la base sigue sin cifrar.',
    );
  }

  final check = raw.sqlite3.open(tmp.path);
  final Map<String, int> after;
  try {
    applyDbKey(check, keyHex);
    after = tableRowCounts(check);
  } finally {
    check.close();
  }
  if (!_sameCounts(before, after)) {
    tmp.deleteSync();
    throw const DbOpenException(
      'La copia cifrada no tiene las mismas filas que la original: se dejó la base como estaba.',
    );
  }

  backups.createSync(recursive: true);
  tmp.copySync(p.join(backups.path, 'user-cifrada-$stamp.sqlite'));
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final side = File('${file.path}$suffix');
    if (side.existsSync()) side.deleteSync();
  }
  tmp.renameSync(file.path);
  return after;
}

bool _sameCounts(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Prepares `user.sqlite` before drift opens it. Pure file logic so it can
/// be tested without a phone: [readKey]/[writeKey] wrap secure storage.
Future<DbPrepareReport> prepareUserDbFile({
  required File file,
  required Directory backups,
  required Future<String?> Function() readKey,
  required Future<void> Function(String key) writeKey,
  DateTime? now,
}) async {
  final stamp = (now ?? DateTime.now()).toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  var key = await readKey();
  final exists = file.existsSync() && file.lengthSync() > 0;
  final plain = exists && isPlainSqlite(file);
  String? quarantined;
  if (!DbKey.isValid(key)) {
    if (exists && !plain) {
      backups.createSync(recursive: true);
      quarantined = p.join(backups.path, 'user-sin-clave-$stamp.sqlite');
      file.renameSync(quarantined);
    }
    key = DbKey.generate();
    await writeKey(key);
  }
  var counts = const <String, int>{};
  String? backup;
  if (plain) {
    counts = encryptPlainDatabase(file, key!, backups: backups, stamp: stamp);
    backup = p.join(backups.path, 'user-cifrada-$stamp.sqlite');
  }
  return DbPrepareReport(
    keyHex: key!,
    encryptedNow: plain,
    rowCounts: counts,
    backupPath: backup,
    quarantinedPath: quarantined,
  );
}

/// The opened database and what the preparation did.
class OpenedUserDb {
  const OpenedUserDb({required this.db, required this.encrypted, required this.report});

  final UserDb db;

  /// The file on disk is not readable as plain SQLite.
  final bool encrypted;
  final DbPrepareReport report;
}

/// Opens the encrypted `user.sqlite` from the app support directory.
Future<OpenedUserDb> openUserDb({FlutterSecureStorage storage = const FlutterSecureStorage()}) async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'user.sqlite'));
  final report = await prepareUserDbFile(
    file: file,
    backups: Directory(p.join(dir.path, 'backups')),
    readKey: () => storage.read(key: DbKey.storageName),
    writeKey: (key) => storage.write(key: DbKey.storageName, value: key),
  );
  final key = report.keyHex;
  final db = UserDb(
    driftDatabase(
      name: 'user',
      native: DriftNativeOptions(
        databaseDirectory: () async => dir,
        setup: (db) => applyDbKey(db, key),
      ),
    ),
  );
  // The first query creates or migrates the file; then it must be encrypted.
  await db.customSelect('SELECT 1').get();
  return OpenedUserDb(db: db, encrypted: !isPlainSqlite(file), report: report);
}
