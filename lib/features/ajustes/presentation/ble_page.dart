import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/settings.dart';
import '../../../services/services.dart';
import '../../../telemetry/ble_hr_source.dart';

/// Finds a band broadcasting the standard Heart Rate service (0x180D) and
/// shows the live pulse. The chosen band is remembered for sessions.
class BlePage extends ConsumerStatefulWidget {
  const BlePage({super.key});

  @override
  ConsumerState<BlePage> createState() => _BlePageState();
}

class _BlePageState extends ConsumerState<BlePage> {
  late final HeartRateMonitor? _monitor = ref.read(heartRateMonitorProvider);
  StreamSubscription<List<HrDevice>>? _scan;
  StreamSubscription<int>? _bpmSub;
  StreamSubscription<HrConnection>? _stateSub;
  List<HrDevice> _devices = const [];
  HrConnection _state = HrConnection.disconnected;
  int? _bpm;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    final monitor = _monitor;
    if (monitor == null) return;
    _bpmSub = monitor.bpm.listen((v) => setState(() => _bpm = v));
    _stateSub = monitor.connection.listen((s) => setState(() => _state = s));
  }

  @override
  void dispose() {
    unawaited(_scan?.cancel());
    unawaited(_bpmSub?.cancel());
    unawaited(_stateSub?.cancel());
    final monitor = _monitor;
    if (monitor != null) {
      unawaited(monitor.stopScan().catchError((Object _) {}));
      unawaited(monitor.disconnect().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _startScan() async {
    final monitor = _monitor;
    if (monitor == null) return;
    await _scan?.cancel();
    setState(() {
      _devices = const [];
      _scanning = true;
    });
    try {
      _scan = monitor.scan().listen(
            (devices) => setState(() => _devices = devices),
            onError: (Object e) {
              if (mounted) toast(context, 'Bluetooth: $e');
            },
          );
      await Future<void>.delayed(const Duration(seconds: 12));
    } on Object catch (e) {
      if (mounted) toast(context, 'No se pudo buscar: $e');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(HrDevice device) async {
    final monitor = _monitor;
    if (monitor == null) return;
    try {
      await monitor.stopScan();
      await monitor.connect(device.id);
      await ref.read(settingsRepositoryProvider).set(SettingKey.bleDeviceId, device.id);
    } on Object catch (e) {
      if (mounted) toast(context, 'No se pudo conectar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HosPage(
      title: 'PULSO BLE',
      body: PanelList(children: [
        const Note(
          'Activa en la banda "Compartir frecuencia cardiaca" (transmisión de '
          'pulso). HumanOS escucha el servicio estándar 0x180D; no envía nada.',
        ),
        if (_monitor == null)
          const Note('Bluetooth no está disponible en esta compilación.')
        else ...[
          TerminalPanel(
            label: 'En vivo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _bpm == null ? '—' : '$_bpm',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge,
                ),
                Text(
                  switch (_state) {
                    HrConnection.connected => 'CONECTADA',
                    HrConnection.connecting => 'CONECTANDO…',
                    HrConnection.disconnected => 'DESCONECTADA',
                  },
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? 'BUSCANDO…' : 'BUSCAR BANDA'),
            onPressed: _scanning ? null : _startScan,
          ),
          for (final d in _devices)
            Card(
              child: ListTile(
                title: Text(d.name.isEmpty ? d.id : d.name),
                subtitle: Text('${d.id} · señal ${d.rssi} dBm'),
                trailing: const Icon(Icons.link),
                onTap: () => _connect(d),
              ),
            ),
        ],
      ]),
    );
  }
}
