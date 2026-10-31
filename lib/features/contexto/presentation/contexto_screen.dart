import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/settings.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../trabajo/data/work_repository.dart' show TemplateStatus, parseStamp, stampOf;
import '../domain/context_model.dart';
import 'disclosure_page.dart';
import 'xiaomi_guide_page.dart';
import 'zone_editor.dart';

/// CONTEXTO: the mode (location + time + state), the user's zones and the
/// manual buttons. Zones are opt-in and only use the system's geofences.
class ContextoScreen extends ConsumerWidget {
  const ContextoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HosPage(
      title: 'CONTEXTO',
      subtitle: 'Dónde estás y cómo estás, sin rastreo',
      body: PanelList(children: [
        _ModePanel(),
        _OutingPanel(),
        _ZonesPanel(),
        _EventRemindersPanel(),
        _BatteryPanel(),
        _RecentPanel(),
      ]),
    );
  }
}

String zoneKindLabel(ContextMode kind, String? custom) =>
    kind == ContextMode.otro && custom != null && custom.trim().isNotEmpty ? custom.trim().toUpperCase() : kind.labelEs;

class _ModePanel extends ConsumerWidget {
  const _ModePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(modeDecisionProvider);
    final state = ref.watch(recentStateProvider);
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Modo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(decision.mode.labelEs, style: theme.textTheme.headlineMedium),
          Text(decision.reasonEs, style: theme.textTheme.bodyMedium),
          if (decision.mode.silences)
            const Note('En este modo los avisos esperan: solo pasan el termo, la comida de la pausa y la '
                'seguridad de alimentos.'),
          if (decision.lowEnergy) const Note('Energía baja: si entrenas hoy, considera una sesión más suave.'),
          const SizedBox(height: 8),
          Text('¿No es así? Corrige con un toque:', style: theme.textTheme.labelLarge),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in ContextMode.zoneKinds)
              ChoiceChip(
                label: Text(m.labelEs),
                selected: decision.source == ModeSource.correccion && decision.mode == m,
                onSelected: (_) async {
                  await correctMode(ref, m);
                  if (context.mounted) toast(context, 'Modo: ${m.labelEs}.');
                },
              ),
          ]),
          const SizedBox(height: 12),
          Text('¿Cómo estás? (energía y ánimo, 1–5)', style: theme.textTheme.labelLarge),
          Wrap(spacing: 6, children: [
            for (var i = 1; i <= 5; i++)
              ChoiceChip(
                label: Text('$i'),
                selected: state == i,
                onSelected: (_) => ref.read(contextRepositoryProvider).addCheckin(ref.read(clockProvider)(), i),
              ),
          ]),
        ],
      ),
    );
  }
}

class _OutingPanel extends ConsumerWidget {
  const _OutingPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TerminalPanel(
      label: 'Llegué · Voy a salir',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: BigButton(
                label: 'Llegué',
                icon: Icons.login,
                onPressed: () => _OutingSheet.show(context, ContextTransition.enter),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigButton(
                label: 'Voy a salir',
                icon: Icons.logout,
                outlined: true,
                onPressed: () => _OutingSheet.show(context, ContextTransition.exit),
              ),
            ),
          ]),
          const Note('Funciona sin zonas. Las notas son opcionales y se guardan cifradas en el teléfono.'),
        ],
      ),
    );
  }
}

class _OutingSheet extends ConsumerStatefulWidget {
  const _OutingSheet(this.transition);

  final ContextTransition transition;

  static Future<void> show(BuildContext context, ContextTransition transition) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _OutingSheet(transition),
      );

  @override
  ConsumerState<_OutingSheet> createState() => _OutingSheetState();
}

class _OutingSheetState extends ConsumerState<_OutingSheet> {
  final _plan = TextEditingController();
  final _company = TextEditingController();
  int? _zoneId;
  int? _feeling;

