/// "MEJOR OPCIÓN AHORA": ranks what is in the pantry.
///
/// score = 0.30·z(NRF9.3 per USD) + 0.25·z(protein per 100 kcal, DIAAS
/// adjusted when known) + 0.15·z(kcal/g) + 0.15·gap_closure
/// − 0.25·[NOVA = 4] − 1.0·[user_excluded] + 0.10·expiry_urgency.
///
/// A NULL input drops its term (contributes 0) and lowers the confidence
/// shown next to the item. DIAAS is rarely published, so protein without a
/// DIAAS value is used unadjusted and lowers confidence by one level
/// instead of dropping the protein term. Expired items are flagged and
/// ranked last; they are never recommended.
library;

import 'dart:math' as math;

import 'assumptions.dart';
import 'confidence.dart';
import 'format_es.dart';

class ScorerParams {
  const ScorerParams({
    required this.wNrfPerUsd,
    required this.wProtein,
    required this.wEnergyDensity,
    required this.wGapClosure,
    required this.wNova4Penalty,
    required this.wExcludedPenalty,
    required this.wExpiryUrgency,
    required this.expiryUrgencyDays,
    required this.portionG,
  });

  factory ScorerParams.fromAssumptions(Assumptions a) => ScorerParams(
    wNrfPerUsd: a[A.wNrfPerUsd],
    wProtein: a[A.wProteinQuality],
    wEnergyDensity: a[A.wEnergyDensity],
    wGapClosure: a[A.wGapClosure],
    wNova4Penalty: a[A.wNova4Penalty],
    wExcludedPenalty: a[A.wUserExcludedPenalty],
    wExpiryUrgency: a[A.wExpiryUrgency],
    expiryUrgencyDays: a[A.expiryUrgencyDays],
    portionG: a[A.scorerPortionG],
  );

  final double wNrfPerUsd;
  final double wProtein;
  final double wEnergyDensity;
  final double wGapClosure;
  final double wNova4Penalty;
  final double wExcludedPenalty;
  final double wExpiryUrgency;
  final double expiryUrgencyDays;
  final double portionG;
}

/// One pantry item with whatever is known about it.
class PantryCandidate {
  const PantryCandidate({
    required this.key,
    required this.name,
    required this.gramsAvailable,
    this.kcalPer100g,
    this.proteinPer100g,
    this.nrf93Per100kcal,
    this.priceUsdPerKg,
    this.diaas,
    this.nova,
    this.userExcluded = false,
    this.daysToExpiry,
    this.foodConfidence = Confidence.media,
  });

  final String key;
  final String name;
  final double gramsAvailable;
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? nrf93Per100kcal;
  final double? priceUsdPerKg;

  /// DIAAS as a fraction (1.0 = 100 %).
  final double? diaas;
  final int? nova;
  final bool userExcluded;

  /// Days until expiry; negative means expired.
  final int? daysToExpiry;
  final Confidence foodConfidence;
}

/// What is still missing today.
class NutritionGap {
  const NutritionGap({required this.kcal, required this.proteinG});
  final double kcal;
  final double proteinG;
}

enum ScoreTermKind {
  nrfPerUsd('Densidad nutricional por dólar'),
  protein('Proteína por 100 kcal'),
  energyDensity('kcal por gramo'),
  gapClosure('Cierra la brecha de hoy'),
  nova4('Ultraprocesado (NOVA 4)'),
  excluded('Excluido por ti'),
  expiry('Vence pronto');

  const ScoreTermKind(this.labelEs);
  final String labelEs;
}

class ScoreTerm {
  const ScoreTerm({
    required this.kind,
    required this.weight,
    required this.rawValue,
    required this.contribution,
    required this.dropped,
  });

  final ScoreTermKind kind;
  final double weight;
  final double? rawValue;
  final double contribution;

  /// Input was NULL; the term contributes nothing.
  final bool dropped;
}

class ScoredCandidate {
  const ScoredCandidate({
    required this.candidate,
    required this.score,
    required this.terms,
    required this.confidence,
    required this.notesEs,
    required this.expired,
  });

