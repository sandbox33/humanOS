import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/off_client.dart';
import '../telemetry/ble_hr_source.dart';
import '../telemetry/health_connect_source.dart';
import '../telemetry/usage_stats.dart';
import 'notifications.dart';
import 'screen_awake.dart';
import 'tempo_audio.dart';

/// Platform services. `main()` provides the real implementations; tests
/// override them with fakes so no plugin channel is touched.
final notificationServiceProvider =
    Provider<NotificationService>((ref) => SilentNotificationService());
final tempoAudioProvider = Provider<TempoAudio>((ref) => SilentTempoAudio());
final screenAwakeProvider = Provider<ScreenAwake>((ref) => NoopScreenAwake());
final healthSourceProvider = Provider<HealthSource?>((ref) => null);
final heartRateMonitorProvider = Provider<HeartRateMonitor?>((ref) => null);
final screenTimeProvider = Provider<ScreenTimeSource?>((ref) => null);
final offClientProvider = Provider<OffClient>((ref) => OffClient());
