import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Parses a Heart Rate Measurement (characteristic 0x2A37). Bit 0 of the
/// flags byte selects UINT8 or UINT16 (little endian) for the value.
int? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final uint16 = data[0] & 0x01 == 0x01;
  if (uint16) {
    if (data.length < 3) return null;
    return data[1] | (data[2] << 8);
  }
  if (data.length < 2) return null;
  return data[1];
}

class HrDevice {
  const HrDevice({required this.id, required this.name, required this.rssi});
  final String id;
  final String name;
  final int rssi;
}

enum HrConnection { disconnected, connecting, connected }

/// Live heart rate from a band broadcasting the standard Heart Rate service.
abstract class HeartRateMonitor {
  Stream<List<HrDevice>> scan({Duration timeout});
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Stream<int> get bpm;
  Stream<HrConnection> get connection;
}

/// `flutter_blue_plus` implementation (personal use licence).
class BleHeartRateMonitor implements HeartRateMonitor {
  static final _service = Guid('180d');
  static final _measurement = Guid('2a37');

  final _bpm = StreamController<int>.broadcast();
  final _connection = StreamController<HrConnection>.broadcast();
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _values;
  StreamSubscription<BluetoothConnectionState>? _state;

  @override
  Stream<int> get bpm => _bpm.stream;

  @override
  Stream<HrConnection> get connection => _connection.stream;

  @override
  Stream<List<HrDevice>> scan({Duration timeout = const Duration(seconds: 12)}) {
    unawaited(FlutterBluePlus.startScan(withServices: [_service], timeout: timeout));
    return FlutterBluePlus.scanResults.map((results) => [
          for (final r in results)
            HrDevice(
              id: r.device.remoteId.str,
              name: r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName,
              rssi: r.rssi,
            ),
        ]);
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    await disconnect();
    _connection.add(HrConnection.connecting);
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    _state = device.connectionState.listen((s) {
      _connection.add(s == BluetoothConnectionState.connected
          ? HrConnection.connected
          : HrConnection.disconnected);
    });
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 20));
    final services = await device.discoverServices();
    final service = services.firstWhere((s) => s.uuid == _service);
    final characteristic =
        service.characteristics.firstWhere((c) => c.uuid == _measurement);
    _values = characteristic.onValueReceived.listen((value) {
      final bpm = parseHeartRateMeasurement(value);
      if (bpm != null && bpm > 0) _bpm.add(bpm);
    });
    device.cancelWhenDisconnected(_values!);
    await characteristic.setNotifyValue(true);
  }

  @override
  Future<void> disconnect() async {
    await _values?.cancel();
    _values = null;
    await _state?.cancel();
    _state = null;
    final device = _device;
    _device = null;
    if (device != null) await device.disconnect();
    _connection.add(HrConnection.disconnected);
  }
}