  final PantryCandidate candidate;
  final double score;
  final List<ScoreTerm> terms;
  final Confidence confidence;
  final List<String> notesEs;
  final bool expired;
}

Map<String, double> _zScores(Map<String, double> values) {
  if (values.length < 2) return {for (final k in values.keys) k: 0};
  final mean = values.values.reduce((a, b) => a + b) / values.length;
  var sq = 0.0;
  for (final v in values.values) {
    sq += (v - mean) * (v - mean);
  }
  final sd = math.sqrt(sq / values.length);
  if (sd == 0) return {for (final k in values.keys) k: 0};
  return {for (final e in values.entries) e.key: (e.value - mean) / sd};
}

double? _nrfPerUsd(PantryCandidate c) {
  final nrf = c.nrf93Per100kcal;
  final kcal = c.kcalPer100g;
  final price = c.priceUsdPerKg;
  if (nrf == null || kcal == null || price == null || price <= 0) return null;
  final kcalPerUsd = kcal * 10 / price;
  return nrf * kcalPerUsd / 100;
}

double? _proteinPer100kcal(PantryCandidate c) {
  final protein = c.proteinPer100g;
  final kcal = c.kcalPer100g;
  if (protein == null || kcal == null || kcal <= 0) return null;
  final factor = c.diaas == null ? 1.0 : math.min(c.diaas!, 1.0);
  return protein / kcal * 100 * factor;
}

double? _energyDensity(PantryCandidate c) =>
    c.kcalPer100g == null ? null : c.kcalPer100g! / 100;

double? _gapClosure(PantryCandidate c, NutritionGap gap, double portionG) {
  final kcal = c.kcalPer100g;
  final protein = c.proteinPer100g;
  final parts = <double>[];
  if (gap.kcal > 0) {
    if (kcal == null) return null;
    parts.add(math.min(1, kcal * portionG / 100 / gap.kcal));
  }
  if (gap.proteinG > 0) {
    if (protein == null) return null;
    parts.add(math.min(1, protein * portionG / 100 / gap.proteinG));
  }
  if (parts.isEmpty) return 0;
  return parts.reduce((a, b) => a + b) / parts.length;
}

