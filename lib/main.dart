import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'data/db_open.dart';
import 'data/reference_db.dart';
import 'data/reference_installer.dart';
import 'data/seed.dart';
import 'data/settings.dart';
import 'services/device_context.dart';
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

  final OpenedUserDb opened;
  try {
    opened = await openUserDb();
  } on Object catch (e) {
    runApp(DatabaseErrorApp(message: '$e'));
    return;
  }
  final db = opened.db;
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
  final scheduler = NativeNotificationService();
  unawaited(audio.init().catchError((Object _) {}));

  runApp(ProviderScope(
    overrides: [
      userDbProvider.overrideWithValue(db),
      dbSecurityProvider.overrideWithValue(DbSecurityStatus(
        encrypted: opened.encrypted,
        encryptedThisLaunch: opened.report.encryptedNow,
        verifiedTables: opened.report.rowCounts.length,
        quarantinedPath: opened.report.quarantinedPath,
      )),
      referenceDbProvider.overrideWithValue(reference),
      referenceStatusProvider.overrideWithValue(status),
      notificationServiceProvider.overrideWithValue(scheduler),
      alarmServiceProvider.overrideWithValue(scheduler),
      deviceContextProvider.overrideWithValue(ChannelDeviceContext()),
      tempoAudioProvider.overrideWithValue(audio),
      screenAwakeProvider.overrideWithValue(WindowScreenAwake()),
      healthSourceProvider.overrideWithValue(PluginHealthSource()),
      heartRateMonitorProvider.overrideWithValue(BleHeartRateMonitor()),
      screenTimeProvider.overrideWithValue(UsageStatsScreenTime()),
    ],
    child: const HumanOsApp(),
  ));
}

/// Shown when the user database cannot be opened. Nothing is deleted: the
/// file stays on the phone and the message says what happened.
class DatabaseErrorApp extends StatelessWidget {
  const DatabaseErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AccentColor.phosphor),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('NO SE PUDO ABRIR TU BASE DE DATOS', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 16),
                Text(message),
                const SizedBox(height: 16),
                const Text(
                  'Tus datos no se borraron. Si reinstalaste la app o borraste sus '
                  'datos, la clave de cifrado se perdió: restaura tu copia cifrada '
                  'con contraseña.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
