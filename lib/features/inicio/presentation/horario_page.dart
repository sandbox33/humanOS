import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/clock_picker.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../domain/schedule_model.dart';

const weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// HORARIO: the user's weekly template. Every block, time and weekday is
/// the user's; nothing is preloaded.
class HorarioPage extends ConsumerWidget {
  const HorarioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(blockRowsProvider).value ?? const <ScheduleBlockRow>[];
    final active = [for (final r in rows) if (r.status != 'archivado') r];
    final archived = [for (final r in rows) if (r.status == 'archivado') r];
    return HosPage(
      title: 'HORARIO',
      subtitle: 'Tu día por bloques, por día de la semana',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Bloques',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (active.isEmpty) const Note('Sin bloques. Crea el primero con su hora y sus días.'),
              for (final r in active) _BlockTile(row: r),
              const SizedBox(height: 8),
              BigButton(label: 'Nuevo bloque', icon: Icons.add, onPressed: () => BlockEditor.show(context)),
              const Note('Las comidas son momentos cortos y pueden caer dentro del trabajo. Trabajo, horas extra y '
                  'dormir mantienen su hora; proyecto, ocio, cocinar y entreno se acomodan cuando cambias el día.'),
            ],
          ),
        ),
        if (archived.isNotEmpty)
          TerminalPanel(
            label: 'Archivados',
            child: Column(children: [for (final r in archived) _BlockTile(row: r)]),
          ),
      ]),
    );
  }
}

class _BlockTile extends ConsumerWidget {
  const _BlockTile({required this.row});
  final ScheduleBlockRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = BlockKind.parse(row.kind);
    final days = weekdaysOf(row.daysMask).map((d) => weekdayLetters[d - 1]).join(' ');
    final repo = ref.read(scheduleRepositoryProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(row.alarm ? Icons.alarm_on : Icons.schedule),
      title: Text('${row.startClock} · ${row.label ?? kind.labelEs}'),
      subtitle: Text(
        '$days${row.durationMin == null ? '' : ' · ${formatWorkMinutes(row.durationMin!)}'}'
        '${row.status == 'pausado' ? ' · PAUSADO' : ''}',
      ),
      onTap: () => BlockEditor.show(context, existing: row),
      trailing: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (s) => repo.setStatus(row.id, s),
        itemBuilder: (_) => [
          if (row.status != 'activo') const PopupMenuItem(value: 'activo', child: Text('Activar')),
          if (row.status == 'activo') const PopupMenuItem(value: 'pausado', child: Text('Pausar')),
          if (row.status != 'archivado') const PopupMenuItem(value: 'archivado', child: Text('Archivar')),
        ],
      ),
    );
  }
}

/// Creates or edits one template block.
class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({super.key, this.existing});

  final ScheduleBlockRow? existing;

  static Future<void> show(BuildContext context, {ScheduleBlockRow? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BlockEditor(existing: existing),
      );

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  late BlockKind _kind;
  late final TextEditingController _label;
  late final TextEditingController _duration;
  String? _start;
  late Set<int> _days;
  late bool _alarm;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = BlockKind.parse(e?.kind);
    _label = TextEditingController(text: e?.label ?? '');
    _duration = TextEditingController(text: e?.durationMin?.toString() ?? '');
    _start = e?.startClock;
    _days = e == null ? <int>{} : weekdaysOf(e.daysMask).toSet();
    _alarm = e?.alarm ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final start = _start;
    if (start == null) {
      toast(context, 'Elige la hora de inicio.');
      return;
    }
    if (_days.isEmpty) {
      toast(context, 'Elige al menos un día.');
      return;
    }
    final durationText = _duration.text.trim();
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    if (durationText.isNotEmpty && (duration == null || duration <= 0)) {
      toast(context, 'La duración va en minutos, por ejemplo 90.');
      return;
    }
    final repo = ref.read(scheduleRepositoryProvider);
    final e = widget.existing;
    if (e == null) {
      await repo.addBlock(
        kind: _kind,
        startClock: start,
        daysMask: daysMaskOf(_days),
        label: _label.text,
        durationMin: duration,
        alarm: _alarm,
      );
    } else {
      await repo.updateBlock(
        e.id,
        kind: _kind,
        startClock: start,
        daysMask: daysMaskOf(_days),
        label: _label.text,
        durationMin: duration,
        alarm: _alarm,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'NUEVO BLOQUE' : 'EDITAR BLOQUE', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final k in BlockKind.values)
                ChoiceChip(label: Text(k.labelEs), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
            ]),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nombre (opcional)')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(_start == null ? 'HORA DE INICIO' : 'INICIO $_start'),
              onPressed: () async {
                final picked = await pickClock(context, initial: _start, help: 'Inicio del bloque');
                if (picked != null) setState(() => _start = picked);
              },
            ),
            TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duración en minutos (vacío: hasta el siguiente bloque)'),
            ),
            const SizedBox(height: 8),
            Text('DÍAS', style: theme.textTheme.titleSmall),
            Wrap(spacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayLetters[d - 1]),
                  selected: _days.contains(d),
                  onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ALARMA'),
              subtitle: const Text('Suena a la hora exacta, también con la pantalla bloqueada.'),
              value: _alarm,
              onChanged: (v) => setState(() => _alarm = v),
            ),
            const SizedBox(height: 8),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
