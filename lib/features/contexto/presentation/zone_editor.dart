import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../trabajo/data/work_repository.dart' show TemplateStatus, stampOf;
import '../../trabajo/domain/work_model.dart';
import '../domain/context_model.dart';

/// Create or edit a zone: neutral name, context kind, a point (current
/// location or typed/pasted coordinates) and a radius of at least the
/// minimum.
class ZoneEditor extends ConsumerStatefulWidget {
  const ZoneEditor({super.key, this.existing});

  final ZoneRow? existing;

  static Future<void> show(BuildContext context, {ZoneRow? existing}) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ZoneEditor(existing: existing),
      );

  @override
  ConsumerState<ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends ConsumerState<ZoneEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _kindLabel = TextEditingController(text: widget.existing?.kindLabel ?? '');
  late final TextEditingController _coordinates = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.latitude}, ${widget.existing!.longitude}',
  );
  late ContextMode _kind = ContextMode.parse(widget.existing?.kind ?? ContextMode.chamba.code);
  late double _radius = (widget.existing?.radiusM ?? ref.read(contextParamsProvider).defaultRadiusM).toDouble();
  late int? _templateId = widget.existing?.templateId;
  String? _accuracy;
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    _kindLabel.dispose();
    _coordinates.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final device = ref.read(deviceContextProvider);
    setState(() => _locating = true);
    try {
      var access = await device.access();
      if (!access.fine) access = await device.requestForeground();
      if (!access.fine) {
        if (mounted) toast(context, 'Sin ubicación precisa: escribe o pega las coordenadas.');
        return;
      }
      final point = await device.currentLocation();
      if (!mounted) return;
      if (point == null) {
        toast(context, 'No se pudo leer la ubicación. Revisa que esté encendida.');
        return;
      }
      setState(() {
        _coordinates.text = '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
        _accuracy = point.accuracyM == null ? null : 'Precisión de la lectura: ±${point.accuracyM!.round()} m';
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final params = ref.read(contextParamsProvider);
    final existing = widget.existing;
    final point = parseCoordinates(_coordinates.text);
    final rows = ref.read(zoneRowsProvider).value ?? const <ZoneRow>[];
    final active = existing == null || TemplateStatus.parse(existing.status) == TemplateStatus.activo;
    final others = rows
        .where((r) => r.id != existing?.id && TemplateStatus.parse(r.status) == TemplateStatus.activo)
        .length;
    final issues = validateZone(
      name: _name.text,
      kind: _kind,
      latitude: point?.latitude,
      longitude: point?.longitude,
      radiusM: _radius.round(),
      active: active,
      activeOthers: others,
      params: params,
    );
    if (issues.isNotEmpty) {
      toast(context, issues.map((i) => i.messageEs).join(' '));
      return;
    }
    final companion = ZonesCompanion(
      name: Value(_name.text.trim()),
      kind: Value(_kind.code),
      kindLabel: Value(_kind == ContextMode.otro && _kindLabel.text.trim().isNotEmpty ? _kindLabel.text.trim() : null),
      latitude: Value(point!.latitude),
      longitude: Value(point.longitude),
      radiusM: Value(_radius.round()),
      templateId: Value(_templateId),
    );
    final repo = ref.read(contextRepositoryProvider);
    if (existing == null) {
      await repo.saveZone(companion.copyWith(createdAt: Value(stampOf(ref.read(clockProvider)()))));
    } else {
      await repo.saveZone(companion, id: existing.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = ref.watch(contextParamsProvider);
    final templates = ref.watch(activeTemplatesProvider);
    final point = parseCoordinates(_coordinates.text);
    final overlaps = point == null
        ? const <ContextZone>[]
        : overlappingZones(
            latitude: point.latitude,
            longitude: point.longitude,
            radiusM: _radius.round(),
            zones: ref.watch(zonesProvider).where((z) => z.active).toList(),
            exceptId: widget.existing?.id,
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'NUEVA ZONA' : 'EDITAR ZONA', style: theme.textTheme.titleLarge),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre neutro', hintText: 'Zona A'),
            ),
            const SizedBox(height: 8),
            Text('Contexto', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in ContextMode.zoneKinds)
                ChoiceChip(label: Text(k.labelEs), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
            ]),
            if (_kind == ContextMode.otro)
              TextField(controller: _kindLabel, decoration: const InputDecoration(labelText: 'Nombre de tu contexto')),
            const SizedBox(height: 12),
            Text('Punto', style: theme.textTheme.labelLarge),
            OutlinedButton.icon(
              icon: const Icon(Icons.my_location),
              label: Text(_locating ? 'LEYENDO…' : 'USAR MI UBICACIÓN ACTUAL'),
              onPressed: _locating ? null : _useCurrentLocation,
            ),
            TextField(
              controller: _coordinates,
              decoration: const InputDecoration(
                labelText: 'O escribe o pega «latitud, longitud»',
                helperText: 'También sirve un enlace de mapa con coordenadas.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_accuracy != null) Text(_accuracy!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('Radio (mínimo ${params.minRadiusM} m)', style: theme.textTheme.labelLarge),
            ValueStepper(
              value: _radius,
              unit: 'm',
              min: params.minRadiusM.toDouble(),
              max: 2000,
              steps: const [50, 250],
              onChanged: (v) => setState(() => _radius = v),
            ),
            for (final z in overlaps) Note('Se superpone con «${z.name}»: en la zona común cuenta la última entrada.'),
            if (templates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Plantilla de trabajo sugerida (opcional)', style: theme.textTheme.labelLarge),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ChoiceChip(
                  label: const Text('NINGUNA'),
                  selected: _templateId == null,
                  onSelected: (_) => setState(() => _templateId = null),
                ),
                for (final t in templates)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _templateId == t.id,
                    onSelected: (_) => setState(() => _templateId = t.id),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            BigButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
