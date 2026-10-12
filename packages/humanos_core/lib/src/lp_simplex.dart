/// Linear programming (two-phase simplex with Bland's rule) and the day
/// plan built on it: minimise cost subject to kcal ≥ target, protein ≥
/// target, sodium ≤ limit (+ sweat sodium), fat ≤ cap and grams ≤ stock.
/// When infeasible, a diagnostic names the binding constraint.
library;

import 'assumptions.dart';
import 'format_es.dart';

enum ConstraintSense { le, ge, eq }

class LinearConstraint {
  const LinearConstraint(
    this.coefficients,
    this.sense,
    this.rhs, {
    this.label = '',
  });

  final List<double> coefficients;
  final ConstraintSense sense;
  final double rhs;
  final String label;
}

enum LpStatus { optimal, infeasible, unbounded }

class LpSolution {
  const LpSolution(this.status, this.values, this.objective);
  final LpStatus status;
  final List<double> values;
  final double objective;
}

const double _eps = 1e-9;

/// Minimises `objective · x` subject to [constraints] and `x ≥ 0`.
LpSolution solveLp({
  required List<double> objective,
  required List<LinearConstraint> constraints,
  int maxIterations = 20000,
}) {
  final n = objective.length;
  final senses = <ConstraintSense>[];
  final rows = <List<double>>[];
  final rhs = <double>[];
  for (final c in constraints) {
    if (c.coefficients.length != n) {
      throw ArgumentError(
        'La restricción «${c.label}» no tiene $n coeficientes',
      );
    }
    var coeffs = List<double>.of(c.coefficients);
    var b = c.rhs;
    var sense = c.sense;
    if (b < 0) {
      coeffs = [for (final v in coeffs) -v];
      b = -b;
      sense = switch (sense) {
        ConstraintSense.le => ConstraintSense.ge,
        ConstraintSense.ge => ConstraintSense.le,
        ConstraintSense.eq => ConstraintSense.eq,
      };
    }
    rows.add(coeffs);
    rhs.add(b);
    senses.add(sense);
  }
  final m = rows.length;
  final slackCount = senses.where((s) => s != ConstraintSense.eq).length;
  final artCount = senses.where((s) => s != ConstraintSense.le).length;
  final cols = n + slackCount + artCount;
  final t = List.generate(m, (_) => List<double>.filled(cols + 1, 0));
  final basis = List<int>.filled(m, -1);
  var slackCol = n;
  var artCol = n + slackCount;
  for (var i = 0; i < m; i++) {
    for (var j = 0; j < n; j++) {
      t[i][j] = rows[i][j];
    }
    t[i][cols] = rhs[i];
    switch (senses[i]) {
      case ConstraintSense.le:
        t[i][slackCol] = 1;
        basis[i] = slackCol++;
      case ConstraintSense.ge:
        t[i][slackCol++] = -1;
        t[i][artCol] = 1;
        basis[i] = artCol++;
      case ConstraintSense.eq:
        t[i][artCol] = 1;
        basis[i] = artCol++;
    }
  }
  final firstArtificial = n + slackCount;

  if (artCount > 0) {
    final cost1 = List<double>.filled(cols, 0);
    for (var j = firstArtificial; j < cols; j++) {
      cost1[j] = 1;
    }
    _simplex(t, basis, cost1, cols, maxIterations);
    var infeasibility = 0.0;
    for (var i = 0; i < m; i++) {
      infeasibility += cost1[basis[i]] * t[i][cols];
    }
    if (infeasibility > 1e-7) {
      return LpSolution(LpStatus.infeasible, List.filled(n, 0), 0);
    }
    for (var i = 0; i < m; i++) {
      if (basis[i] < firstArtificial) continue;
      for (var j = 0; j < firstArtificial; j++) {
        if (t[i][j].abs() > _eps) {
          _pivot(t, basis, i, j);
          break;
        }
      }
    }
  }

  final cost2 = List<double>.filled(cols, 0);
  for (var j = 0; j < n; j++) {
    cost2[j] = objective[j];
  }
  final status = _simplex(t, basis, cost2, firstArtificial, maxIterations);
  if (status == LpStatus.unbounded) {
    return LpSolution(
      LpStatus.unbounded,
      List.filled(n, 0),
      double.negativeInfinity,
    );
  }
  final x = List<double>.filled(n, 0);
  for (var i = 0; i < m; i++) {
    if (basis[i] < n) x[basis[i]] = t[i][cols] < 0 ? 0 : t[i][cols];
  }
  var value = 0.0;
  for (var j = 0; j < n; j++) {
    value += objective[j] * x[j];
  }
  return LpSolution(LpStatus.optimal, x, value);
}

