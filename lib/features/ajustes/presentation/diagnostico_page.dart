import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/chores.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/status_widgets.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../../telemetry/confidence.dart';
import '../../../telemetry/health_connect_source.dart';
import '../../../telemetry/telemetry_repository.dart';
import '../../estado/domain/readiness_today.dart';

final _availabilityProvider = FutureProvider<HealthAvailability?>((ref) async {
  final source = ref.watch(healthSourceProvider);
  if (source == null) return null;
  try {
    return await source.availability();
  } on Object {
    return HealthAvailability.unavailable;
  }
});

/// Diagnóstico de datos: what each source actually delivers, with the
/// confidence of each type, so missing band data is visible, not silent.
class DiagnosticoPage extends ConsumerWidget {
  const DiagnosticoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(telemetrySamplesProvider).value ?? const <TelemetrySampleRow>[];
    final today = ref.watch(todayProvider);
    final settings = ref.watch(settingsMapProvider).value ?? const {};
    final last = DateTime.tryParse(settings[SettingKey.healthLastSync] ?? '');
    final availability = ref.watch(_availabilityProvider).value;
    final reference = ref.watch(referenceStatusProvider);

    List<TelemetrySampleRow> since(int days) {
      final from = addDays(today, -(days - 1));
      return [
        for (final r in rows)
          if (DateTime.tryParse(r.start) case final start? when !dateOnly(start).isBefore(from)) r,
      ];
    }

    final week = countByKind(since(7));
    final month = countByKind(since(30));
    final lastByKind = <TelemetryKind, DateTime>{};
    for (final r in rows) {
      final kind = TelemetryKind.ofCode(r.type);
      final start = DateTime.tryParse(r.start);
      if (kind == null || start == null) continue;
      final current = lastByKind[kind];
      if (current == null || start.isAfter(current)) lastByKind[kind] = start;
    }
    final theme = Theme.of(context);
    return HosPage(
      title: 'DIAGNÓSTICO',
      subtitle: 'Qué datos llegan de verdad',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Health Connect',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataLine('Estado', switch (availability) {
                HealthAvailability.available => 'disponible',
                HealthAvailability.needsInstall => 'falta instalar o actualizar',
                HealthAvailability.unavailable => 'no disponible',
                null => 'sin acceso en esta compilación',
              }),
              DataLine('Permiso', settings[SettingKey.healthGranted] == '1' ? 'concedido' : 'no pedido'),
              DataLine('Última lectura', last == null ? 'nunca' : '${fmtShortDay(last)} ${fmtTime(last)}'),
              BigButton(
                label: 'Leer ahora',
                icon: Icons.sync,
                outlined: true,
                onPressed: () async {
                  final result = await syncHealth(ref);
                  if (result.ok) await recordReadiness(ref);
                  if (context.mounted) toast(context, result.messageEs);
                },
              ),
            ],
          ),
        ),
        TerminalPanel(
          label: 'Lecturas por tipo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('TIPO', style: theme.textTheme.labelMedium)),
                SizedBox(width: 52, child: Text('7 D', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
                SizedBox(width: 52, child: Text('30 D', style: theme.textTheme.labelMedium, textAlign: TextAlign.end)),
              ]),
              const Divider(),
              for (final kind in TelemetryKind.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: Text(kind.labelEs, style: theme.textTheme.bodyLarge)),
                        SizedBox(width: 52, child: Text('${week[kind] ?? 0}', textAlign: TextAlign.end)),
                        SizedBox(width: 52, child: Text('${month[kind] ?? 0}', textAlign: TextAlign.end)),
                      ]),
                      Row(children: [
                        ConfidenceChip(kind.confidenceEs),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lastByKind[kind] == null
                                ? 'sin lecturas'
                                : 'última: ${fmtShortDay(lastByKind[kind]!)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              const Note(
                'Si VFC queda en 0, Mi Fitness no la comparte: la recuperación usa '
                'el pulso en reposo. Las fases del sueño son poco fiables en '
                'bandas de muñeca; el total de sueño es más útil.',
              ),
            ],
          ),
        ),
        TerminalPanel(
          label: 'Base de alimentos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DataLine('Instalada', reference.installed ? 'sí' : 'no'),
              if (reference.updated) const Note('Copiada o actualizada en este arranque.'),
              if (reference.errorEs != null) Note(reference.errorEs!),
            ],
          ),
        ),
      ]),
    );
  }
}
