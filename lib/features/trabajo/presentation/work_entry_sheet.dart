import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/clock_picker.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../data/user_db.dart';
import '../data/work_repository.dart';
import '../domain/work_model.dart';

/// How the hours are entered in the quick form.
enum _TimeMode { range, duration, startNow }

/// Quick log: template → hours → save (three taps when the template has
/// times). Also edits an existing entry.
class WorkEntrySheet extends ConsumerStatefulWidget {
  const WorkEntrySheet({super.key, this.template, this.existing, this.prefill});

  final WorkTemplateRow? template;
  final WorkEntryRow? existing;

  /// A `work_entry` record from the assistant: the form starts with it and
  /// the user confirms.
  final LogIntent? prefill;

  static Future<void> show(
    BuildContext context, {
    WorkTemplateRow? template,
    WorkEntryRow? existing,
    LogIntent? prefill,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => WorkEntrySheet(template: template, existing: existing, prefill: prefill),
      );

  @override
  ConsumerState<WorkEntrySheet> createState() => _WorkEntrySheetState();
}

class _WorkEntrySheetState extends ConsumerState<WorkEntrySheet> {
  late final TextEditingController _label;
  late final TextEditingController _rate;
  late final TextEditingController _total;
  late final TextEditingController _note;
  late WorkKind _kind;
  late _TimeMode _mode;
  String? _start;
  String? _end;
  double _hours = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? t?.label ?? '');
    final rate = e?.rateCentsPerHour ?? t?.rateCentsPerHour;
    _rate = TextEditingController(text: rate == null ? '' : formatCents(rate, withCurrency: false));
    _total = TextEditingController(
      text: e != null && e.rateCentsPerHour == null && e.earnedCents != null
          ? formatCents(e.earnedCents!, withCurrency: false)
          : '',
    );
    _note = TextEditingController(text: e?.note ?? '');
    _kind = WorkKind.parse(e?.kind ?? t?.kind);
    final start = parseStamp(e?.startTs);
    final end = parseStamp(e?.endTs);
    if (start != null) _start = formatClock(start.hour * 60 + start.minute);
    if (end != null) _end = formatClock(end.hour * 60 + end.minute);
    _start ??= t?.startClock;
    _end ??= t?.endClock;
    _hours = (e?.minutes ?? 0) / 60;
    final p = widget.prefill?.fields;
    if (p != null) {
      if (p['label'] case final String label) _label.text = label;
      if (p['start'] case final String start) _start = start;
      if (p['end'] case final String end) _end = end;
      if (p['minutes'] case final int minutes) _hours = minutes / 60;
      if (p['rate_cents'] case final int rate) _rate.text = formatCents(rate, withCurrency: false);
      if (p['total_cents'] case final int total) _total.text = formatCents(total, withCurrency: false);
    }
    _mode = (_start != null && _end != null) ? _TimeMode.range : _TimeMode.duration;
  }

  @override
  void dispose() {
    for (final c in [_label, _rate, _total, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _breakMinutes() {
    final t = widget.template;
    if (t?.breakMinutes == null || _mode != _TimeMode.range) return null;
    return t!.breakMinutes;
  }

  Future<void> _save() async {
    if (_saving) return;
    final today = ref.read(todayProvider);
    final existing = widget.existing;
    final date = existing == null ? today : parseIsoDate(existing.date);
    final now = ref.read(clockProvider)();
    int? startMin, endMin, minutes;
    switch (_mode) {
      case _TimeMode.range:
        if (_start == null || _end == null) {
          toast(context, 'Elige la hora de inicio y la de fin.');
          return;
        }
        startMin = parseClock(_start!);
        endMin = parseClock(_end!);
      case _TimeMode.duration:
        minutes = (_hours * 60).round();
      case _TimeMode.startNow:
        startMin = now.hour * 60 + now.minute;
    }
    final total = _total.text.trim().isEmpty ? null : parseCents(_total.text);
    final rate = _rate.text.trim().isEmpty ? null : parseCents(_rate.text);
    if ((_total.text.trim().isNotEmpty && total == null) || (_rate.text.trim().isNotEmpty && rate == null)) {
      toast(context, 'Revisa los montos: usa números como 12,50.');
      return;
    }
    final built = buildWorkEntry(
      date: date,
      label: _label.text,
      kind: _kind,
      startMin: startMin,
      endMin: endMin,
      minutes: minutes,
      rateCentsPerHour: rate,
      totalCents: total,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final entry = built.entry;
    if (entry == null) {
      toast(context, built.issues.map((i) => i.messageEs).join(' '));
      return;
    }
    // A planned break is not paid time.
    final pause = _breakMinutes();
    final adjusted = pause == null || entry.minutes <= pause
        ? entry
        : WorkEntry(
            date: entry.date,
            label: entry.label,
            kind: entry.kind,
            start: entry.start,
            end: entry.end,
            minutes: entry.minutes - pause,
            rateCentsPerHour: entry.rateCentsPerHour,
            earnedCents: entry.rateCentsPerHour == null
                ? entry.earnedCents
                : earnedFor(entry.minutes - pause, entry.rateCentsPerHour!),
            note: entry.note,
          );
    setState(() => _saving = true);
    final repo = ref.read(workRepositoryProvider);
    if (existing == null) {
      await repo.addEntry(adjusted, templateId: widget.template?.id, now: now);
    } else {
      await repo.replaceEntry(existing.id, adjusted);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'REGISTRAR TRABAJO' : 'EDITAR TRABAJO',
                style: theme.textTheme.titleLarge),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Trabajo')),
            const SizedBox(height: 8),
            SegmentedButton<WorkKind>(
              segments: [
                for (final k in WorkKind.values) ButtonSegment(value: k, label: Text(k.labelEs.toUpperCase())),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_TimeMode>(
              segments: [
                const ButtonSegment(value: _TimeMode.range, label: Text('INICIO–FIN')),
                const ButtonSegment(value: _TimeMode.duration, label: Text('HORAS')),
                if (widget.existing == null)
                  const ButtonSegment(value: _TimeMode.startNow, label: Text('EMPIEZO YA')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            switch (_mode) {
              _TimeMode.range => Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final v = await pickClock(context, initial: _start, help: 'Inicio');
                        if (v != null) setState(() => _start = v);
                      },
                      child: Text('INICIO ${_start ?? '--:--'}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final v = await pickClock(context, initial: _end, help: 'Fin');
                        if (v != null) setState(() => _end = v);
                      },
                      child: Text('FIN ${_end ?? '--:--'}'),
                    ),
                  ),
                ]),
              _TimeMode.duration => ValueStepper(
                  value: _hours,
                  unit: 'h',
                  decimals: 2,
                  min: 0,
                  max: 24,
                  steps: const [0.25, 1],
                  onChanged: (v) => setState(() => _hours = v),
                ),
              _TimeMode.startNow => const Text(
                  'Se guarda como «en curso». Márcalo TERMINAR al salir: mientras '
                  'tanto no llegan avisos.',
                ),
            },
            if (_mode == _TimeMode.range && _breakMinutes() != null)
              Text('Se descuenta la pausa de ${_breakMinutes()} min de la plantilla.',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _rate,
                  decoration: const InputDecoration(labelText: 'Tarifa por hora', suffixText: 'USD'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: money,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _total,
                  decoration: const InputDecoration(labelText: 'o total ganado', suffixText: 'USD'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: money,
                ),
              ),
            ]),
            Text('Ambos opcionales. Con el total, la tarifa queda vacía.', style: theme.textTheme.bodySmall),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            const SizedBox(height: 12),
            BigButton(
              label: _saving ? 'Guardando…' : 'Guardar',
              icon: Icons.check,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
