import 'package:flutter/material.dart';
import 'package:humanos_core/humanos_core.dart';

import '../theme.dart';

/// The band's colour in the current theme.
Color bandColor(HosLook look, ReadinessBand band) => switch (band) {
      ReadinessBand.verde => look.ok,
      ReadinessBand.amarillo => look.warn,
      ReadinessBand.rojo => look.danger,
    };

/// Readiness band as a solid block with its code.
class BandBadge extends StatelessWidget {
  const BandBadge(this.band, {super.key, this.large = false});
  final ReadinessBand band;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final color = bandColor(look, band);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 18 : 10, vertical: large ? 8 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        band.code,
        style: look.statusStyle(large ? 40 : 24, color),
      ),
    );
  }
}

/// Confidence of a number: alta / media / baja (and a mixed label).
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip(this.label, {super.key, this.tooltip});

  ConfidenceChip.of(Confidence confidence, {Key? key, String? tooltip})
      : this(confidence.code, key: key, tooltip: tooltip);

  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.6)),
      ),
      child: Text('CONF. ${label.toUpperCase()}', style: theme.textTheme.labelSmall),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

/// Small bordered tag (taxonomy chips).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.look.surfaceHigh,
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: theme.textTheme.labelMedium),
    );
  }
}
