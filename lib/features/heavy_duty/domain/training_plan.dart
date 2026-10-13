import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/reference_models.dart';
import '../../../data/user_db.dart';
import '../../estado/domain/readiness_today.dart';
import '../../estado/domain/targets.dart';
import '../data/training_repository.dart';

final trainingRepositoryProvider =
    Provider<TrainingRepository>((ref) => TrainingRepository(ref.watch(userDbProvider)));

final sessionsProvider = StreamProvider<List<SessionRow>>(
  (ref) => ref.watch(trainingRepositoryProvider).watchSessions(),
);

final setsProvider = StreamProvider<List<SetRow>>(
  (ref) => ref.watch(trainingRepositoryProvider).watchSets(),
);

final personalRecordsProvider = StreamProvider<List<PersonalRecordRow>>(
  (ref) => ref.watch(trainingRepositoryProvider).watchRecords(),
);

/// Exercise catalogue from the reference database.
final exerciseCatalogProvider = Provider<Map<int, ExerciseRecord>>((ref) {
  final db = ref.watch(referenceDbProvider);
  if (db == null) return const {};
  return {for (final e in db.exercises()) e.id: e};
});

final exerciseTemplatesProvider = Provider<Map<String, List<int>>>(
  (ref) => ref.watch(referenceDbProvider)?.templates() ?? const {},
);

final trainingHistoryProvider = Provider<List<SessionRecord>>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const <SessionRow>[];
  final sets = ref.watch(setsProvider).value ?? const <SetRow>[];
  return TrainingRepository.toHistory(sessions, sets);
});

/// Next session: date window, template and mode (normal / deload / retest).
final sessionPlanProvider = Provider<SessionPlan>((ref) {
  final catalog = ref.watch(exerciseCatalogProvider);
  return planNextSession(
    history: ref.watch(trainingHistoryProvider),
    exercises: [for (final e in catalog.values) e.toSpec()],
    today: ref.watch(todayProvider),
    params: ProgressionParams.fromAssumptions(ref.watch(currentAssumptionsProvider)),
    readinessToday: ref.watch(readinessTodayProvider).band,
  );
});

/// Exercises of a template, in order.
List<ExerciseRecord> templateExercises(
  TrainingTemplate template,
  Map<String, List<int>> templates,
  Map<int, ExerciseRecord> catalog,
) =>
    [
      for (final id in templates[template.code] ?? const <int>[])
        if (catalog[id] != null) catalog[id]!,
    ];

/// Effective load for e1RM: assisted machines subtract the assistance
/// from body weight; other exercises use the load as is.
double? effectiveLoad(ExerciseRecord exercise, double loadKg, double? bodyWeightKg) {
  if (!exercise.assisted) return loadKg;
  if (bodyWeightKg == null) return null;
  final load = bodyWeightKg - loadKg;
  return load > 0 ? load : null;
}

/// Previous working sets of an exercise for PR checks.
List<LiftResult> previousLifts(
  ExerciseRecord exercise,
  List<SessionRecord> history,
  double? bodyWeightKg,
) {
  final lifts = <LiftResult>[];
  for (final session in history) {
    for (final set in session.sets) {
      if (set.exerciseId != exercise.id || set.isWarmup) continue;
      final load = effectiveLoad(exercise, set.loadKg, bodyWeightKg);
      if (load != null) lifts.add(LiftResult(loadKg: load, reps: set.validReps));
    }
  }
  return lifts;
}

/// Body weight used for assisted exercises (latest weigh-in).
final bodyWeightProvider = Provider<double?>((ref) => ref.watch(latestWeightProvider)?.kg);