  @override
  void dispose() {
    _plan.dispose();
    _company.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    final now = ref.read(clockProvider)();
    final repo = ref.read(contextRepositoryProvider);
    await repo.addEvent(
      at: now,
      transition: widget.transition,
      source: 'manual',
      zoneId: _zoneId,
      plan: _text(_plan),
      company: _text(_company),
      feeling: _feeling,
    );
    if (_feeling != null) await repo.addCheckin(now, _feeling!);
    await ref.read(deviceContextProvider).fireManual(
          widget.transition == ContextTransition.enter ? 'llegar' : 'salir',
          zoneId: _zoneId,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zones = (ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[])
        .where((z) => TemplateStatus.parse(z.status) == TemplateStatus.activo)
        .toList();
    final arriving = widget.transition == ContextTransition.enter;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(arriving ? 'LLEGUÉ' : 'VOY A SALIR', style: theme.textTheme.titleLarge),
            if (zones.isNotEmpty) ...[
              Text(arriving ? '¿A dónde? (opcional)' : '¿De dónde? (opcional)', style: theme.textTheme.labelLarge),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final z in zones)
                  ChoiceChip(
                    label: Text(z.name),
                    selected: _zoneId == z.id,
                    onSelected: (on) => setState(() => _zoneId = on ? z.id : null),
                  ),
              ]),
            ],
            TextField(controller: _plan, decoration: const InputDecoration(labelText: '¿Qué vas a hacer? (opcional)')),
            TextField(controller: _company, decoration: const InputDecoration(labelText: '¿Con quién? (opcional)')),
            const SizedBox(height: 8),
            Text('¿Cómo te sientes? (opcional, 1–5)', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (var i = 1; i <= 5; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: _feeling == i,
                  onSelected: (on) => setState(() => _feeling = on ? i : null),
                ),
            ]),
            const SizedBox(height: 12),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _ZonesPanel extends ConsumerWidget {
  const _ZonesPanel();

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final device = ref.read(deviceContextProvider);
    if (!await device.playServices()) {
      if (context.mounted) toast(context, 'Este teléfono no tiene Google Play services: las zonas no funcionan.');
      return;
    }
    if (!context.mounted) return;
    // Prominent disclosure before any location permission.
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DisclosurePage()),
    );
    if (accepted != true) return;
    var access = await device.requestForeground();
    if (!access.fine) {
      if (context.mounted) toast(context, 'Sin ubicación precisa las zonas no funcionan.');
      return;
    }
    if (!access.background && context.mounted) {
      final go = await confirm(
        context,
        title: 'Permitir todo el tiempo',
        message: 'En la pantalla que sigue elige «Permitir todo el tiempo». Sin eso el teléfono no puede '
            'avisar a HumanOS cuando entras o sales con la app cerrada.',
        accept: 'CONTINUAR',
      );
      if (!go) return;
      access = await device.requestBackground();
    }
    if (!access.readyForZones) {
      if (context.mounted) toast(context, 'Falta «Permitir todo el tiempo»: las zonas quedan apagadas.');
      return;
    }
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setBool(SettingKey.zonesEnabled, true);
    await settings.set(SettingKey.zonesDisclosureAt, stampOf(ref.read(clockProvider)()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final rows = ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[];
    final status = ref.watch(zoneSyncStatusProvider);
    final params = ref.watch(contextParamsProvider);
    final repo = ref.read(contextRepositoryProvider);
    final active = rows.where((r) => TemplateStatus.parse(r.status) == TemplateStatus.activo).length;
    return TerminalPanel(
      label: 'Zonas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ZONAS ACTIVADAS'),
            subtitle: const Text('Opcional. Usa las geocercas del sistema: sin rastreo ni historial de rutas.'),
            value: settings.zonesEnabled,
            onChanged: (on) async {
              if (on) {
                await _turnOn(context, ref);
              } else {
                await disableZones(ref);
              }
            },
          ),
          if (settings.batteryOverLimit)
            const Note('Tu prueba de batería superó tu límite: las zonas quedan apagadas hasta que cambies el límite.'),
          if (settings.zonesEnabled && status != null)
            Note(status.ok ? 'Zonas activas en el teléfono: ${status.count}.' : (status.errorEs ?? 'No se pudieron activar.')),
          DataLine('Activas', '$active de ${params.maxActiveZones}'),
          for (final r in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.name),
              subtitle: Text('${zoneKindLabel(ContextMode.parse(r.kind), r.kindLabel)} · ${r.radiusM} m · '
                  '${TemplateStatus.parse(r.status).labelEs}'),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'editar':
                      await ZoneEditor.show(context, existing: r);
                    case 'activar':
                      if (active >= params.maxActiveZones) {
                        toast(context, ZoneIssue.tooManyActive.messageEs);
                      } else {
                        await repo.setZoneStatus(r.id, TemplateStatus.activo);
                      }
                    case 'pausar':
                      await repo.setZoneStatus(r.id, TemplateStatus.pausado);
                    case 'archivar':
                      await repo.setZoneStatus(r.id, TemplateStatus.archivado);
                    case 'borrar':
                      final ok = await confirm(
                        context,
                        title: 'Borrar zona',
                        message: 'Se borran el nombre y las coordenadas. Las entradas y salidas pasadas quedan sin zona.',
                        accept: 'BORRAR',
                      );
                      if (ok) await repo.deleteZone(r.id);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'editar', child: Text('EDITAR')),
                  if (TemplateStatus.parse(r.status) != TemplateStatus.activo)
                    const PopupMenuItem(value: 'activar', child: Text('ACTIVAR')),
                  if (TemplateStatus.parse(r.status) == TemplateStatus.activo)
                    const PopupMenuItem(value: 'pausar', child: Text('PAUSAR')),
                  if (TemplateStatus.parse(r.status) != TemplateStatus.archivado)
                    const PopupMenuItem(value: 'archivar', child: Text('ARCHIVAR')),
                  const PopupMenuItem(value: 'borrar', child: Text('BORRAR')),
                ],
              ),
            ),
          if (rows.isEmpty) const Note('Sin zonas. Crea una con un nombre neutro, por ejemplo «Zona A».'),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('NUEVA ZONA'),
            onPressed: () => ZoneEditor.show(context),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const XiaomiGuidePage())),
            child: const Text('GUÍA XIAOMI / HYPEROS'),
          ),
        ],
      ),
    );
  }
}

