import 'dart:async';

import 'package:humanos/services/device_context.dart';

/// Records what the app asks the phone; test data only.
class FakeDeviceContext implements DeviceContext {
  FakeDeviceContext({
    this.foreground = const LocationAccess(fine: true, coarse: true, background: false, notifications: true),
    this.afterBackground = const LocationAccess(fine: true, coarse: true, background: true, notifications: true),
    this.location,
  });

  LocationAccess foreground;
  LocationAccess afterBackground;
  LocationAccess current = const LocationAccess.none();
  GeoPoint? location;
  final calls = <String>[];
  final registered = <List<NativeZone>>[];
  final pendingTransitions = <NativeTransition>[];
  final eventReminders = <List<NativeEventReminder>>[];
  final manual = <({bool? silencing, DateTime? until})>[];
  final fired = <(String, int?)>[];
  final _changes = StreamController<void>.broadcast();

  void emitChange() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<LocationAccess> access() async => current;

  @override
  Future<LocationAccess> requestForeground() async {
    calls.add('requestForeground');
    return current = foreground;
  }

  @override
  Future<LocationAccess> requestBackground() async {
    calls.add('requestBackground');
    return current = afterBackground;
  }

  @override
  Future<LocationAccess> requestNotifications() async => current;

  @override
  Future<bool> playServices() async => true;

  @override
  Future<GeoPoint?> currentLocation() async => location;

  @override
  Future<ZoneSyncResult> registerZones(List<NativeZone> zones, {required int responsivenessMs, required int staleMs}) async {
    registered.add(zones);
    return ZoneSyncResult(ok: true, count: zones.length);
  }

  @override
  Future<List<NativeTransition>> drainEvents() async {
    final out = [...pendingTransitions];
    pendingTransitions.clear();
    return out;
  }

  @override
  Future<NativeContextState?> state() async => null;

  @override
  Future<void> setManual({required bool? silencing, required DateTime? until}) async =>
      manual.add((silencing: silencing, until: until));

  @override
  Future<void> setEventReminders(List<NativeEventReminder> reminders) async => eventReminders.add(reminders);

  @override
  Future<void> fireManual(String trigger, {int? zoneId}) async => fired.add((trigger, zoneId));

  bool wifi = true;
  @override
  Future<bool> unmeteredNetwork() async => wifi;
  @override
  Future<bool> ignoringBatteryOptimizations() async => false;
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => true;
  @override
  Future<bool> openAutostart() async => true;
  @override
  Future<bool> openBatterySaver() async => true;
  @override
  Future<bool> openAppDetails() async => true;
  @override
  Future<bool> openLocationSettings() async => true;
}
