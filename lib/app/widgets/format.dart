import 'package:humanos_core/humanos_core.dart';
import 'package:intl/intl.dart';

/// "sin dato" is the only way an unknown number is shown.
const sinDato = 'sin dato';

String fmtNum(double? value, {int decimals = 0, String unit = ''}) {
  if (value == null || value.isNaN) return sinDato;
  final text = formatDecimal(value, decimals: decimals);
  return unit.isEmpty ? text : '$text $unit';
}

/// A total that may be a floor because some item had no data.
String fmtTotal(double? value, {required bool partial, int decimals = 0, String unit = ''}) {
  if (value == null) return sinDato;
  final text = fmtNum(value, decimals: decimals, unit: unit);
  return partial ? '≥ $text' : text;
}

final DateFormat _dayFormat = DateFormat("EEE d 'de' MMM", 'es');
final DateFormat _shortDay = DateFormat('d MMM', 'es');
final DateFormat _time = DateFormat('HH:mm', 'es');

String fmtDay(DateTime day) => _dayFormat.format(day).toUpperCase();
String fmtShortDay(DateTime day) => _shortDay.format(day);
String fmtTime(DateTime time) => _time.format(time);

String fmtUsd(double? value) =>
    value == null ? sinDato : '\$${formatDecimal(value, decimals: 2)}';
