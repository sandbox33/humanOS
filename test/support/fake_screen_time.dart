import 'package:humanos/telemetry/usage_stats.dart';
import 'package:humanos_core/humanos_core.dart';

/// Invented usage events and declared app categories.
class FakeScreenTime implements ScreenTimeSource {
  FakeScreenTime({this.granted = true, this.usage = const [], this.declared = const {}});

  bool granted;
  final List<UsageEvent> usage;
  final Map<String, int> declared;
  final asked = <(DateTime, DateTime)>[];

  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<void> openSettings() async {}
  @override
  Future<int?> minutesToday() async => granted ? 0 : null;
  @override
  Future<List<UsageEvent>?> events(DateTime from, DateTime to) async {
    if (!granted) return null;
    asked.add((from, to));
    return [
      for (final e in usage)
        if (!e.at.isBefore(from) && e.at.isBefore(to)) e,
    ];
  }

  @override
  Future<Map<String, int>> appCategories() async => declared;
}
