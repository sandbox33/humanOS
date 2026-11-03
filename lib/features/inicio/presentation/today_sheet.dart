import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/clock_picker.dart';
import '../../../app/widgets/hos_page.dart';
import '../domain/schedule_model.dart';

String _clockOf(int minute) => formatClock(minute % (24 * 60));

/// AJUSTAR HOY: skip, move or end a block at another time, or add one
/// (overtime, an errand) for today only. The rest of the day is
/// recalculated at once; the weekly template is not touched.
class TodaySheet extends ConsumerWidget {
  const TodaySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const TodaySheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = ref.watch(dayPlanProvider(0));
    final today = ref.watch(todayProvider);
    final repo = ref.read(scheduleRepositoryProvider);
    final changed = plan.any((b) => b.status != BlockStatus.normal);

    Future<void> act(PlannedBlock b, String action) async {
      switch (action) {
        case 'saltar':
          await repo.addAdjustment(date: today, action: AdjustAction.saltar, blockId: b.id);
        case 'mover':
          final t = await pickClock(context, initial: _clockOf(b.startMin), help: 'Nueva hora de inicio');
          if (t != null) await repo.addAdjustment(date: today, action: AdjustAction.mover, blockId: b.id, startClock: t);
        case 'extender':
          final t = await pickClock(context, initial: _clockOf(b.endMin), help: 'Termina a las');
          if (t != null) await repo.addAdjustment(date: today, action: AdjustAction.extender, blockId: b.id, endClock: t);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('AJUSTAR HOY', style: theme.textTheme.titleLarge),
            Text('El resto del día se recalcula. Dormir solo se mueve si tú lo mueves.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final b in plan)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${_clockOf(b.startMin)}–${_clockOf(b.endMin)} · ${b.title}'),
                subtitle: b.status == BlockStatus.normal ? null : Text(b.status.labelEs.toUpperCase()),
                trailing: !b.fromTemplate
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Cambiar hoy',
                        onSelected: (a) => act(b, a),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'saltar', child: Text('Saltar hoy')),
                          PopupMenuItem(value: 'mover', child: Text('Mover hoy')),
                          PopupMenuItem(value: 'extender', child: Text('Termina hoy a las…')),
                        ],
                      ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('AGREGAR SOLO HOY'),
              onPressed: () => _addForToday(context, ref),
            ),
            if (changed)
              TextButton(
                onPressed: () => repo.clearDay(today),
                child: const Text('VOLVER AL HORARIO DE SIEMPRE'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _addForToday(BuildContext context, WidgetRef ref) async {
  final kind = await showDialog<BlockKind>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('¿QUÉ AGREGAS HOY?'),
      children: [
        for (final k in BlockKind.values)
          SimpleDialogOption(onPressed: () => Navigator.of(context).pop(k), child: Text(k.labelEs)),
      ],
    ),
  );
  if (kind == null || !context.mounted) return;
  final start = await pickClock(context, help: 'Empieza a las');
  if (start == null || !context.mounted) return;
  final end = await pickClock(context, help: 'Termina a las');
  if (end == null) return;
  if (end == start) {
    if (context.mounted) toast(context, 'El inicio y el fin no pueden ser iguales.');
    return;
  }
  await ref.read(scheduleRepositoryProvider).addAdjustment(
        date: ref.read(todayProvider),
        action: AdjustAction.agregar,
        kind: kind,
        startClock: start,
        endClock: end,
      );
}
