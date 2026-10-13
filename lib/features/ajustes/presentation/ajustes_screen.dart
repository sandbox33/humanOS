import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/chores.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/backup_service.dart';
import '../../../data/export_crypto.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../../telemetry/health_connect_source.dart';
import 'ble_page.dart';
import 'diagnostico_page.dart';
import 'supuestos_page.dart';

/// AJUSTES: profile, assumptions, appearance, reminders, health data,
/// band, screen time, encrypted backup and sources/licences.
class AjustesScreen extends ConsumerWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HosPage(
      title: 'AJUSTES',
      body: PanelList(children: [
        const _ProfilePanel(),
        TerminalPanel(
          label: 'Supuestos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Note(
                'Cada número que usa la app (proteína por kg, sodio del sudor, '
                'días de descanso…) con su explicación y su fuente. Puedes '
                'cambiarlos.',
              ),
              BigButton(
                label: 'Ver y editar supuestos',
                icon: Icons.tune,
                outlined: true,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SupuestosPage()),
                ),
              ),
            ],
          ),
        ),
        const _AppearancePanel(),
        const _RemindersPanel(),
        const _HealthPanel(),
        const _BackupPanel(),
        const _SourcesPanel(),
      ]),
    );
  }
}

Future<void> _updateProfile(WidgetRef ref, ProfileCompanion fields) {
  final db = ref.read(userDbProvider);
  return (db.update(db.profile)..where((t) => t.id.equals(1))).write(fields);
}

class _ProfilePanel extends ConsumerWidget {
  const _ProfilePanel();

  Future<void> _time(BuildContext context, WidgetRef ref, String current,
      ProfileCompanion Function(String) build) async {
    final minutes = parseClock(current);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    await _updateProfile(ref, build(formatClock(picked.hour * 60 + picked.minute)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    if (p == null) return const SizedBox.shrink();
    Widget editable(String label, String value, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: DataLine(label, value),
        );
    return TerminalPanel(
      label: 'Perfil',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          editable('Nombre', p.name, () async {
            final name = await askText(context, title: 'Nombre', initial: p.name);
            if (name != null && name.isNotEmpty) await _updateProfile(ref, ProfileCompanion(name: Value(name)));
          }),
          editable('Año de nacimiento', '${p.birthYear}', () async {
            final year = await askNumber(context, title: 'Año de nacimiento', initial: p.birthYear.toDouble(), decimals: 0);
            if (year != null && year > 1900 && year < 2100) {
              await _updateProfile(ref, ProfileCompanion(birthYear: Value(year.round())));
            }
          }),
          editable('Estatura', fmtNum(p.heightCm, unit: 'cm'), () async {
            final cm = await askNumber(context, title: 'Estatura', initial: p.heightCm, unit: 'cm', decimals: 0);
            if (cm != null && cm > 100 && cm < 250) await _updateProfile(ref, ProfileCompanion(heightCm: Value(cm)));
          }),
          editable('Peso meta', fmtNum(p.targetWeightKg, decimals: 1, unit: 'kg'), () async {
            final kg = await askNumber(context, title: 'Peso meta', initial: p.targetWeightKg, unit: 'kg');
            if (kg != null && kg > 30 && kg < 250) {
              await _updateProfile(ref, ProfileCompanion(targetWeightKg: Value(kg)));
            }
          }),
          editable('Entrada al turno', p.shiftStart,
              () => _time(context, ref, p.shiftStart, (v) => ProfileCompanion(shiftStart: Value(v)))),
          editable('Almuerzo', p.lunchStart,
              () => _time(context, ref, p.lunchStart, (v) => ProfileCompanion(lunchStart: Value(v)))),
          editable('Salida del turno', p.shiftEnd,
              () => _time(context, ref, p.shiftEnd, (v) => ProfileCompanion(shiftEnd: Value(v)))),
          const Note('Toca un dato para cambiarlo. El horario mueve los bloques de comida y los avisos.'),
        ],
      ),
    );
  }
}

class _AppearancePanel extends ConsumerWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final degraded = ref.watch(crtGovernorProvider);
    return TerminalPanel(
      label: 'Pantalla',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 8, children: [
            for (final accent in AccentColor.values)
              ChoiceChip(
                label: Text(accent.labelEs),
                selected: settings.accent == accent,
                onSelected: (_) => repo.set(SettingKey.accent, accent.code),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LÍNEAS CRT EN TÍTULOS'),
            subtitle: Text(degraded
                ? 'Apagadas en esta sesión: el teléfono iba lento.'
                : 'Estáticas, solo en los títulos.'),
            value: settings.crtHeaders,
            onChanged: (v) => repo.setBool(SettingKey.crtHeaders, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AVISO DE LOGROS'),
            subtitle: const Text('Destello breve y vibración al batir un récord, subir una racha o un atributo.'),
            value: settings.eventFeedback,
            onChanged: (v) => repo.setBool(SettingKey.eventFeedback, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('FIBRA PRIMERO EN EL ALMUERZO'),
            subtitle: const Text('Sugiere el orden verduras → proteína → carbohidratos. '
                'Apagado por defecto: en superávit puede hacerte comer menos.'),
            value: settings.fiberFirst,
            onChanged: (v) => repo.setBool(SettingKey.fiberFirst, v),
          ),
        ],
      ),
    );
  }
}

