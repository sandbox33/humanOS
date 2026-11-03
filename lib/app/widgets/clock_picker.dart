import 'package:flutter/material.dart';
import 'package:humanos_core/humanos_core.dart';

/// Picks a time of day; returns `HH:MM` or null when cancelled.
Future<String?> pickClock(BuildContext context, {String? initial, String? help}) async {
  var start = TimeOfDay.now();
  if (initial != null) {
    try {
      final m = parseClock(initial);
      start = TimeOfDay(hour: m ~/ 60, minute: m % 60);
    } on FormatException {
      // Keep the current time.
    }
  }
  final picked = await showTimePicker(
    context: context,
    initialTime: start,
    helpText: help,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (picked == null) return null;
  return formatClock(picked.hour * 60 + picked.minute);
}
