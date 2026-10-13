import 'package:flutter/material.dart';
import 'package:humanos_core/humanos_core.dart';

import '../theme.dart';

/// Large numeric stepper (grams, kg, litres) usable with one hand.
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.unit,
    this.steps = const [10, 50],
    this.min = 0,
    this.max = 5000,
    this.decimals = 0,
    this.onTapValue,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String unit;
  final List<double> steps;
  final double min;
  final double max;
  final int decimals;

  /// Opens a numeric dialog to type the value.
  final VoidCallback? onTapValue;

  void _apply(double delta) {
    final next = (value + delta).clamp(min, max).toDouble();
    onChanged(double.parse(next.toStringAsFixed(decimals)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget button(double delta) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: OutlinedButton(
              onPressed: () => _apply(delta),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, kTouchTarget),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                '${delta > 0 ? '+' : '−'}${formatDecimal(delta.abs(), decimals: decimals)}',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTapValue,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${formatDecimal(value, decimals: decimals)} $unit',
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium,
            ),
          ),
        ),
        Row(children: [
          for (final s in steps.reversed) button(-s),
          for (final s in steps) button(s),
        ]),
      ],
    );
  }
}

/// Asks for a number with a numeric keyboard; null when cancelled.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  double? initial,
  String unit = '',
  int decimals = 1,
}) async {
  final controller = TextEditingController(
    text: initial == null ? '' : formatDecimal(initial, decimals: decimals),
  );
  final result = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title.toUpperCase()),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: unit),
        onSubmitted: (text) => Navigator.of(context)
            .pop(double.tryParse(text.replaceAll(',', '.'))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
          child: const Text('ACEPTAR'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
