import 'dart:async';

import 'package:flutter/services.dart';

/// One launchable app on the phone.
class InstalledApp {
  const InstalledApp({required this.package, required this.label});

  final String package;
  final String label;
}

/// HumanOS as the home screen (`LauncherChannel.kt`). Every call fails
/// soft: a missing answer leaves the screen usable, never blank.
abstract class LauncherService {
  Future<List<InstalledApp>> apps();
  Future<Uint8List?> icon(String package);
  Future<bool> launch(String package);
  Future<bool> appDetails(String package);

  /// Ajustes → Apps predeterminadas: the way out to the system launcher.
  Future<bool> openHomeSettings();
  Future<bool> isDefaultHome();

  /// The phone's own dialer package (never a hard-coded one).
  Future<String?> dialer();
  Future<bool> openDialer();

  /// The home button was pressed while HumanOS was on screen.
  Stream<void> get homePressed;
}

class ChannelLauncher implements LauncherService {
  ChannelLauncher() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'homePressed') _home.add(null);
    });
  }

  static const _channel = MethodChannel('com.altair.humanos/launcher');
  final _home = StreamController<void>.broadcast();
  final _icons = <String, Uint8List?>{};

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on Object {
      return null;
    }
  }

  @override
  Future<List<InstalledApp>> apps() async {
    final raw = await _call<List<Object?>>('apps') ?? const [];
    return [
      for (final item in raw)
        if (item is Map)
          InstalledApp(package: item['package'] as String, label: item['label'] as String? ?? item['package'] as String),
    ];
  }

  @override
  Future<Uint8List?> icon(String package) async {
    if (_icons.containsKey(package)) return _icons[package];
    final bytes = await _call<Uint8List>('icon', {'package': package, 'size': 96});
    return _icons[package] = bytes;
  }

  @override
  Future<bool> launch(String package) async => await _call<bool>('launch', {'package': package}) ?? false;

  @override
  Future<bool> appDetails(String package) async => await _call<bool>('appDetails', {'package': package}) ?? false;

  @override
  Future<bool> openHomeSettings() async => await _call<bool>('openHomeSettings') ?? false;

  @override
  Future<bool> isDefaultHome() async => await _call<bool>('isDefaultHome') ?? false;

  @override
  Future<String?> dialer() => _call<String>('dialer');

  @override
  Future<bool> openDialer() async => await _call<bool>('openDialer') ?? false;

  @override
  Stream<void> get homePressed => _home.stream;
}

/// Tests and desktop: no apps, nothing opens.
class NoLauncher implements LauncherService {
  const NoLauncher();

  @override
  Future<List<InstalledApp>> apps() async => const [];
  @override
  Future<Uint8List?> icon(String package) async => null;
  @override
  Future<bool> launch(String package) async => false;
  @override
  Future<bool> appDetails(String package) async => false;
  @override
  Future<bool> openHomeSettings() async => false;
  @override
  Future<bool> isDefaultHome() async => false;
  @override
  Future<String?> dialer() async => null;
  @override
  Future<bool> openDialer() async => false;
  @override
  Stream<void> get homePressed => const Stream.empty();
}