class _RemindersPanel extends ConsumerWidget {
  const _RemindersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    return TerminalPanel(
      label: 'Avisos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('COMIDAS'),
            subtitle: const Text('A la hora de cada bloque según tu turno.'),
            value: settings.mealReminders,
            onChanged: (v) => repo.setBool(SettingKey.mealReminders, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AGUA EN HORAS DE CALOR'),
            subtitle: const Text('Se activan desde TURNO para el día.'),
            value: settings.hydrationNudges,
            onChanged: (v) => repo.setBool(SettingKey.hydrationNudges, v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('DÍA DE SESIÓN'),
            subtitle: const Text('Al salir del turno el día en que toca entrenar.'),
            value: settings.sessionReminder,
            onChanged: (v) => repo.setBool(SettingKey.sessionReminder, v),
          ),
          OutlinedButton(
            onPressed: () async {
              final ok = await ref.read(notificationServiceProvider).requestPermissions(exactAlarms: true);
              if (ok) await rescheduleReminders(ref);
              if (context.mounted) {
                toast(context, ok ? 'Avisos permitidos.' : 'Android no concedió el permiso.');
              }
            },
            child: const Text('PERMITIR AVISOS'),
          ),
        ],
      ),
    );
  }
}

class _HealthPanel extends ConsumerWidget {
  const _HealthPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(healthSourceProvider);
    final settings = ref.watch(settingsMapProvider).value ?? const {};
    final granted = settings[SettingKey.healthGranted] == '1';
    return TerminalPanel(
      label: 'Datos de salud',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'La banda Xiaomi envía sus datos a Mi Fitness, que los comparte con '
            'Health Connect. HumanOS solo lee Health Connect y guarda todo en el '
            'teléfono: nada sale de él salvo tu copia cifrada.',
          ),
          if (source == null)
            const Note('Health Connect no está disponible en esta compilación.')
          else ...[
            BigButton(
              label: granted ? 'Leer ahora' : 'Conectar Health Connect',
              icon: Icons.health_and_safety_outlined,
              onPressed: () async {
                final availability = await source.availability();
                if (availability == HealthAvailability.needsInstall) {
                  await source.installHealthConnect();
                  return;
                }
                if (availability == HealthAvailability.unavailable) {
                  if (context.mounted) toast(context, 'Health Connect no está disponible en este teléfono.');
                  return;
                }
                if (!granted) {
                  final ok = await source.requestPermissions();
                  await ref.read(settingsRepositoryProvider).setBool(SettingKey.healthGranted, ok);
                  if (!ok) {
                    if (context.mounted) toast(context, 'Sin permiso de lectura: no se leyó nada.');
                    return;
                  }
                }
                final result = await syncHealth(ref);
                if (context.mounted) toast(context, result.messageEs);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('DIAGNÓSTICO DE DATOS'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DiagnosticoPage()),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('PULSO EN VIVO POR BLUETOOTH'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BlePage()),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.phone_android),
            label: const Text('PERMISO DE TIEMPO DE PANTALLA'),
            onPressed: () async {
              final screen = ref.read(screenTimeProvider);
              if (screen == null) return;
              if (await screen.hasPermission()) {
                final minutes = await syncScreenTime(ref);
                if (context.mounted) toast(context, 'Permiso activo. Hoy: ${minutes ?? 0} min.');
              } else {
                await screen.openSettings();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BackupPanel extends ConsumerWidget {
  const _BackupPanel();

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final password = await askText(context, title: 'Contraseña de la copia', obscure: true,
        hint: 'mínimo 8 caracteres');
    if (password == null || !context.mounted) return;
    if (password.length < 8) {
      toast(context, 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    final again = await askText(context, title: 'Repite la contraseña', obscure: true);
    if (again != password) {
      if (context.mounted) toast(context, 'Las contraseñas no coinciden.');
      return;
    }
    if (context.mounted) toast(context, 'Cifrando…');
    final now = ref.read(clockProvider)();
    final bytes = await BackupService(ref.read(userDbProvider)).export(password, now);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/humanos-${isoDate(now)}.hos3');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'Copia cifrada de HumanOS',
    ));
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final file = await openFile();
    if (file == null || !context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Importar copia',
      message: 'Se reemplazarán todos tus datos actuales por los de la copia. '
          'Esta acción no se puede deshacer.',
      accept: 'REEMPLAZAR',
    );
    if (!ok || !context.mounted) return;
    final password = await askText(context, title: 'Contraseña de la copia', obscure: true);
    if (password == null) return;
    try {
      final rows = await BackupService(ref.read(userDbProvider)).import(await file.readAsBytes(), password);
      if (context.mounted) toast(context, 'Copia restaurada: $rows registros.');
    } on ExportException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TerminalPanel(
      label: 'Copia de seguridad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'Cifrada con AES-256-GCM y tu contraseña (PBKDF2). Tú eliges dónde '
            'guardarla. Sin la contraseña no se puede abrir.',
          ),
          BigButton(
            label: 'Exportar copia cifrada',
            icon: Icons.lock_outline,
            onPressed: () => _export(context, ref),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _import(context, ref),
            child: const Text('IMPORTAR COPIA'),
          ),
        ],
      ),
    );
  }
}

class _SourcesPanel extends ConsumerWidget {
  const _SourcesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(referenceDbProvider)?.sources() ?? const [];
    final status = ref.watch(referenceStatusProvider);
    return TerminalPanel(
      label: 'Fuentes y licencias',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!status.installed) Note(status.errorEs ?? 'Base de alimentos no instalada.'),
          for (final s in sources) ...[
            DataLine(s.name, s.license),
            Note('${s.version} · ${s.url}'),
          ],
          const DataLine('Open Food Facts', 'ODbL'),
          const Note('Productos y búsquedas por código: openfoodfacts.org. Base de '
              'datos abierta bajo Open Database License; contenidos bajo Database Contents License.'),
          const DataLine('Fuentes VT323, Share Tech Mono, IBM Plex Mono', 'SIL OFL 1.1'),
          const DataLine('Sonidos del metrónomo', 'tonos propios'),
        ],
      ),
    );
  }
}
