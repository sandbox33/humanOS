/// Money as integer cents (never `double` in storage). Parsing and
/// formatting for Spanish (Ecuador) input: "4,75", "4.75", "$12", "1.250,50".
library;

/// Parses a typed amount into cents. Accepts a comma or a dot as decimal
/// separator; a separator followed by exactly three digits and more
/// separators is read as thousands ("1.250,50" → 125050). More than two
/// decimals round half up ("4,755" → 476). Null for empty or invalid text.
int? parseCents(String text) {
  var t = text.trim().replaceAll(RegExp(r'[\s$]|usd|USD'), '');
  if (t.isEmpty) return null;
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  if (!RegExp(r'^[0-9.,]+$').hasMatch(t)) return null;
  final separators = RegExp(r'[.,]').allMatches(t).toList();
  String whole;
  String fraction;
  if (separators.isEmpty) {
    whole = t;
    fraction = '';
  } else {
    final last = separators.last;
    final tail = t.substring(last.end);
    final thousandsOnly =
        separators.length > 1 &&
        separators.every((m) => m.group(0) == separators.first.group(0)) &&
        tail.length == 3;
    if (thousandsOnly) {
      whole = t.replaceAll(RegExp(r'[.,]'), '');
      fraction = '';
    } else {
      whole = t.substring(0, last.start).replaceAll(RegExp(r'[.,]'), '');
      fraction = tail;
    }
  }
  if (whole.isEmpty) whole = '0';
  if (!RegExp(r'^\d+$').hasMatch(whole) ||
      !RegExp(r'^\d*$').hasMatch(fraction)) {
    return null;
  }
  var cents = int.parse(whole) * 100;
  if (fraction.isNotEmpty) {
    final padded = '${fraction}00'.substring(0, 2);
    cents += int.parse(padded);
    if (fraction.length > 2 && int.parse(fraction[2]) >= 5) cents += 1;
  }
  return negative ? -cents : cents;
}

/// "4,75 USD", "1250,50 USD", "-0,40 USD".
String formatCents(int cents, {bool withCurrency = true}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final text =
      '${negative ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
  return withCurrency ? '$text USD' : text;
}

/// Integer division rounding half away from zero: the one rule used for
/// every money computation (rate × time, shares, averages).
int divRound(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'no puede ser 0');
  }
  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs(), d = denominator.abs();
  final q = (2 * n + d) ~/ (2 * d);
  return negative ? -q : q;
}

/// [cents] × [percent] / 100, rounded half away from zero.
int percentOfCents(int cents, int percent) => divRound(cents * percent, 100);
