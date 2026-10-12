/// Number formatting for user-facing Spanish (es-EC) messages produced by
/// the engines: comma as decimal separator, no thousands grouping noise.
library;

/// Formats [value] with exactly [decimals] decimals and a comma separator.
String formatDecimal(double value, {int decimals = 1}) {
  final fixed = value.toStringAsFixed(decimals);
  final normalized = fixed == '-0' || RegExp(r'^-0[.,]0+$').hasMatch(fixed)
      ? fixed.substring(1)
      : fixed;
  return normalized.replaceAll('.', ',');
}

/// Formats an integer-like quantity (kcal, mg, g) without decimals.
String formatWhole(double value) => formatDecimal(value, decimals: 0);

/// Formats a duration in minutes as `5 h 20 min`, `45 min` or `8 h`.
String formatHoursMinutes(double minutes) {
  final total = minutes.round();
  final sign = total < 0 ? '-' : '';
  final abs = total.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  if (h == 0) return '$sign$m min';
  if (m == 0) return '$sign$h h';
  return '$sign$h h $m min';
}
