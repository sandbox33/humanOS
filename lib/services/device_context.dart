import 'dart:async';

import 'package:flutter/services.dart';
import 'package:humanos_core/humanos_core.dart' show ContextTransition;

/// Location and notification permissions as the phone reports them.
class LocationAccess {
  const LocationAccess({
    required this.fine,
    required this.coarse,
    required this.background,
    required this.notifications,
  });

  const LocationAccess.none() : fine = false, coarse = false, background = false, notifications = false;

  factory LocationAccess.fromMap(Map<Object?, Object?>? m) => LocationAccess(
        fine: m?['fine'] == true,
        coarse: m?['coarse'] == true,
        background: m?['background'] == true,
        notifications: m?['notifications'] == true,
      );

  final bool fine;
  final bool coarse;
  final bool background;
  final bool notifications;

  /// Geofences need precise location "all the time".
  bool get readyForZones => fine && background;
}

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude, this.accuracyM});

  final double latitude;
  final double longitude;
  final double? accuracyM;
}

/// What the phone needs to watch a zone: no name, no kind.
class NativeZone {
  const NativeZone({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.silences,
  });

  final int id;
  final double latitude;
  final double longitude;
  final int radiusM;
  final bool silences;

  Map<String, Object> toMap() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'radiusM': radiusM,
        'silences': silences,
      };
}

class NativeTransition {
  const NativeTransition({required this.zoneId, required this.transition, required this.at});

  final int zoneId;
  final ContextTransition transition;
  final DateTime at;
}

class ZoneSyncResult {
  const ZoneSyncResult({required this.ok, required this.count, this.errorEs});

  final bool ok;
  final int count;
  final String? errorEs;
}

class NativeContextState {
  const NativeContextState({
    required this.inside,
    required this.silenced,
    required this.zones,
    this.lostCode,
    this.lastEvent,
  });

  final List<int> inside;
  final bool silenced;
  final int zones;

  /// Set when the system dropped the geofences (location turned off).
  final int? lostCode;
  final DateTime? lastEvent;
}

/// A reminder the phone posts on arriving at or leaving one of [zoneIds]
/// (empty: any place, including the manual buttons).
class NativeEventReminder {
  const NativeEventReminder({
    required this.id,
    required this.trigger,
    required this.zoneIds,
    required this.message,
  });

  final int id;
  final String trigger;
  final List<int> zoneIds;
  final String message;

  Map<String, Object> toMap() => {'id': id, 'trigger': trigger, 'zoneIds': zoneIds, 'message': message};
}

/// The phone's side of the location context (`ContextBridge.kt`).
abstract class DeviceContext {
  /// Fires when the phone stored new transitions while the app is open.
  Stream<void> get changes;
  Future<LocationAccess> access();
  Future<LocationAccess> requestForeground();
  Future<LocationAccess> requestBackground();
  Future<LocationAccess> requestNotifications();
  Future<bool> playServices();

  /// One reading, on request (never continuous updates).
  Future<GeoPoint?> currentLocation();
  Future<ZoneSyncResult> registerZones(List<NativeZone> zones, {required int responsivenessMs, required int staleMs});
  Future<List<NativeTransition>> drainEvents();
  Future<NativeContextState?> state();

  /// The user's correction for the phone's gate; null clears it.
  Future<void> setManual({required bool? silencing, required DateTime? until});
  Future<void> setEventReminders(List<NativeEventReminder> reminders);
  Future<void> fireManual(String trigger, {int? zoneId});
  /// Wi-Fi or another network that is not metered.
  Future<bool> unmeteredNetwork();
  Future<bool> ignoringBatteryOptimizations();
  Future<bool> requestIgnoreBatteryOptimizations();
  Future<bool> openAutostart();
  Future<bool> openBatterySaver();
  Future<bool> openAppDetails();
  Future<bool> openLocationSettings();
}

