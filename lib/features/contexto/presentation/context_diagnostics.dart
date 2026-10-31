import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/format.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../services/device_context.dart';
import '../../../services/notifications.dart';
import '../../../services/services.dart';

typedef _Snapshot = ({
  bool playServices,
  LocationAccess access,
  NativeContextState? state,
  bool batteryFree,
  SchedulerState? scheduler,
});

final _contextSnapshotProvider = FutureProvider.autoDispose<_Snapshot>((ref) async {
  final device = ref.watch(deviceContextProvider);
  final scheduler = ref.watch(notificationServiceProvider);
  return (
    playServices: await device.playServices(),
    access: await device.access(),
    state: await device.state(),
    batteryFree: await device.ignoringBatteryOptimizations(),
    scheduler: scheduler is NativeNotificationService ? await scheduler.state() : null,
  );
});

/// DIAGNÓSTICO: what the phone reports about zones, reminders and alarms.
class ContextDiagnosticsPanel extends ConsumerWidget {
  const ContextDiagnosticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(_contextSnapshotProvider).value;
    String yes(bool v) => v ? 'sí' : 'no';
    return TerminalPanel(
      label: 'Zonas, avisos y alarmas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot == null)
            const DataLine('Teléfono', sinDato)
          else ...[
            DataLine('Google Play services', yes(snapshot.playServices)),
            DataLine('Ubicación precisa', yes(snapshot.access.fine)),
            DataLine('Ubicación todo el tiempo', yes(snapshot.access.background)),
            DataLine('Notificaciones', yes(snapshot.access.notifications)),
            DataLine('Batería sin optimizar', yes(snapshot.batteryFree)),
            DataLine('Zonas en el teléfono', '${snapshot.state?.zones ?? 0}'),
            DataLine('Dentro de', snapshot.state == null ? sinDato : '${snapshot.state!.inside.length} zona(s)'),
            DataLine('Avisos retenidos ahora', snapshot.state == null ? sinDato : yes(snapshot.state!.silenced)),
            DataLine(
              'Último movimiento',
              switch (snapshot.state?.lastEvent) {
                final at? => '${fmtShortDay(at)} ${fmtTime(at)}',
                null => sinDato,
              },
            ),
            if (snapshot.state?.lostCode != null)
              const Note('El sistema quitó las zonas (ubicación apagada o reinicio): abre CONTEXTO para '
                  'activarlas de nuevo.'),
            if (snapshot.scheduler case final s?) ...[
              DataLine('Alarmas exactas permitidas', yes(s.exact)),
              DataLine('Avisos programados', '${s.pending}'),
              DataLine('Avisos en espera de salir', '${s.deferred}'),
              DataLine(
                'Próximo aviso',
                switch (s.next) {
                  final at? => '${fmtShortDay(at)} ${fmtTime(at)}',
                  null => sinDato,
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