/// Ranks [items] (highest score first; expired items last).
List<ScoredCandidate> scorePantry(
  List<PantryCandidate> items, {
  required NutritionGap gap,
  required ScorerParams params,
}) {
  final available = items.where((c) => c.gramsAvailable > 0).toList();
  final active = available
      .where((c) => c.daysToExpiry == null || c.daysToExpiry! >= 0)
      .toList();

  Map<String, double> collect(double? Function(PantryCandidate) pick) => {
    for (final c in active)
      if (pick(c) != null) c.key: pick(c)!,
  };

  final zNrf = _zScores(collect(_nrfPerUsd));
  final zProtein = _zScores(collect(_proteinPer100kcal));
  final zEnergy = _zScores(collect(_energyDensity));

  final results = <ScoredCandidate>[];
  for (final c in available) {
    final expired = c.daysToExpiry != null && c.daysToExpiry! < 0;
    final terms = <ScoreTerm>[];
    final notes = <String>[];
    var dropped = 0;

    void zTerm(
      ScoreTermKind kind,
      double weight,
      double? raw,
      Map<String, double> z,
    ) {
      if (raw == null) {
        dropped++;
        terms.add(
          ScoreTerm(
            kind: kind,
            weight: weight,
            rawValue: null,
            contribution: 0,
            dropped: true,
          ),
        );
      } else {
        terms.add(
          ScoreTerm(
            kind: kind,
            weight: weight,
            rawValue: raw,
            contribution: expired ? 0 : weight * (z[c.key] ?? 0),
            dropped: false,
          ),
        );
      }
    }

    zTerm(ScoreTermKind.nrfPerUsd, params.wNrfPerUsd, _nrfPerUsd(c), zNrf);
    zTerm(
      ScoreTermKind.protein,
      params.wProtein,
      _proteinPer100kcal(c),
      zProtein,
    );
    zTerm(
      ScoreTermKind.energyDensity,
      params.wEnergyDensity,
      _energyDensity(c),
      zEnergy,
    );

    final closure = _gapClosure(c, gap, params.portionG);
    if (closure == null) {
      dropped++;
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.gapClosure,
          weight: params.wGapClosure,
          rawValue: null,
          contribution: 0,
          dropped: true,
        ),
      );
    } else {
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.gapClosure,
          weight: params.wGapClosure,
          rawValue: closure,
          contribution: params.wGapClosure * closure,
          dropped: false,
        ),
      );
    }

    if (c.nova == null) {
      dropped++;
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.nova4,
          weight: params.wNova4Penalty,
          rawValue: null,
          contribution: 0,
          dropped: true,
        ),
      );
    } else {
      final isUltra = c.nova == 4;
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.nova4,
          weight: params.wNova4Penalty,
          rawValue: c.nova!.toDouble(),
          contribution: isUltra ? -params.wNova4Penalty : 0,
          dropped: false,
        ),
      );
      if (isUltra) notes.add('Ultraprocesado (NOVA 4).');
    }

    terms.add(
      ScoreTerm(
        kind: ScoreTermKind.excluded,
        weight: params.wExcludedPenalty,
        rawValue: c.userExcluded ? 1 : 0,
        contribution: c.userExcluded ? -params.wExcludedPenalty : 0,
        dropped: false,
      ),
    );
    if (c.userExcluded) notes.add('Lo marcaste como excluido.');

    if (c.daysToExpiry == null) {
      dropped++;
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.expiry,
          weight: params.wExpiryUrgency,
          rawValue: null,
          contribution: 0,
          dropped: true,
        ),
      );
    } else {
      final days = c.daysToExpiry!;
      final urgency = days < 0
          ? 0.0
          : math.max(0.0, 1 - days / params.expiryUrgencyDays).toDouble();
      terms.add(
        ScoreTerm(
          kind: ScoreTermKind.expiry,
          weight: params.wExpiryUrgency,
          rawValue: urgency,
          contribution: params.wExpiryUrgency * urgency,
          dropped: false,
        ),
      );
      if (days >= 0 && days <= 2) {
        notes.add(days == 0 ? 'Vence hoy.' : 'Vence en $days días.');
      }
    }

    var confidence = c.foodConfidence;
    if (dropped >= 3) {
      confidence = confidence.min(Confidence.baja);
    } else if (dropped >= 1) {
      confidence = confidence.min(Confidence.media);
    }
    if (c.diaas == null && c.proteinPer100g != null) {
      confidence = confidence.min(Confidence.media);
      notes.add('Proteína sin ajuste DIAAS (sin valor publicado).');
    }
    if (dropped > 0) {
      notes.add('$dropped dato(s) sin valor: no suman ni restan.');
    }
    if (expired) {
      notes.add(
        'Vencido hace ${-c.daysToExpiry!} día(s): revísalo antes de '
        'comer. No se recomienda.',
      );
    }
    final score = terms.fold(0.0, (sum, t) => sum + t.contribution);
    results.add(
      ScoredCandidate(
        candidate: c,
        score: expired ? double.negativeInfinity : score,
        terms: List.unmodifiable(terms),
        confidence: expired ? Confidence.baja : confidence,
        notesEs: List.unmodifiable(notes),
        expired: expired,
      ),
    );
  }
  results.sort((a, b) => b.score.compareTo(a.score));
  return results;
}

/// Short Spanish explanation of the top contributions.
String explainScore(ScoredCandidate s) {
  final relevant =
      s.terms.where((t) => !t.dropped && t.contribution != 0).toList()
        ..sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
  if (relevant.isEmpty) return 'Sin datos suficientes para destacar algo.';
  return relevant
      .take(3)
      .map((t) {
        final sign = t.contribution >= 0 ? '+' : '−';
        return '$sign${formatDecimal(t.contribution.abs(), decimals: 2)} '
            '${t.kind.labelEs}';
      })
      .join(' · ');
}
