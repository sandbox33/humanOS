import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/backup_service.dart';
import 'package:humanos/data/export_crypto.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/user_db.dart';

import 'support/fixtures.dart';

void main() {
  test('AES-GCM container round trip and wrong password', () async {
    const json = '{"format":"x","valor":"áéí"}';
    final data = await ExportCrypto.encryptJson(json, 'clave-segura', iterations: 1000);
    expect(String.fromCharCodes(data.sublist(0, 4)), 'HOS3');
    expect(utf8.decode(data, allowMalformed: true).contains('valor'), isFalse,
        reason: 'the payload is never stored in clear');
    expect(await ExportCrypto.decryptJson(data, 'clave-segura'), json);
    await expectLater(
      ExportCrypto.decryptJson(data, 'otra-clave'),
      throwsA(isA<ExportException>()),
    );
    await expectLater(
      ExportCrypto.encryptJson(json, 'corta'),
      throwsA(isA<ExportException>()),
    );
  });

  test('every user table survives an export and restore', () async {
    final source = memoryUserDb();
    await seedIfNeeded(source);
    await source.into(source.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: '2026-10-13', weightKg: const Value(65.4)),
        );
    final json = await BackupService(source).dumpJson(DateTime(2026, 10, 13));

    final target = memoryUserDb();
    final rows = await BackupService(target).restoreJson(json);
    expect(rows, greaterThan(0));
    final weight = await target.select(target.bodyMetrics).getSingle();
    expect(weight.weightKg, 65.4);
    expect(await target.select(target.habits).get(), hasLength(7));
    await source.close();
    await target.close();
  });
}