class ChannelDeviceContext implements DeviceContext {
  ChannelDeviceContext() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changes.add(null);
    });
  }

  static const _channel = MethodChannel('com.altair.humanos/context');
  final _changes = StreamController<void>.broadcast();

  Future<LocationAccess> _access(String method) async =>
      LocationAccess.fromMap(await _channel.invokeMapMethod<Object?, Object?>(method));

  Future<bool> _flag(String method) async => await _channel.invokeMethod<bool>(method) ?? false;

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<LocationAccess> access() => _access('access');
  @override
  Future<LocationAccess> requestForeground() => _access('requestForeground');
  @override
  Future<LocationAccess> requestBackground() => _access('requestBackground');
  @override
  Future<LocationAccess> requestNotifications() => _access('requestNotifications');
  @override
  Future<bool> playServices() => _flag('playServices');

  @override
  Future<GeoPoint?> currentLocation() async {
    final m = await _channel.invokeMapMethod<String, Object?>('currentLocation');
    if (m == null) return null;
    return GeoPoint(
      latitude: (m['latitude']! as num).toDouble(),
      longitude: (m['longitude']! as num).toDouble(),
      accuracyM: (m['accuracyM'] as num?)?.toDouble(),
    );
  }

  @override
  Future<ZoneSyncResult> registerZones(List<NativeZone> zones, {required int responsivenessMs, required int staleMs}) async {
    final m = await _channel.invokeMapMethod<String, Object?>('registerZones', {
      'zones': [for (final z in zones) z.toMap()],
      'responsivenessMs': responsivenessMs,
      'staleMs': staleMs,
    });
    return ZoneSyncResult(
      ok: m?['ok'] == true,
      count: m?['count'] as int? ?? 0,
      errorEs: m?['error'] as String?,
    );
  }

  @override
  Future<List<NativeTransition>> drainEvents() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('drainEvents') ?? const [];
    return [
      for (final m in list)
        if (ContextTransition.parse(m['transition'] as String?) case final t?)
          NativeTransition(
            zoneId: m['zoneId']! as int,
            transition: t,
            at: DateTime.fromMillisecondsSinceEpoch(m['atMs']! as int),
          ),
    ];
  }

  @override
  Future<NativeContextState?> state() async {
    final m = await _channel.invokeMapMethod<String, Object?>('state');
    if (m == null) return null;
    final last = m['lastEventMs'] as int?;
    return NativeContextState(
      inside: [for (final id in (m['inside'] as List<Object?>? ?? const [])) id! as int],
      silenced: m['silenced'] == true,
      zones: m['zones'] as int? ?? 0,
      lostCode: m['lostCode'] as int?,
      lastEvent: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  @override
  Future<void> setManual({required bool? silencing, required DateTime? until}) => _channel.invokeMethod<void>(
        'setManual',
        {'silencing': silencing, 'untilMs': until?.millisecondsSinceEpoch},
      );

  @override
  Future<void> setEventReminders(List<NativeEventReminder> reminders) =>
      _channel.invokeMethod<void>('setEventReminders', {'reminders': [for (final r in reminders) r.toMap()]});

  @override
  Future<void> fireManual(String trigger, {int? zoneId}) =>
      _channel.invokeMethod<void>('fireManual', {'trigger': trigger, 'zoneId': zoneId});

  @override
  Future<bool> unmeteredNetwork() => _flag('unmeteredNetwork');
  @override
  Future<bool> ignoringBatteryOptimizations() => _flag('ignoringBatteryOptimizations');
  @override
  Future<bool> requestIgnoreBatteryOptimizations() => _flag('requestIgnoreBatteryOptimizations');
  @override
  Future<bool> openAutostart() => _flag('openAutostart');
  @override
  Future<bool> openBatterySaver() => _flag('openBatterySaver');
  @override
  Future<bool> openAppDetails() => _flag('openAppDetails');
  @override
  Future<bool> openLocationSettings() => _flag('openLocationSettings');
}

/// Platforms and tests without the phone's location: nothing is granted
/// and nothing is watched.
class UnavailableDeviceContext implements DeviceContext {
  const UnavailableDeviceContext();

  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<LocationAccess> access() async => const LocationAccess.none();
  @override
  Future<LocationAccess> requestForeground() async => const LocationAccess.none();
  @override
  Future<LocationAccess> requestBackground() async => const LocationAccess.none();
  @override
  Future<LocationAccess> requestNotifications() async => const LocationAccess.none();
  @override
  Future<bool> playServices() async => false;
  @override
  Future<GeoPoint?> currentLocation() async => null;
  @override
  Future<ZoneSyncResult> registerZones(List<NativeZone> zones, {required int responsivenessMs, required int staleMs}) async =>
      const ZoneSyncResult(ok: false, count: 0, errorEs: 'Las zonas solo funcionan en el teléfono.');
  @override
  Future<List<NativeTransition>> drainEvents() async => const [];
  @override
  Future<NativeContextState?> state() async => null;
  @override
  Future<void> setManual({required bool? silencing, required DateTime? until}) async {}
  @override
  Future<void> setEventReminders(List<NativeEventReminder> reminders) async {}
  @override
  Future<void> fireManual(String trigger, {int? zoneId}) async {}
  @override
  Future<bool> unmeteredNetwork() async => false;
  @override
  Future<bool> ignoringBatteryOptimizations() async => false;
  @override
  Future<bool> requestIgnoreBatteryOptimizations() async => false;
  @override
  Future<bool> openAutostart() async => false;
  @override
  Future<bool> openBatterySaver() async => false;
  @override
  Future<bool> openAppDetails() async => false;
  @override
  Future<bool> openLocationSettings() async => false;
}
