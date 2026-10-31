import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../services/services.dart';

/// MIUI/HyperOS stop apps in the background and can cancel alarms. These
/// steps keep reminders, zones and alarms alive.
class XiaomiGuidePage extends ConsumerStatefulWidget {
  const XiaomiGuidePage({super.key});

  @override
  ConsumerState<XiaomiGuidePage> createState() => _XiaomiGuidePageState();
}

class _XiaomiGuidePageState extends ConsumerState<XiaomiGuidePage> with WidgetsBindingObserver {
  bool? _ignoring;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final value = await ref.read(deviceContextProvider).ignoringBatteryOptimizations();
    if (mounted) setState(() => _ignoring = value);
  }

  Future<void> _open(Future<bool> Function() action) async {
    final ok = await action();
    if (!ok && mounted) toast(context, 'Este teléfono no tiene esa pantalla: búscala en Ajustes → Apps → HumanOS.');
  }

  Widget _step(String number, String title, String text, {String? button, Future<bool> Function()? action}) {
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Paso $number · $title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: theme.textTheme.bodyMedium),
          if (button != null && action != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => _open(action), child: Text(button)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.read(deviceContextProvider);
    final notifications = ref.read(notificationServiceProvider);
    return HosPage(
      title: 'XIAOMI / HYPEROS',
      subtitle: 'Para que avisos, zonas y alarmas no se pierdan',
      body: PanelList(children: [
        _step('1', 'Inicio automático', 'Activa el inicio automático de HumanOS. Sin él, el sistema no la '
            'despierta para una alarma, un aviso o una zona.', button: 'ABRIR INICIO AUTOMÁTICO', action: device.openAutostart),
        _step('2', 'Ahorro de batería', 'En el ahorro de batería de HumanOS elige «Sin restricciones».',
            button: 'ABRIR AHORRO DE BATERÍA', action: device.openBatterySaver),
        _step(
          '3',
          'Optimización de Android',
          _ignoring == true
              ? 'Listo: HumanOS ya no está optimizada.'
              : 'Permite que HumanOS no se optimice. Estado: ${_ignoring == null ? 'sin dato' : 'optimizada'}.',
          button: 'PERMITIR',
          action: device.requestIgnoreBatteryOptimizations,
        ),
        _step('4', 'Fijar en recientes', 'Abre la vista de apps recientes, mantén presionada la tarjeta de '
            'HumanOS (o deslízala hacia abajo) y toca el candado.'),
        _step('5', 'Alarmas exactas', 'Permite las alarmas y recordatorios exactos para que suenen a la hora.',
            button: 'ABRIR PERMISO', action: () async {
          await notifications.requestPermissions(exactAlarms: true);
          return true;
        }),
        _step('6', 'Prueba', 'Crea una alarma en ALARMAS para dentro de 2 h, cierra la app y confirma que suena.'),
      ]),
    );
  }
}
