import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/event_feedback.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/reference_models.dart';
import '../../../data/seed.dart';
import '../../../data/settings.dart';
import '../../../services/screen_awake.dart';
import '../../../services/services.dart';
import '../../../services/tempo_audio.dart';
import '../../../telemetry/ble_hr_source.dart';
import '../../habitos/domain/habits_model.dart';
import '../data/training_repository.dart';
import '../domain/training_plan.dart';
import 'heavy_duty_screen.dart';

sealed class _Stage {
  const _Stage();
}

class _Big3Stage extends _Stage {
  const _Big3Stage();
}

class _RampStage extends _Stage {
  const _RampStage(this.exercise, this.sets);
  final ExerciseRecord exercise;
  final List<WarmupSet> sets;
}

class _WorkStage extends _Stage {
  const _WorkStage(this.exercise, this.target);
  final ExerciseRecord exercise;
  final ExerciseTarget target;
}

class _RestStage extends _Stage {
  const _RestStage(this.next);
  final ExerciseRecord next;
}

class _SummaryStage extends _Stage {
  const _SummaryStage();
}

/// A finished work set and whether it beat a record.
class WorkResult {
  const WorkResult({required this.draft, required this.pr, this.e1rm});
  final SetDraft draft;
  final bool pr;
  final double? e1rm;
}

