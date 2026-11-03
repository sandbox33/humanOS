/// The day's close (B6): mood and energy from 1 to 5, minutes with people
/// by the user's own categories, and the user's own honesty question.
/// No score and no reproach; trends only after enough days, always with
/// how many days they rest on and the reminder that correlation is not
/// cause.
library;

import 'dart:math' as math;

/// One closed day.
class DayClose {
  const DayClose({
    required this.date,
    required this.mood,
    required this.energy,
    this.interactionMinutes = const {},
    this.honestyYes,
  });

  final DateTime date;

  /// 1–5.
  final int mood;

  /// 1–5.
  final int energy;

  /// Minutes per interaction category id.
  final Map<int, int> interactionMinutes;

  /// The answer to the user's question; null when unanswered.
  final bool? honestyYes;

  int get totalInteractionMinutes =>
      interactionMinutes.values.fold(0, (s, m) => s + m);
}

/// Whether a 1–5 value is valid.
bool validScale(int value) => value >= 1 && value <= 5;

/// Pearson correlation of paired values; null with fewer than 3 pairs or
/// when one side does not vary.
double? pearson(List<double> x, List<double> y) {
  final n = x.length;
  if (n != y.length || n < 3) return null;
  final mx = x.reduce((a, b) => a + b) / n;
  final my = y.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = x[i] - mx, dy = y[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  if (sxx == 0 || syy == 0) return null;
  return sxy / math.sqrt(sxx * syy);
}

/// Trends over the closed days.
class CloseTrends {
  const CloseTrends({
    required this.days,
    required this.moodMean,
    required this.energyMean,
    required this.interactionMeanMinutes,
    required this.honestyYesDays,
    required this.answeredDays,
    this.moodVsInteraction,
    this.energyVsInteraction,
  });

  /// How many closed days the trends rest on.
  final int days;
  final double moodMean;
  final double energyMean;
  final double interactionMeanMinutes;
  final int honestyYesDays;
  final int answeredDays;

  /// Correlation (Pearson) of mood and energy with minutes with people.
  final double? moodVsInteraction;
  final double? energyVsInteraction;
}

/// Trends of the last [window] closed days, only when at least [minDays]
/// days are closed (fewer days say too little). Null below that.
CloseTrends? closeTrends(
  List<DayClose> closes, {
  required int minDays,
  required int window,
}) {
  final recent = [...closes]..sort((a, b) => b.date.compareTo(a.date));
  final used = recent.take(window).toList();
  if (used.length < minDays) return null;
  final n = used.length;
  final minutes = [for (final c in used) c.totalInteractionMinutes.toDouble()];
  final answered = [
    for (final c in used)
      if (c.honestyYes != null) c,
  ];
  return CloseTrends(
    days: n,
    moodMean: used.fold(0, (s, c) => s + c.mood) / n,
    energyMean: used.fold(0, (s, c) => s + c.energy) / n,
    interactionMeanMinutes: minutes.reduce((a, b) => a + b) / n,
    honestyYesDays: answered.where((c) => c.honestyYes!).length,
    answeredDays: answered.length,
    moodVsInteraction: pearson([
      for (final c in used) c.mood.toDouble(),
    ], minutes),
    energyVsInteraction: pearson([
      for (final c in used) c.energy.toDouble(),
    ], minutes),
  );
}

/// A correlation in plain words: its value and direction, never a verdict
/// about the person.
String correlationEs(double? r) {
  if (r == null) return 'sin dato (sin variación suficiente)';
  final value = r.toStringAsFixed(2).replaceAll('.', ',');
  if (r == 0) return 'r = $value, sin relación';
  return 'r = $value, ${r > 0 ? 'suben juntas' : 'una sube cuando la otra baja'}';
}