void _pivot(List<List<double>> t, List<int> basis, int row, int col) {
  final width = t[row].length;
  final p = t[row][col];
  for (var j = 0; j < width; j++) {
    t[row][j] /= p;
  }
  for (var i = 0; i < t.length; i++) {
    if (i == row) continue;
    final factor = t[i][col];
    if (factor.abs() <= _eps) continue;
    for (var j = 0; j < width; j++) {
      t[i][j] -= factor * t[row][j];
      if (t[i][j].abs() < 1e-12) t[i][j] = 0;
    }
  }
  basis[row] = col;
}

LpStatus _simplex(
  List<List<double>> t,
  List<int> basis,
  List<double> cost,
  int allowedColumns,
  int maxIterations,
) {
  final m = t.length;
  final rhsCol = t.isEmpty ? 0 : t[0].length - 1;
  for (var iter = 0; iter < maxIterations; iter++) {
    var entering = -1;
    for (var j = 0; j < allowedColumns; j++) {
      var d = cost[j];
      for (var i = 0; i < m; i++) {
        d -= cost[basis[i]] * t[i][j];
      }
      if (d < -_eps) {
        entering = j;
        break;
      }
    }
    if (entering < 0) return LpStatus.optimal;
    var leaving = -1;
    var best = double.infinity;
    for (var i = 0; i < m; i++) {
      final a = t[i][entering];
      if (a <= _eps) continue;
      final ratio = t[i][rhsCol] / a;
      if (ratio < best - _eps ||
          ((ratio - best).abs() <= _eps &&
              leaving >= 0 &&
              basis[i] < basis[leaving])) {
        best = ratio;
        leaving = i;
      }
    }
    if (leaving < 0) return LpStatus.unbounded;
    _pivot(t, basis, leaving, entering);
  }
  throw StateError('El simplex no convergió');
}

// ------------------------------------------------------------- Day plan

/// A food available for the day plan (values per gram).
class DietFood {
  const DietFood({
    required this.key,
    required this.name,
    required this.maxGrams,
    this.costUsdPerG,
    this.kcalPerG,
    this.proteinPerG,
    this.sodiumMgPerG,
    this.fatPerG,
    this.isBeverage = false,
  });

  final String key;
  final String name;

  /// Stock in the pantry.
  final double maxGrams;
  final double? costUsdPerG;
  final double? kcalPerG;
  final double? proteinPerG;
  final double? sodiumMgPerG;
  final double? fatPerG;

  /// Beverages never fill a plate on their own (v1 contract).
  final bool isBeverage;
}

class DietTargets {
  const DietTargets({
    required this.kcalMin,
    required this.proteinMinG,
    required this.sodiumMaxMg,
  });

  final double kcalMin;
  final double proteinMinG;

  /// 2300 mg plus the sodium lost in sweat today.
  final double sodiumMaxMg;
}

class DietParams {
  const DietParams({required this.maxEnergyShare, required this.fatMaxFrac});

  factory DietParams.fromAssumptions(Assumptions a) => DietParams(
    maxEnergyShare: a[A.lpMaxEnergyShare],
    fatMaxFrac: a[A.lpFatMaxFrac],
  );

  final double maxEnergyShare;
  final double fatMaxFrac;
}

enum DietStatus { optimal, infeasible, noCandidates, nothingNeeded }

