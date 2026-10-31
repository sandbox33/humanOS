import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/clock_picker.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../data/work_repository.dart';
import '../domain/work_model.dart';

const _weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Work templates: the user's own shortcuts (label, rate, usual hours and
/// planned days). Create, edit, pause, archive or delete.
class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(workTemplatesProvider).value ?? const <WorkTemplateRow>[];
    final repo = ref.read(workRepositoryProvider);
    return HosPage(
      title: 'PLANTILLAS',
      subtitle: 'Tus trabajos frecuentes',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-plantilla',
        icon: const Icon(Icons.add),
        label: const Text('NUEVA'),
        onPressed: () => _TemplateEditor.show(context),
      ),
      body: PanelList(children: [
        if (templates.isEmpty)
          const Note('Sin plantillas. Crea una con el botón NUEVA: nombre, tarifa y, si quieres, '
              'tus horas habituales y los días que trabajas.'),
        for (final t in templates)
          TerminalPanel(
            label: '${t.label} · ${TemplateStatus.parse(t.status).labelEs}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_describe(t), style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                    onPressed: () => _TemplateEditor.show(context, existing: t),
                    child: const Text('EDITAR'),
                  ),
                  if (TemplateStatus.parse(t.status) != TemplateStatus.activo)
                    OutlinedButton(
                      onPressed: () => repo.setTemplateStatus(t.id, TemplateStatus.activo),
                      child: const Text('ACTIVAR'),
                    ),
                  if (TemplateStatus.parse(t.status) == TemplateStatus.activo)
                    OutlinedButton(
                      onPressed: () => repo.setTemplateStatus(t.id, TemplateStatus.pausado),
                      child: const Text('PAUSAR'),
                    ),
                  if (TemplateStatus.parse(t.status) != TemplateStatus.archivado)
                    OutlinedButton(
                      onPressed: () => repo.setTemplateStatus(t.id, TemplateStatus.archivado),
                      child: const Text('ARCHIVAR'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: 'Borrar plantilla',
                        message: 'Los registros ya guardados no se borran.',
                        accept: 'BORRAR',
                      );
                      if (ok) await repo.deleteTemplate(t.id);
                    },
                    child: const Text('BORRAR'),
                  ),
                ]),
              ],
            ),
          ),
      ]),
    );
  }

  static String _describe(WorkTemplateRow t) {
    final parts = <String>[
      WorkKind.parse(t.kind).labelEs,
      if (t.rateCentsPerHour != null) '${formatCents(t.rateCentsPerHour!)}/h',
      if (t.startClock != null && t.endClock != null) '${t.startClock}–${t.endClock}',
      if (t.breakStart != null && t.breakMinutes != null) 'pausa ${t.breakStart} (${t.breakMinutes} min)',
      if (t.daysMask != null && t.daysMask != 0)
        weekdaysOf(t.daysMask).map((d) => _weekdayLetters[d - 1]).join(' '),
      if (t.heatExposure) 'con calor',
    ];
    return parts.join(' · ');
  }
}

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({this.existing});

  final WorkTemplateRow? existing;

  static Future<void> show(BuildContext context, {WorkTemplateRow? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _TemplateEditor(existing: existing),
      );

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final TextEditingController _label;
  late final TextEditingController _rate;
  late final TextEditingController _breakMinutes;
  late WorkKind _kind;
  String? _start, _end, _break;
  late Set<int> _days;
  late bool _heat;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _label = TextEditingController(text: t?.label ?? '');
    _rate = TextEditingController(
      text: t?.rateCentsPerHour == null ? '' : formatCents(t!.rateCentsPerHour!, withCurrency: false),
    );
    _breakMinutes = TextEditingController(text: t?.breakMinutes?.toString() ?? '');
    _kind = WorkKind.parse(t?.kind);
    _start = t?.startClock;
    _end = t?.endClock;
    _break = t?.breakStart;
    _days = weekdaysOf(t?.daysMask).toSet();
    _heat = t?.heatExposure ?? false;
  }

  @override
  void dispose() {
    for (final c in [_label, _rate, _breakMinutes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      toast(context, 'Ponle un nombre a la plantilla.');
      return;
    }
    final rate = _rate.text.trim().isEmpty ? null : parseCents(_rate.text);
    if (_rate.text.trim().isNotEmpty && (rate == null || rate < 0)) {
      toast(context, 'Revisa la tarifa: usa números como 3,25.');
      return;
    }
    final pause = int.tryParse(_breakMinutes.text.trim());
    if ((_start == null) != (_end == null)) {
      toast(context, 'Pon inicio y fin, o ninguno.');
      return;
    }
    final companion = WorkTemplatesCompanion(
      label: Value(label),
      kind: Value(_kind.code),
      rateCentsPerHour: Value(rate),
      startClock: Value(_start),
      endClock: Value(_end),
      breakStart: Value(_break),
      breakMinutes: Value(_break == null ? null : pause),
      daysMask: Value(_days.isEmpty ? null : daysMaskOf(_days)),
      heatExposure: Value(_heat),
    );
    final repo = ref.read(workRepositoryProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.saveTemplate(companion.copyWith(createdAt: Value(stampOf(DateTime.now()))));
    } else {
      await repo.saveTemplate(companion, id: existing.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _clockButton(String label, String? value, ValueChanged<String?> set) => Expanded(
        child: OutlinedButton(
          onPressed: () async {
            final v = await pickClock(context, initial: value, help: label);
            if (v != null) setState(() => set(v));
          },
          onLongPress: () => setState(() => set(null)),
          child: Text('$label ${value ?? '--:--'}'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'NUEVA PLANTILLA' : 'EDITAR PLANTILLA', style: theme.textTheme.titleLarge),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            SegmentedButton<WorkKind>(
              segments: [
                for (final k in WorkKind.values) ButtonSegment(value: k, label: Text(k.labelEs.toUpperCase())),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            TextField(
              controller: _rate,
              decoration: const InputDecoration(labelText: 'Tarifa sugerida por hora (opcional)', suffixText: 'USD'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
            const SizedBox(height: 12),
            Text('Horas habituales (opcional; mantén presionado para quitar)', style: theme.textTheme.labelLarge),
            Row(children: [
              _clockButton('INICIO', _start, (v) => _start = v),
              const SizedBox(width: 8),
              _clockButton('FIN', _end, (v) => _end = v),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _clockButton('PAUSA', _break, (v) => _break = v),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _breakMinutes,
                  decoration: const InputDecoration(labelText: 'Minutos de pausa'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text('Días que la trabajas (opcional)', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                FilterChip(
                  label: Text(_weekdayLetters[d - 1]),
                  selected: _days.contains(d),
                  onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ]),
            const Note('Con horas y días, la app calla los avisos durante ese trabajo (salvo en la '
                'pausa) y organiza tus comidas alrededor.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('TRABAJO CON CALOR'),
              subtitle: const Text('Activa el plan del termo: aviso antes de empezar y en la pausa.'),
              value: _heat,
              onChanged: (v) => setState(() => _heat = v),
            ),
            const SizedBox(height: 8),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
