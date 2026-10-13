import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class HumanOsApp extends ConsumerStatefulWidget {
  const HumanOsApp({super.key});

  @override
  ConsumerState<HumanOsApp> createState() => _HumanOsAppState();
}

class _HumanOsAppState extends ConsumerState<HumanOsApp> {
  static const _window = 90;
  static const _budget = Duration(milliseconds: 16);
  final List<Duration> _frames = [];
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _clock = Timer.periodic(
      const Duration(minutes: 1),
      (_) => ref.read(todayProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _clock?.cancel();
    super.dispose();
  }

  /// Frame-time watchdog for the CRT headers: when the average build +
  /// raster time of the last frames exceeds 16 ms the effect is switched off
  /// for the session.
  void _onTimings(List<FrameTiming> timings) {
    if (!ref.read(crtEnabledProvider)) {
      _frames.clear();
      return;
    }
    for (final t in timings) {
      _frames.add(t.buildDuration + t.rasterDuration);
    }
    if (_frames.length > _window) _frames.removeRange(0, _frames.length - _window);
    if (_frames.length < _window ~/ 3) return;
    final total = _frames.fold(Duration.zero, (a, b) => a + b);
    if (total ~/ _frames.length > _budget) {
      ref.read(crtGovernorProvider.notifier).markDegraded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    return MaterialApp(
      title: 'HumanOS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(accent),
      locale: const Locale('es', 'EC'),
      supportedLocales: const [Locale('es', 'EC'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const AppShell(),
    );
  }
}
