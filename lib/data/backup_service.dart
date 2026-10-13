import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import 'export_crypto.dart';
import 'user_db.dart';

/// User-initiated encrypted export and import of every user table.
class BackupService {
  BackupService(this._db);
  final UserDb _db;

  static const payloadFormat = 'humanos-export';

  /// Every row of every table as JSON.
  Future<String> dumpJson(DateTime now) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _db.exportOrder) {
      final rows = await _db
          .customSelect('SELECT * FROM "${table.actualTableName}"')
          .get();
      tables[table.actualTableName] = [for (final r in rows) r.data];
    }
    return jsonEncode({
      'format': payloadFormat,
      'schema': _db.schemaVersion,
      'exported_at': now.toIso8601String(),
      'tables': tables,
    });
  }

  /// Encrypted export, key derivation off the UI isolate.
  Future<Uint8List> export(String password, DateTime now) async {
    final json = await dumpJson(now);
    return Isolate.run(() => ExportCrypto.encryptJson(json, password));
  }

  /// Replaces all user data with the content of an encrypted export.
  Future<int> import(Uint8List data, String password) async {
    final json = await Isolate.run(() => ExportCrypto.decryptJson(data, password));
    return restoreJson(json);
  }

  /// Restores a decrypted export; returns the number of rows written.
  Future<int> restoreJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic> || decoded['format'] != payloadFormat) {
      throw const ExportException('El contenido no es una copia de HumanOS.');
    }
    final schema = decoded['schema'];
    if (schema is! int || schema > _db.schemaVersion) {
      throw const ExportException('La copia es de una versión más nueva de HumanOS.');
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const ExportException('Copia incompleta.');
    }
    var written = 0;
    await _db.transaction(() async {
      for (final table in _db.exportOrder.reversed) {
        await _db.customStatement('DELETE FROM "${table.actualTableName}"');
      }
      for (final table in _db.exportOrder) {
        final rows = tables[table.actualTableName];
        if (rows is! List) continue;
        final known = table.$columns.map((c) => c.name).toSet();
        for (final row in rows) {
          if (row is! Map<String, dynamic>) continue;
          final columns = row.keys.where(known.contains).toList();
          if (columns.isEmpty) continue;
          await _db.customStatement(
            'INSERT INTO "${table.actualTableName}" '
            '(${columns.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(columns.length, '?').join(', ')})',
            [for (final c in columns) row[c]],
          );
          written++;
        }
      }
    });
    _db.notifyUpdates({
      for (final table in _db.exportOrder) TableUpdate.onTable(table),
    });
    return written;
  }
}
