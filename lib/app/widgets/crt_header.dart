import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';

/// Loads the scanline shader once; null when shaders are unavailable.
final crtProgramProvider = FutureProvider<ui.FragmentProgram?>((ref) async {
  try {
    return await ui.FragmentProgram.fromAsset('assets/shaders/crt.frag');
  } on Object {
    return null;
  }
});

/// Screen header: the uppercase title in the theme's display font. In
/// WASTELAND it carries static CRT scanlines (only on headers, never
/// animated, switched off automatically if frames lag); in GRIMORIO a still
/// rule of runes underlines it.
class CrtHeader extends ConsumerWidget {
  const CrtHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final look = context.look;
    final enabled = look.terminal && ref.watch(crtEnabledProvider);
    final program = enabled ? ref.watch(crtProgramProvider).value : null;
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: theme.textTheme.headlineLarge),
          if (!look.terminal)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                height: 10,
                width: double.infinity,
                child: CustomPaint(painter: RuneRulePainter(theme.colorScheme.primary)),
              ),
            ),
          if (subtitle != null)
            Text(subtitle!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    if (program == null) return text;
    return Stack(
      children: [
        text,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinePainter(program)),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.program);
  final ui.FragmentProgram program;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, 0.35);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) =>
      oldDelegate.program != program;
}

/// A still line with small angular marks (original drawing, no asset):
/// the book's equivalent of the terminal's scanlines.
class RuneRulePainter extends CustomPainter {
  RuneRulePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), pen);
    const step = 36.0;
    final h = size.height / 2 - 1;
    var i = 0;
    for (var x = step / 2; x < size.width; x += step, i++) {
      final mark = Path();
      switch (i % 3) {
        case 0: // diamond
          mark
            ..moveTo(x, mid - h)
            ..lineTo(x + h, mid)
            ..lineTo(x, mid + h)
            ..lineTo(x - h, mid)
            ..close();
        case 1: // arrow stave
          mark
            ..moveTo(x, mid - h)
            ..lineTo(x, mid + h)
            ..moveTo(x - h, mid - h)
            ..lineTo(x, mid)
            ..lineTo(x + h, mid - h);
        default: // crossed stave
          mark
            ..moveTo(x - h, mid - h)
            ..lineTo(x + h, mid + h)
            ..moveTo(x + h, mid - h)
            ..lineTo(x - h, mid + h);
      }
      canvas.drawPath(mark, pen);
    }
  }

  @override
  bool shouldRepaint(RuneRulePainter oldDelegate) => oldDelegate.color != color;
}