class DietPlan {
  const DietPlan({
    required this.status,
    required this.gramsByKey,
    required this.costUsd,
    required this.kcal,
    required this.proteinG,
    required this.sodiumMg,
    required this.fatG,
    required this.sodiumPartial,
    required this.excludedEs,
    required this.bindingEs,
    required this.messageEs,
  });

  final DietStatus status;
  final Map<String, double> gramsByKey;
  final double costUsd;
  final double kcal;
  final double proteinG;

  /// Sodium of the foods with known sodium.
  final double sodiumMg;
  final double fatG;

  /// Some planned foods have no sodium data: the total is a floor.
  final bool sodiumPartial;
  final List<String> excludedEs;
  final List<String> bindingEs;
  final String messageEs;
}

class _Candidate {
  _Candidate(this.food, this.upper);
  final DietFood food;
  final double upper;
}

/// Cheapest plan that meets [targets] with what is in the pantry.
DietPlan planDiet({
  required List<DietFood> foods,
  required DietTargets targets,
  required DietParams params,
}) {
  final excluded = <String>[];
  final candidates = <_Candidate>[];
  for (final f in foods) {
    if (f.maxGrams <= 0) continue;
    if (f.isBeverage) {
      excluded.add('${f.name}: bebida (no llena el plato sola).');
      continue;
    }
    if (f.costUsdPerG == null) {
      excluded.add('${f.name}: sin precio.');
      continue;
    }
    if (f.kcalPerG == null || f.proteinPerG == null) {
      excluded.add('${f.name}: sin dato de kcal o proteína.');
      continue;
    }
    final shareCap = f.kcalPerG! > 0
        ? params.maxEnergyShare * targets.kcalMin / f.kcalPerG!
        : f.maxGrams;
    final upper = shareCap < f.maxGrams ? shareCap : f.maxGrams;
    candidates.add(_Candidate(f, upper < 0 ? 0 : upper));
  }

  if (targets.kcalMin <= 0 && targets.proteinMinG <= 0) {
    return DietPlan(
      status: DietStatus.nothingNeeded,
      gramsByKey: const {},
      costUsd: 0,
      kcal: 0,
      proteinG: 0,
      sodiumMg: 0,
      fatG: 0,
      sodiumPartial: false,
      excludedEs: excluded,
      bindingEs: const [],
      messageEs: 'Ya cubriste las metas de hoy.',
    );
  }
  if (candidates.isEmpty) {
    return DietPlan(
      status: DietStatus.noCandidates,
      gramsByKey: const {},
      costUsd: 0,
      kcal: 0,
      proteinG: 0,
      sodiumMg: 0,
      fatG: 0,
      sodiumPartial: false,
      excludedEs: excluded,
      bindingEs: const [],
      messageEs:
          'No hay alimentos con precio, kcal y proteína en la '
          'despensa.',
    );
  }

  final fatCap = params.fatMaxFrac * targets.kcalMin / 9;

  LpSolution solve({
    bool withSodium = true,
    bool withFat = true,
    bool withShareCaps = true,
  }) {
    final n = candidates.length;
    final constraints = <LinearConstraint>[
      LinearConstraint(
        [for (final c in candidates) c.food.kcalPerG!],
        ConstraintSense.ge,
        targets.kcalMin,
        label: 'kcal',
      ),
      LinearConstraint(
        [for (final c in candidates) c.food.proteinPerG!],
        ConstraintSense.ge,
        targets.proteinMinG,
        label: 'proteina',
      ),
    ];
    if (withSodium && candidates.any((c) => c.food.sodiumMgPerG != null)) {
      constraints.add(
        LinearConstraint(
          [for (final c in candidates) c.food.sodiumMgPerG ?? 0],
          ConstraintSense.le,
          targets.sodiumMaxMg,
          label: 'sodio',
        ),
      );
    }
    if (withFat && candidates.any((c) => c.food.fatPerG != null)) {
      constraints.add(
        LinearConstraint(
          [for (final c in candidates) c.food.fatPerG ?? 0],
          ConstraintSense.le,
          fatCap,
          label: 'grasa',
        ),
      );
    }
    for (var i = 0; i < n; i++) {
      final row = List<double>.filled(n, 0);
      row[i] = 1;
      final upper = withShareCaps
          ? candidates[i].upper
          : candidates[i].food.maxGrams;
      constraints.add(
        LinearConstraint(
          row,
          ConstraintSense.le,
          upper,
          label: 'tope ${candidates[i].food.name}',
        ),
      );
    }
    return solveLp(
      objective: [for (final c in candidates) c.food.costUsdPerG!],
      constraints: constraints,
    );
  }

  final solution = solve();
  if (solution.status == LpStatus.optimal) {
    final grams = <String, double>{};
    var kcal = 0.0, protein = 0.0, sodium = 0.0, fat = 0.0, cost = 0.0;
    var sodiumPartial = false;
    for (var i = 0; i < candidates.length; i++) {
      final g = solution.values[i];
      if (g < 0.5) continue;
      final f = candidates[i].food;
      grams[f.key] = g;
      kcal += f.kcalPerG! * g;
      protein += f.proteinPerG! * g;
      cost += f.costUsdPerG! * g;
      if (f.sodiumMgPerG == null) {
        sodiumPartial = true;
      } else {
        sodium += f.sodiumMgPerG! * g;
      }
      if (f.fatPerG != null) fat += f.fatPerG! * g;
    }
    return DietPlan(
      status: DietStatus.optimal,
      gramsByKey: grams,
      costUsd: cost,
      kcal: kcal,
      proteinG: protein,
      sodiumMg: sodium,
      fatG: fat,
      sodiumPartial: sodiumPartial,
      excludedEs: excluded,
      bindingEs: const [],
      messageEs:
          'Plan de ${formatDecimal(cost, decimals: 2)} USD: '
          '${formatWhole(kcal)} kcal, ${formatWhole(protein)} g de proteína.',
    );
  }

  final binding = <String>[];
  var maxKcal = 0.0, maxProtein = 0.0;
  for (final c in candidates) {
    maxKcal += c.food.kcalPerG! * c.upper;
    maxProtein += c.food.proteinPerG! * c.upper;
  }
  if (maxKcal + _eps < targets.kcalMin) {
    binding.add(
      'kcal: la despensa da como máximo ${formatWhole(maxKcal)} de '
      '${formatWhole(targets.kcalMin)} kcal.',
    );
  }
  if (maxProtein + _eps < targets.proteinMinG) {
    binding.add(
      'proteína: la despensa da como máximo '
      '${formatWhole(maxProtein)} de ${formatWhole(targets.proteinMinG)} g.',
    );
  }
  if (binding.isEmpty) {
    if (solve(withSodium: false).status == LpStatus.optimal) {
      binding.add(
        'sodio: no se llega a las metas sin pasar de '
        '${formatWhole(targets.sodiumMaxMg)} mg.',
      );
    }
    if (solve(withFat: false).status == LpStatus.optimal) {
      binding.add(
        'grasa: las metas exigen más del '
        '${formatWhole(params.fatMaxFrac * 100)} % de kcal en grasa.',
      );
    }
    if (solve(withShareCaps: false).status == LpStatus.optimal) {
      binding.add(
        'variedad: hace falta que un alimento pase del '
        '${formatWhole(params.maxEnergyShare * 100)} % de las kcal.',
      );
    }
    if (binding.isEmpty) {
      binding.add(
        'combinación de límites: sodio, grasa y topes por alimento '
        'a la vez.',
      );
    }
  }
  return DietPlan(
    status: DietStatus.infeasible,
    gramsByKey: const {},
    costUsd: 0,
    kcal: 0,
    proteinG: 0,
    sodiumMg: 0,
    fatG: 0,
    sodiumPartial: false,
    excludedEs: excluded,
    bindingEs: binding,
    messageEs: 'No hay plan posible con la despensa actual.',
  );
}
