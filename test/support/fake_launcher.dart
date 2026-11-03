import 'dart:async';
import 'dart:typed_data';

import 'package:humanos/services/launcher.dart';

/// Invented apps; records what the screens asked the phone to do.
class FakeLauncher implements LauncherService {
  FakeLauncher({this.installed = const []});

  final List<InstalledApp> installed;
  final launched = <String>[];
  int homeSettingsOpened = 0;
  int dialerOpened = 0;
  final _home = StreamController<void>.broadcast();

  void pressHome() => _home.add(null);

  @override
  Future<List<InstalledApp>> apps() async => installed;
  @override
  Future<Uint8List?> icon(String package) async => null;
  @override
  Future<bool> launch(String package) async {
    launched.add(package);
    return true;
  }

  @override
  Future<bool> appDetails(String package) async => true;
  @override
  Future<bool> openHomeSettings() async {
    homeSettingsOpened++;
    return true;
  }

  @override
  Future<bool> isDefaultHome() async => true;
  @override
  Future<String?> dialer() async => 'test.dialer';
  @override
  Future<bool> openDialer() async {
    dialerOpened++;
    return true;
  }

  @override
  Stream<void> get homePressed => _home.stream;
}
