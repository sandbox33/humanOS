import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/clock_picker.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../contexto/domain/context_model.dart';
import '../../contexto/presentation/xiaomi_guide_page.dart';
import '../../trabajo/data/work_repository.dart' show TemplateStatus, stampOf;

const _weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// ALARMAS: the user's morning alarms. Exact alarm-clock alarms with alarm
/// volume and a full-screen screen, rung by the phone even with the app
/// closed.
class AlarmasScreen extends ConsumerWidget {
  const AlarmasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(alarmRowsProvider).value ?? const <MorningAlarmRow>[];
    final now = ref.watch(clockProvider)();
    final repo = ref.read(contextRepositoryProvider);
    return HosPage(
      title: 'ALARMAS',
      subtitle: 'Suenan con volumen de alarma y pantalla completa',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nueva-alarma',
        icon: const Icon(Icons.alarm_add),
        label: const Text('NUEVA'),
        onPressed: () => _AlarmEditor.show(context),
      ),
      body: PanelList(children: [
        if (rows.isEmpty) const Note('Sin alarmas. Crea una con el botón NUEVA: hora, días y minutos para posponer.'),
        for (final a in rows)
          TerminalPanel(
            label: '${a.clock} · ${a.label}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${weekdaysOf(a.daysMask).map((d) => _weekdayLetters[d - 1]).join(' ')} · posponer '
                  '${a.snoozeMinutes} min · ${TemplateStatus.parse(a.status).labelEs}',
                ),
                if (TemplateStatus.parse(a.status) == TemplateStatus.activo)
                  if (_next(a, now) case final next?)
                    DataLine('Próxima', '${fmtShortDay(next)} ${fmtTime(next)} · ${untilAlarmEs(next, now)}'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(onPressed: () => _AlarmEditor.show(context, existing: a), child: const Text('EDITAR')),
                  if (TemplateStatus.parse(a.status) == TemplateStatus.activo)
                    OutlinedButton(
                      onPressed: () => repo.setAlarmStatus(a.id, TemplateStatus.pausado),
                      child: const Text('PAUSAR'),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => repo.setAlarmStatus(a.id, TemplateStatus.activo),
                      child: const Text('ACTIVAR'),
                    ),
                  if (TemplateStatus.parse(a.status) != TemplateStatus.archivado)
                    OutlinedButton(
                      onPressed: () => repo.setAlarmStatus(a.id, TemplateStatus.archivado),
                      child: const Text('ARCHIVAR'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await confirm(context, title: 'Borrar alarma', message: a.label, accept: 'BORRAR');
                      if (ok) await repo.deleteAlarm(a.id);
                    },
                    child: const Text('BORRAR'),
                  ),
                ]),
              ],
            ),
          ),
        TerminalPanel(
          label: 'Comprobar',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('PROBAR SONIDO AHORA'),
                onPressed: () => ref.read(alarmServiceProvider).ringNow('Prueba de alarma'),
              ),
              const Note('Para confiar en una alarma: créala para dentro de 2 h, cierra la app y confirma que '
                  'suena. En Xiaomi/HyperOS sigue antes la guía.'),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const XiaomiGuidePage())),
                child: const Text('GUÍA XIAOMI / HYPEROS'),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  static DateTime? _next(MorningAlarmRow a, DateTime now) {
    try {
      return nextAlarmAt(minuteOfDay: parseClock(a.clock), daysMask: a.daysMask, now: now);
    } on FormatException {
      return null;
    }
  }
}

class _AlarmEditor extends ConsumerStatefulWidget {
  const _AlarmEditor({this.existing});

  final MorningAlarmRow? existing;

  static Future<void> show(BuildContext context, {MorningAlarmRow? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _AlarmEditor(existing: existing),
      );

  @override
  ConsumerState<_AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends ConsumerState<_AlarmEditor> {
  late final TextEditingController _label = TextEditingController(text: widget.existing?.label ?? 'Despertar');
  late String? _clock = widget.existing?.clock;
  late Set<int> _days = weekdaysOf(widget.existing?.daysMask ?? daysMaskOf([1, 2, 3, 4, 5])).toSet();
  late double _snooze =
      (widget.existing?.snoozeMinutes ?? ref.read(currentAssumptionsProvider).integer(A.alarmSnoozeMin)).toDouble();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    if (label.isEmpty || _clock == null || _days.isEmpty) {
      toast(context, 'Pon un nombre, la hora y al menos un día.');
      return;
    }
    final companion = MorningAlarmsCompanion(
      label: Value(label),
      clock: Value(_clock!),
      daysMask: Value(daysMaskOf(_days)),
      snoozeMinutes: Value(_snooze.round()),
    );
    final repo = ref.read(contextRepositoryProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.saveAlarm(companion.copyWith(createdAt: Value(stampOf(ref.read(clockProvider)()))));
    } else {
      await repo.saveAlarm(companion, id: existing.id);
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
            Text(widget.existing == null ? 'NUEVA ALARMA' : 'EDITAR ALARMA', style: theme.textTheme.titleLarge),
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final v = await pickClock(context, initial: _clock, help: 'Hora de la alarma');
                if (v != null) setState(() => _clock = v);
              },
              child: Text('HORA ${_clock ?? '--:--'}', style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            Text('Días', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                FilterChip(
                  label: Text(_weekdayLetters[d - 1]),
                  selected: _days.contains(d),
                  onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ]),
            const SizedBox(height: 8),
            Text('Posponer', style: theme.textTheme.labelLarge),
            ValueStepper(
              value: _snooze,
              unit: 'min',
              min: 1,
              max: 30,
              steps: const [1, 5],
              onChanged: (v) => setState(() => _snooze = v),
            ),
            const SizedBox(height: 12),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