/// Live Heavy Duty session: McGill Big 3, warm-up ramp, one work set per
/// exercise with metronome and giant rep counter, rest timer and save. The
/// screen stays on for the whole session.
class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({
    super.key,
    required this.template,
    required this.mode,
    required this.band,
    required this.overridden,
  });

  final TrainingTemplate template;
  final SessionMode mode;
  final ReadinessBand? band;
  final bool overridden;

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  late final List<_Stage> _stages;
  int _index = 0;
  final Map<int, double?> _loads = {};
  final List<SetDraft> _warmups = [];
  final Map<int, WorkResult> _results = {};
  final List<int> _bpm = [];
  StreamSubscription<int>? _hr;
  int? _lastBpm;
  bool _saving = false;
  late final ScreenAwake _screen = ref.read(screenAwakeProvider);
  late final HeartRateMonitor? _monitor = ref.read(heartRateMonitorProvider);

  @override
  void initState() {
    super.initState();
    final catalog = ref.read(exerciseCatalogProvider);
    final templates = ref.read(exerciseTemplatesProvider);
    final history = ref.read(trainingHistoryProvider);
    final params = ProgressionParams.fromAssumptions(ref.read(currentAssumptionsProvider));
    final exercises = templateExercises(widget.template, templates, catalog);
    _stages = [const _Big3Stage()];
    for (var i = 0; i < exercises.length; i++) {
      final e = exercises[i];
      final target = nextExerciseTarget(e.toSpec(), history, mode: widget.mode, params: params);
      _loads[e.id] = target.loadKg;
      final load = target.loadKg;
      if (load != null) {
        final ramp = warmupRamp(spec: e.toSpec(), targetLoadKg: load, params: params);
        if (ramp.isNotEmpty) _stages.add(_RampStage(e, ramp));
      }
      _stages.add(_WorkStage(e, target));
      if (i < exercises.length - 1) _stages.add(_RestStage(exercises[i + 1]));
    }
    _stages.add(const _SummaryStage());
    unawaited(_screen.keepOn(true));
    unawaited(ref.read(tempoAudioProvider).init().catchError((Object _) {}));
    _connectHeartRate();
  }

  Future<void> _connectHeartRate() async {
    final monitor = _monitor;
    if (monitor == null) return;
    _hr = monitor.bpm.listen((bpm) {
      if (!mounted) return;
      setState(() {
        _lastBpm = bpm;
        _bpm.add(bpm);
      });
    });
    final deviceId = await ref.read(settingsRepositoryProvider).get(SettingKey.bleDeviceId);
    if (deviceId == null) return;
    try {
      await monitor.connect(deviceId);
    } on Object {
      // The band is optional: the session works without live heart rate.
    }
  }

  @override
  void dispose() {
    unawaited(_hr?.cancel());
    unawaited(_screen.keepOn(false));
    final monitor = _monitor;
    if (monitor != null) unawaited(monitor.disconnect().catchError((Object _) {}));
    super.dispose();
  }

  void _next() => setState(() => _index = (_index + 1).clamp(0, _stages.length - 1));

  void _back() => setState(() => _index = (_index - 1).clamp(0, _stages.length - 1));

  Future<bool> _confirmExit() async {
    if (_results.isEmpty) return true;
    return confirm(
      context,
      title: 'Salir',
      message: 'La sesión no está guardada. ¿Salir y perder las series?',
      accept: 'SALIR',
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final today = isoDate(ref.read(todayProvider));
    final records = <int, ({double loadKg, int reps, double e1rm})>{
      for (final r in _results.values)
        if (r.pr && r.e1rm != null)
          r.draft.exerciseId: (loadKg: r.draft.loadKg, reps: r.draft.validReps, e1rm: r.e1rm!),
    };
    final avg = _bpm.isEmpty ? null : _bpm.reduce((a, b) => a + b) / _bpm.length;
    final max = _bpm.isEmpty ? null : _bpm.reduce((a, b) => a > b ? a : b).toDouble();
    await ref.read(trainingRepositoryProvider).saveSession(
          date: today,
          template: widget.template,
          mode: widget.mode,
          readiness: widget.band,
          overridden: widget.overridden,
          sets: [..._warmups, for (final r in _results.values) r.draft],
          avgHr: avg,
          maxHr: max,
          newRecords: records,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _stages[_index];
    final title = switch (stage) {
      _Big3Stage() => 'BIG 3',
      _RampStage(:final exercise) => 'RAMPA · ${exercise.nameEs}',
      _WorkStage(:final exercise) => exercise.nameEs,
      _RestStage() => 'DESCANSO',
      _SummaryStage() => 'RESUMEN',
    };
    return PopScope(
      canPop: _results.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmExit()) navigator.pop();
      },
      child: HosPage(
        title: title,
        subtitle: 'Paso ${_index + 1} de ${_stages.length}'
            '${_lastBpm == null ? '' : ' · ♥ $_lastBpm lpm'}',
        body: switch (stage) {
          _Big3Stage() => _Big3View(onDone: _next),
          final _RampStage ramp => _RampView(
              stage: ramp,
              onDone: (drafts) {
                _warmups
                  ..removeWhere((w) => w.exerciseId == ramp.exercise.id)
                  ..addAll(drafts);
                _next();
              },
            ),
          final _WorkStage work => _WorkSetView(
              key: ValueKey(work.exercise.id),
              exercise: work.exercise,
              target: work.target,
              initialLoad: _loads[work.exercise.id],
              done: _results[work.exercise.id],
              onLoad: (kg) => _loads[work.exercise.id] = kg,
              onDone: (result) {
                setState(() => _results[work.exercise.id] = result);
                _next();
              },
            ),
          final _RestStage rest => _RestView(
              key: ValueKey('rest${rest.next.id}'),
              next: rest.next,
              onDone: _next,
            ),
          _SummaryStage() => _SummaryView(
              results: _results,
              warmups: _warmups.length,
              bpm: _bpm,
              saving: _saving,
              onSave: _save,
            ),
        },
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Paso anterior',
            onPressed: _index == 0 ? null : _back,
          ),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Saltar paso',
            onPressed: _index >= _stages.length - 1 ? null : _next,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Big 3

class _Big3View extends ConsumerStatefulWidget {
  const _Big3View({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_Big3View> createState() => _Big3ViewState();
}

class _Big3ViewState extends ConsumerState<_Big3View> {
  static const _items = [
    ('Curl-up de McGill', 'Una rodilla flexionada, manos bajo la zona lumbar. Sostén 8–10 s. Pirámide 5-3-1.'),
    ('Plancha lateral', 'Apoyo en antebrazo y rodillas o pies. Sostén 8–10 s por lado. Pirámide 5-3-1.'),
    ('Bird-dog', 'Brazo y pierna contrarios, espalda neutra. Sostén 8–10 s por lado. Pirámide 5-3-1.'),
  ];
  final Set<int> _done = {};

  Future<void> _finish() async {
    final repo = ref.read(habitsRepositoryProvider);
    final today = isoDate(ref.read(todayProvider));
    for (final habit in await repo.habits()) {
      if (habit.source == HabitSource.big3) await repo.setValue(habit.id, today, 1);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return PanelList(children: [
      const Note(
        'Activación de tronco antes de cargar la columna (McGill). Sin fatiga: '
        'calidad, no cantidad.',
      ),
      for (var i = 0; i < _items.length; i++)
        Card(
          child: CheckboxListTile(
            value: _done.contains(i),
            onChanged: (v) => setState(() => v == true ? _done.add(i) : _done.remove(i)),
            title: Text(_items[i].$1.toUpperCase()),
            subtitle: Text(_items[i].$2),
          ),
        ),
      const SizedBox(height: 12),
      BigButton(
        label: _done.length == _items.length ? 'Hecho · siguiente' : 'Siguiente',
        icon: Icons.arrow_forward,
        onPressed: _done.length == _items.length ? _finish : widget.onDone,
      ),
    ]);
  }
}

// ------------------------------------------------------------------ ramp

class _RampView extends StatefulWidget {
  const _RampView({required this.stage, required this.onDone});
  final _RampStage stage;
  final ValueChanged<List<SetDraft>> onDone;

  @override
  State<_RampView> createState() => _RampViewState();
}

class _RampViewState extends State<_RampView> {
  final Set<int> _done = {};

  @override
  Widget build(BuildContext context) {
    final e = widget.stage.exercise;
    final sets = widget.stage.sets;
    return PanelList(children: [
      Note('Rampa de calentamiento para ${e.nameEs}: sin acercarte al fallo.'),
      for (var i = 0; i < sets.length; i++)
        Card(
          child: CheckboxListTile(
            value: _done.contains(i),
            onChanged: (v) => setState(() => v == true ? _done.add(i) : _done.remove(i)),
            title: Text(
              '${fmtNum(sets[i].loadKg, decimals: 1, unit: 'kg')} × ${sets[i].reps}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      const SizedBox(height: 12),
      BigButton(
        label: 'Siguiente',
        icon: Icons.arrow_forward,
        onPressed: () => widget.onDone([
          for (final i in _done)
            SetDraft(
              exerciseId: e.id,
              loadKg: sets[i].loadKg,
              reps: sets[i].reps,
              validReps: sets[i].reps,
              reachedFailure: false,
              isWarmup: true,
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------- work set

enum _SetPhase { ready, running, review, restPause, restPauseCounting }

class _WorkSetView extends ConsumerStatefulWidget {
  const _WorkSetView({
    super.key,
    required this.exercise,
    required this.target,
    required this.initialLoad,
    required this.onLoad,
    required this.onDone,
    this.done,
  });

  final ExerciseRecord exercise;
  final ExerciseTarget target;
  final double? initialLoad;
  final ValueChanged<double> onLoad;
  final ValueChanged<WorkResult> onDone;
  final WorkResult? done;

  @override
  ConsumerState<_WorkSetView> createState() => _WorkSetViewState();
}

class _WorkSetViewState extends ConsumerState<_WorkSetView> {
  late double _load = widget.initialLoad ?? 0;
  _SetPhase _phase = _SetPhase.ready;
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  final List<int> _taps = [];
  int _restPauseReps = 0;
  int _restPauseLeft = 0;
  bool _failure = true;
  bool _metronomeOn = true;
  MetronomePosition? _position;
  RepAnalysis? _analysis;
  TempoSpec? _tempo;
  late final TempoParams _tempoParams;

  ExerciseRecord get _e => widget.exercise;
  TempoAudio get _audio => ref.read(tempoAudioProvider);

  @override
  void initState() {
    super.initState();
    _tempoParams = TempoParams.fromAssumptions(ref.read(currentAssumptionsProvider));
    try {
      _tempo = _e.timed ? null : TempoSpec.parse(_e.tempo);
    } on FormatException {
      _tempo = null;
    }
    _failure = _e.failureSafe;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker?.cancel();
    super.dispose();
  }

  /// Volume keys count a repetition while a set is running (one-handed).
  bool _onKey(KeyEvent event) {
    final volume = event.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown;
    if (!volume) return false;
    if (_phase != _SetPhase.running && _phase != _SetPhase.restPauseCounting) return false;
    if (event is KeyDownEvent) _tap();
    return true;
  }

  void _start() {
    _taps.clear();
    _clock
      ..reset()
      ..start();
    _position = null;
    setState(() => _phase = _SetPhase.running);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final tempo = _tempo;
    if (tempo == null || !_metronomeOn) {
      setState(() {});
      return;
    }
    final position = metronomeAt(tempo, _clock.elapsedMilliseconds, _tempoParams.concentricXS);
    final previous = _position;
    if (previous == null ||
        previous.repIndex != position.repIndex ||
        previous.phaseIndex != position.phaseIndex) {
      unawaited(_audio.phase(position.phase.kind));
    }
    setState(() => _position = position);
  }

  void _tap() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (_phase == _SetPhase.running) {
        _taps.add(_clock.elapsedMilliseconds);
      } else if (_phase == _SetPhase.restPauseCounting) {
        _restPauseReps++;
      }
    });
  }

  void _stop() {
    _ticker?.cancel();
    _clock.stop();
    final tempo = _tempo;
    setState(() {
      _analysis = tempo == null ? null : analyzeReps(_taps, tempo, _tempoParams);
      _phase = _SetPhase.review;
    });
  }

  void _restPause() {
    final seconds = ref.read(currentAssumptionsProvider).integer(A.restPauseS);
    setState(() {
      _restPauseLeft = seconds;
      _phase = _SetPhase.restPause;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _restPauseLeft--);
      if (_restPauseLeft <= 3 && _restPauseLeft > 0) unawaited(_audio.tick());
      if (_restPauseLeft <= 0) {
        timer.cancel();
        unawaited(_audio.restDone());
        setState(() => _phase = _SetPhase.restPauseCounting);
      }
    });
  }

  int get _reps => _e.timed ? (_clock.elapsedMilliseconds / 1000).floor() : debounceTaps(_taps, _tempoParams.debounceMs).length;

  int get _validReps => _e.timed ? _reps : (_analysis?.validReps ?? _reps);

  Future<void> _finish() async {
    final history = ref.read(trainingHistoryProvider);
    final bodyWeight = ref.read(bodyWeightProvider);
    final effective = effectiveLoad(_e, _load, bodyWeight);
    final valid = _validReps;
    final check = effective == null || _e.timed || valid <= 0
        ? null
        : checkPr(loadKg: effective, reps: valid, previous: previousLifts(_e, history, bodyWeight));
    final pr = check?.any ?? false;
    if (pr && ref.read(settingsProvider).eventFeedback) {
      unawaited(_audio.record());
      await EventFeedback.show(context, 'PR · ${_e.nameEs}');
    }
    widget.onDone(WorkResult(
      draft: SetDraft(
        exerciseId: _e.id,
        loadKg: _load,
        reps: _reps,
        validReps: valid,
        reachedFailure: _e.failureSafe && _failure,
        tutS: _e.timed ? _reps.toDouble() : _analysis?.tutS,
        restPauseReps: _restPauseReps,
        tapsMs: _analysis?.tapsMs ?? const [],
      ),
      pr: check?.isE1rmPr ?? false,
      e1rm: check?.e1rm,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.target;
    final done = widget.done;
    return PanelList(children: [
      TerminalPanel(
        label: 'Target to smash',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DataLine('Supera', previousText(_e, t.previousBest), emphasis: true),
            DataLine('Objetivo', targetText(_e, t)),
            if (!_e.failureSafe)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                color: HosColors.amber.withValues(alpha: 0.15),
                child: Text(
                  'NO AL FALLO · PARA CON ${t.rirTarget ?? 2} EN RESERVA',
                  style: theme.textTheme.titleMedium?.copyWith(color: HosColors.amber),
                ),
              ),
            Note(_e.cueEs),
            if (done != null)
              Note('Ya registrada: ${done.draft.validReps} válidas. Repetirla la reemplaza.'),
          ],
        ),
      ),
      ValueStepper(
        value: _load,
        unit: _e.assisted ? 'kg asist.' : 'kg',
        decimals: 1,
        steps: [_e.minIncrementKg <= 0 ? 1 : _e.minIncrementKg, 5],
        max: 500,
        onChanged: _phase == _SetPhase.ready
            ? (v) {
                setState(() => _load = v);
                widget.onLoad(v);
              }
            : (_) {},
        onTapValue: _phase != _SetPhase.ready
            ? null
            : () async {
                final value = await askNumber(context, title: 'Carga', initial: _load, unit: 'kg');
                if (value != null && value >= 0) {
                  setState(() => _load = value);
                  widget.onLoad(value);
                }
              },
      ),
      const SizedBox(height: 8),
      ...switch (_phase) {
        _SetPhase.ready => [
            if (_tempo != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('METRÓNOMO ${_e.tempo}'),
                subtitle: const Text('Bajar · pausa · subir · arriba, con sonido'),
                value: _metronomeOn,
                onChanged: (v) => setState(() => _metronomeOn = v),
              ),
            BigButton(
              label: _e.timed ? 'Empezar a sostener' : 'Empezar serie',
              icon: Icons.play_arrow,
              onPressed: _start,
            ),
            const Note('Toca el contador (o una tecla de volumen) al terminar cada repetición, arriba.'),
          ],
        _SetPhase.running => [
            if (_position != null)
              Text(
                '${_position!.phase.kind.labelEs} ${fmtNum(_position!.phaseRemainingS < 0 ? 0.0 : _position!.phaseRemainingS, decimals: 1)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall,
              ),
            _BigCounter(
              value: _e.timed ? '${_reps}s' : '$_reps',
              label: _e.timed ? 'SEGUNDOS' : 'REPS',
              onTap: _e.timed ? null : _tap,
            ),
            const SizedBox(height: 8),
            BigButton(label: _e.timed ? 'Soltar' : 'Terminar serie', icon: Icons.stop, onPressed: _stop),
          ],
        _SetPhase.review => [
            TerminalPanel(
              label: 'Serie',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DataLine(_e.timed ? 'Segundos' : 'Repeticiones', '$_reps', emphasis: true),
                  if (_analysis != null) ...[
                    DataLine('Válidas por tempo', '${_analysis!.validReps}'),
                    DataLine('Tiempo bajo tensión', fmtNum(_analysis!.tutS, unit: 's')),
                  ],
                  if (_restPauseReps > 0) DataLine('Rest-pause', '+$_restPauseReps'),
                  if (_e.failureSafe)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('LLEGUÉ AL FALLO TÉCNICO'),
                      value: _failure,
                      onChanged: (v) => setState(() => _failure = v),
                    ),
                ],
              ),
            ),
            if (_e.failureSafe && _failure && !_e.timed && _restPauseReps == 0)
              OutlinedButton.icon(
                icon: const Icon(Icons.timer_outlined),
                label: Text('REST-PAUSE (${ref.watch(currentAssumptionsProvider).integer(A.restPauseS)} s)'),
                onPressed: _restPause,
              ),
            const SizedBox(height: 8),
            BigButton(label: 'Guardar serie', icon: Icons.check, onPressed: _finish),
            TextButton(onPressed: _start, child: const Text('REPETIR LA SERIE')),
          ],
        _SetPhase.restPause => [
            Text('$_restPauseLeft', textAlign: TextAlign.center, style: theme.textTheme.displayLarge),
            const Note('Respira. Al sonar, más repeticiones con la misma carga.'),
          ],
        _SetPhase.restPauseCounting => [
            _BigCounter(value: '+$_restPauseReps', label: 'REST-PAUSE', onTap: _tap),
            const SizedBox(height: 8),
            BigButton(
              label: 'Terminar rest-pause',
              icon: Icons.stop,
              onPressed: () => setState(() => _phase = _SetPhase.review),
            ),
          ],
      },
    ]);
  }
}

/// Giant tap target (≥ 120 dp): the whole width, easy with one hand.
class _BigCounter extends StatelessWidget {
  const _BigCounter({required this.value, required this.label, this.onTap});
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      label: 'Contador de repeticiones',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null ? null : (_) => onTap!(),
        child: Container(
          key: const Key('rep-counter'),
          height: 220,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.primary, width: 3),
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: theme.textTheme.displayLarge?.copyWith(fontSize: 120)),
              Text(label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ rest

class _RestView extends ConsumerStatefulWidget {
  const _RestView({super.key, required this.next, required this.onDone});
  final ExerciseRecord next;
  final VoidCallback onDone;

  @override
  ConsumerState<_RestView> createState() => _RestViewState();
}

class _RestViewState extends ConsumerState<_RestView> {
  late int _left = ref.read(currentAssumptionsProvider).integer(A.restBetweenExercisesS);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _left <= 0) return;
      setState(() => _left--);
      if (_left == 0) unawaited(ref.read(tempoAudioProvider).restDone());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _left ~/ 60;
    final seconds = (_left % 60).toString().padLeft(2, '0');
    return PanelList(children: [
      Text('$minutes:$seconds', textAlign: TextAlign.center, style: theme.textTheme.displayLarge?.copyWith(fontSize: 110)),
      Text('SIGUIENTE: ${widget.next.nameEs.toUpperCase()}',
          textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() => _left += 30),
            child: const Text('+30 s'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(onPressed: widget.onDone, child: const Text('SIGUIENTE')),
        ),
      ]),
    ]);
  }
}

// --------------------------------------------------------------- summary

class _SummaryView extends ConsumerWidget {
  const _SummaryView({
    required this.results,
    required this.warmups,
    required this.bpm,
    required this.saving,
    required this.onSave,
  });

  final Map<int, WorkResult> results;
  final int warmups;
  final List<int> bpm;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(exerciseCatalogProvider);
    return PanelList(children: [
      TerminalPanel(
        label: 'Series de trabajo',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (results.isEmpty) const Note('Ninguna serie registrada todavía.'),
            for (final r in results.values)
              DataLine(
                catalog[r.draft.exerciseId]?.nameEs ?? 'Ejercicio ${r.draft.exerciseId}',
                '${fmtNum(r.draft.loadKg, decimals: 1, unit: 'kg')} × ${r.draft.validReps}'
                '${r.draft.restPauseReps > 0 ? ' +${r.draft.restPauseReps}' : ''}'
                '${r.pr ? ' · PR' : ''}',
              ),
            DataLine('Series de calentamiento', '$warmups'),
            if (bpm.isNotEmpty)
              DataLine(
                'Pulso medio / máximo',
                '${fmtNum(bpm.reduce((a, b) => a + b) / bpm.length)} / ${bpm.reduce((a, b) => a > b ? a : b)} lpm',
              ),
          ],
        ),
      ),
      BigButton(
        label: 'Guardar sesión',
        icon: Icons.save_outlined,
        onPressed: results.isEmpty || saving ? null : onSave,
      ),
      const Note('La próxima sesión se calcula al guardar (4–5 días de descanso).'),
    ]);
  }
}
