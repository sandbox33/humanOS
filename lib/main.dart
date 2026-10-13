import 'dart:async';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/reference_db.dart';
import 'data/reference_installer.dart';
import 'data/seed.dart';
import 'data/user_db.dart';
import 'services/notifications.dart';
import 'services/screen_awake.dart';
import 'services/services.dart';
import 'services/tempo_audio.dart';
import 'telemetry/ble_hr_source.dart';
import 'telemetry/health_connect_source.dart';
import 'telemetry/usage_stats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  final db = UserDb(driftDatabase(
    name: 'user',
    native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
  ));
  await seedIfNeeded(db);

  ReferenceDb? reference;
  var status = const ReferenceStatus(installed: false);
  try {
    final install = await ReferenceInstaller().ensureInstalled();
    final path = install.path;
    if (path != null) {
      reference = ReferenceDb.open(path);
      status = ReferenceStatus(installed: true, updated: install.updated);
    } else {
      status = const ReferenceStatus(
        installed: false,
        errorEs: 'Este APK no trae la base de alimentos (compilación sin el paso de CI).',
      );
    }
  } on Object catch (e) {
    status = ReferenceStatus(installed: false, errorEs: 'No se pudo abrir la base de alimentos: $e');
  }

  final audio = PoolTempoAudio();
  unawaited(audio.init().catchError((Object _) {}));

  runApp(ProviderScope(
    overrides: [
      userDbProvider.overrideWithValue(db),
      referenceDbProvider.overrideWithValue(reference),
      referenceStatusProvider.overrideWithValue(status),
      notificationServiceProvider.overrideWithValue(LocalNotificationService()),
      tempoAudioProvider.overrideWithValue(audio),
      screenAwakeProvider.overrideWithValue(WindowScreenAwake()),
      healthSourceProvider.overrideWithValue(PluginHealthSource()),
      heartRateMonitorProvider.overrideWithValue(BleHeartRateMonitor()),
      screenTimeProvider.overrideWithValue(UsageStatsScreenTime()),
    ],
    child: const HumanOsApp(),
  ));
}