class _EventRemindersPanel extends ConsumerWidget {
  const _EventRemindersPanel();

  Future<void> _edit(BuildContext context, WidgetRef ref, {EventReminderRow? existing}) async {
    final zones = (ref.read(zoneRowsProvider).value ?? const <ZoneRow>[])
        .where((z) => TemplateStatus.parse(z.status) == TemplateStatus.activo)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EventReminderEditor(existing: existing, zones: zones),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(eventReminderRowsProvider).value ?? const <EventReminderRow>[];
    final zones = ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[];
    final repo = ref.read(contextRepositoryProvider);
    String where(EventReminderRow r) {
      if (r.zoneId != null) return zones.where((z) => z.id == r.zoneId).firstOrNull?.name ?? 'zona borrada';
      if (r.zoneKind != null) return 'zonas ${ContextMode.parse(r.zoneKind).labelEs}';
      return 'cualquier lugar';
    }

    return TerminalPanel(
      label: 'Al llegar o salir',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            const Note('Recordatorios tuyos que salen al llegar a una zona o al salir (también con los botones '
                'Llegué y Voy a salir).'),
          for (final r in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.message),
              subtitle: Text('${r.trigger == 'llegar' ? 'Al llegar' : 'Al salir'} · ${where(r)} · '
                  '${TemplateStatus.parse(r.status).labelEs}'),
              onTap: () => _edit(context, ref, existing: r),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'activar':
                      await repo.setEventReminderStatus(r.id, TemplateStatus.activo);
                    case 'pausar':
                      await repo.setEventReminderStatus(r.id, TemplateStatus.pausado);
                    case 'archivar':
                      await repo.setEventReminderStatus(r.id, TemplateStatus.archivado);
                    case 'borrar':
                      await repo.deleteEventReminder(r.id);
                  }
                },
                itemBuilder: (_) => [
                  if (TemplateStatus.parse(r.status) != TemplateStatus.activo)
                    const PopupMenuItem(value: 'activar', child: Text('ACTIVAR')),
                  if (TemplateStatus.parse(r.status) == TemplateStatus.activo)
                    const PopupMenuItem(value: 'pausar', child: Text('PAUSAR')),
                  if (TemplateStatus.parse(r.status) != TemplateStatus.archivado)
                    const PopupMenuItem(value: 'archivar', child: Text('ARCHIVAR')),
                  const PopupMenuItem(value: 'borrar', child: Text('BORRAR')),
                ],
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('NUEVO RECORDATORIO'),
            onPressed: () => _edit(context, ref),
          ),
        ],
      ),
    );
  }
}

class _EventReminderEditor extends ConsumerStatefulWidget {
  const _EventReminderEditor({required this.zones, this.existing});

  final EventReminderRow? existing;
  final List<ZoneRow> zones;

  @override
  ConsumerState<_EventReminderEditor> createState() => _EventReminderEditorState();
}

