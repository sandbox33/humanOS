import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Feedback tied to a real event (PR, streak, attribute up): one short
/// border flash (≤ 600 ms) and a haptic pulse. No loot, no randomness, no
/// decorative animation; the caller skips it when the user disabled it.
abstract final class EventFeedback {
  static const duration = Duration(milliseconds: 600);

  static Future<void> show(BuildContext context, String message) async {
    final overlay = Overlay.maybeOf(context);
    unawaited(HapticFeedback.heavyImpact());
    if (overlay == null) return;
    final color = Theme.of(context).colorScheme.primary;
    final entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: color, width: 6)),
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 64),
          child: Material(
            color: Colors.transparent,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                message.toUpperCase(),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    await Future<void>.delayed(duration);
    entry.remove();
  }
}
