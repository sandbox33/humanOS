import 'package:audioplayers/audioplayers.dart';
import 'package:humanos_core/humanos_core.dart';

/// Metronome and timer sounds. Audio keeps playing with the screen dimmed
/// and mixes with the user's music instead of stopping it.
abstract class TempoAudio {
  Future<void> init();
  Future<void> phase(TempoPhaseKind kind);
  Future<void> tick();
  Future<void> restDone();
  Future<void> record();
  Future<void> dispose();
}

class PoolTempoAudio implements TempoAudio {
  final Map<String, AudioPool> _pools = {};

  static const _files = {
    'down': 'audio/down.wav',
    'hold': 'audio/hold.wav',
    'up': 'audio/up.wav',
    'top': 'audio/top.wav',
    'tick': 'audio/tick.wav',
    'rest': 'audio/rest_done.wav',
    'pr': 'audio/pr.wav',
  };

  @override
  Future<void> init() async {
    if (_pools.isNotEmpty) return;
    final context = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();
    for (final entry in _files.entries) {
      _pools[entry.key] = await AudioPool.create(
        source: AssetSource(entry.value),
        maxPlayers: 2,
        audioContext: context,
        playerMode: PlayerMode.lowLatency,
      );
    }
  }

  Future<void> _play(String key) async {
    final pool = _pools[key];
    if (pool != null) await pool.start();
  }

  @override
  Future<void> phase(TempoPhaseKind kind) => _play(switch (kind) {
        TempoPhaseKind.eccentric => 'down',
        TempoPhaseKind.bottomPause => 'hold',
        TempoPhaseKind.concentric => 'up',
        TempoPhaseKind.topPause => 'top',
      });

  @override
  Future<void> tick() => _play('tick');

  @override
  Future<void> restDone() => _play('rest');

  @override
  Future<void> record() => _play('pr');

  @override
  Future<void> dispose() async {
    for (final pool in _pools.values) {
      await pool.dispose();
    }
    _pools.clear();
  }
}

class SilentTempoAudio implements TempoAudio {
  @override
  Future<void> init() async {}
  @override
  Future<void> phase(TempoPhaseKind kind) async {}
  @override
  Future<void> tick() async {}
  @override
  Future<void> restDone() async {}
  @override
  Future<void> record() async {}
  @override
  Future<void> dispose() async {}
}