class _EventReminderEditorState extends ConsumerState<_EventReminderEditor> {
  late final TextEditingController _message = TextEditingController(text: widget.existing?.message ?? '');
  late String _trigger = widget.existing?.trigger ?? 'llegar';
  late int? _zoneId = widget.existing?.zoneId;
  late String? _kind = widget.existing?.zoneKind;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      toast(context, 'Escribe el recordatorio.');
      return;
    }
    final companion = EventRemindersCompanion(
      message: Value(message),
      trigger: Value(_trigger),
      zoneId: Value(_zoneId),
      zoneKind: Value(_zoneId == null ? _kind : null),
    );
    final repo = ref.read(contextRepositoryProvider);
    final existing = widget.existing;
    if (existing == null) {
      await repo.saveEventReminder(companion.copyWith(createdAt: Value(stampOf(ref.read(clockProvider)()))));
    } else {
      await repo.saveEventReminder(companion, id: existing.id);
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
            Text(widget.existing == null ? 'NUEVO RECORDATORIO' : 'EDITAR RECORDATORIO', style: theme.textTheme.titleLarge),
            TextField(controller: _message, decoration: const InputDecoration(labelText: 'Recordatorio')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'llegar', label: Text('AL LLEGAR')),
                ButtonSegment(value: 'salir', label: Text('AL SALIR')),
              ],
              selected: {_trigger},
              onSelectionChanged: (s) => setState(() => _trigger = s.first),
            ),
            const SizedBox(height: 8),
            Text('¿Dónde?', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('CUALQUIER LUGAR'),
                selected: _zoneId == null && _kind == null,
                onSelected: (_) => setState(() {
                  _zoneId = null;
                  _kind = null;
                }),
              ),
              for (final k in ContextMode.zoneKinds)
                ChoiceChip(
                  label: Text('ZONAS ${k.labelEs}'),
                  selected: _zoneId == null && _kind == k.code,
                  onSelected: (_) => setState(() {
                    _zoneId = null;
                    _kind = k.code;
                  }),
                ),
              for (final z in widget.zones)
                ChoiceChip(
                  label: Text(z.name),
                  selected: _zoneId == z.id,
                  onSelected: (_) => setState(() {
                    _zoneId = z.id;
                    _kind = null;
                  }),
                ),
            ]),
            const Note('En la pantalla de bloqueo solo se ve «HumanOS»; el texto aparece al desbloquear.'),
            const SizedBox(height: 8),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _BatteryPanel extends ConsumerWidget {
  const _BatteryPanel();

  Future<void> _ask(BuildContext context, WidgetRef ref, String key, String title, int? current) async {
    final v = await askNumber(context, title: title, initial: current?.toDouble(), unit: '%', decimals: 0);
    if (v == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    if (v < 0) {
      await repo.remove(key);
    } else {
      await repo.set(key, v.round().toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final cost = s.batteryZonesCostPct;
    return TerminalPanel(
      label: 'Batería de las zonas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note('Prueba de 24 h: anota en Ajustes del teléfono → Batería cuánto usó HumanOS en 24 h sin '
              'zonas y en 24 h con zonas activas. Si la diferencia supera tu límite, las zonas se apagan.'),
          DataLine('Sin zonas (24 h)', s.batteryWithoutZonesPct == null ? sinDato : '${s.batteryWithoutZonesPct} %'),
          DataLine('Con zonas (24 h)', s.batteryWithZonesPct == null ? sinDato : '${s.batteryWithZonesPct} %'),
          DataLine('Diferencia', cost == null ? sinDato : '$cost %'),
          DataLine('Tu límite', s.batteryLimitPct == null ? 'sin límite' : '${s.batteryLimitPct} %'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: () => _ask(context, ref, SettingKey.batteryWithoutZonesPct, 'Batería en 24 h sin zonas', s.batteryWithoutZonesPct),
              child: const Text('SIN ZONAS'),
            ),
            OutlinedButton(
              onPressed: () => _ask(context, ref, SettingKey.batteryWithZonesPct, 'Batería en 24 h con zonas', s.batteryWithZonesPct),
              child: const Text('CON ZONAS'),
            ),
            OutlinedButton(
              onPressed: () => _ask(context, ref, SettingKey.batteryLimitPct, 'Diferencia máxima aceptada', s.batteryLimitPct),
              child: const Text('LÍMITE'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _RecentPanel extends ConsumerWidget {
  const _RecentPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(contextEventRowsProvider).value ?? const <ContextEventRow>[];
    final zones = ref.watch(zoneRowsProvider).value ?? const <ZoneRow>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return TerminalPanel(
      label: 'Últimas entradas y salidas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows.take(10))
            DataLine(
              '${r.transition == 'entrar' ? 'Entrada' : 'Salida'} · '
                  '${r.zoneId == null ? 'sin zona' : zones.where((z) => z.id == r.zoneId).firstOrNull?.name ?? 'zona borrada'}',
              switch (parseStamp(r.at)) {
                final at? => '${fmtShortDay(at)} ${fmtTime(at)}${r.source == 'manual' ? ' · manual' : ''}',
                null => sinDato,
              },
            ),
        ],
      ),
    );
  }
}
