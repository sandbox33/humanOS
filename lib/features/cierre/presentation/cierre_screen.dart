import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../domain/close_model.dart';

/// CIERRE DEL DÍA (B6): three short parts, under half a minute. No score
/// and no reproach; everything stays on the phone, encrypted.
class CierreScreen extends ConsumerStatefulWidget {
  const CierreScreen({super.key});

  @override
  ConsumerState<CierreScreen> createState() => _CierreScreenState();
}

class _CierreScreenState extends ConsumerState<CierreScreen> {
  int? _mood;
  int? _energy;
  final _minutes = <int, int>{};
  bool? _honest;
  final _note = TextEditingController();
  bool _loaded = false;
  bool _saved = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Today's close, when already saved, fills the form for a change.
  void _load() {
    if (_loaded) return;
    final rows = ref.read(closeRowsProvider).value;
    final interactions = ref.read(closeInteractionRowsProvider).value;
    if (rows == null || interactions == null) return;
    _loaded = true;
    final today = isoDate(ref.read(todayProvider));
    final row = rows.where((r) => r.date == today).firstOrNull;
    if (row == null) return;
    _mood = row.mood;
    _energy = row.energy;
    _honest = row.honestyYes;
    _note.text = row.honestyNote ?? '';
    for (final i in interactions) {
      if (i.date == today) _minutes[i.categoryId] = i.minutes;
    }
  }

  Future<void> _save() async {
    if (_mood == null || _energy == null) {
      toast(context, 'Marca tu ánimo y tu energía.');
      return;
    }
    await ref.read(closeRepositoryProvider).save(
          date: isoDate(ref.read(todayProvider)),
          mood: _mood!,
          energy: _energy!,
          minutes: _minutes,
          honestyYes: _honest,
          honestyNote: _honest == true ? _note.text : null,
        );
    if (!mounted) return;
    setState(() => _saved = true);
    toast(context, 'Día cerrado.');
  }

  Widget _scale(String label, int? value, ValueChanged<int> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          SegmentedButton<int>(
            segments: [for (var v = 1; v <= 5; v++) ButtonSegment(value: v, label: Text('$v'))],
            selected: value == null ? const <int>{} : {value},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(closeRowsProvider);
    ref.watch(closeInteractionRowsProvider);
    _load();
    final settings = ref.watch(settingsMapProvider).value ?? const {};
    final question = settings[CloseKey.question];
    final phrase = settings[CloseKey.phrase];
    final categories = [
      for (final c in ref.watch(interactionCategoriesProvider).value ?? const <InteractionCategoryRow>[])
        if (c.status == 'activo') c,
    ];
    final reference = ref.watch(communicationMinutesTodayProvider);
    final repo = ref.read(settingsRepositoryProvider);
    return HosPage(
      title: 'CIERRE DEL DÍA',
      subtitle: 'Tres partes, menos de medio minuto',
      body: PanelList(children: [
        TerminalPanel(
          label: '1 · Ánimo y energía',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _scale('ÁNIMO (1 BAJO · 5 ALTO)', _mood, (v) => setState(() => _mood = v)),
            const SizedBox(height: 8),
            _scale('ENERGÍA (1 BAJA · 5 ALTA)', _energy, (v) => setState(() => _energy = v)),
          ]),
        ),
        TerminalPanel(
          label: '2 · Tiempo con personas',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (reference != null)
              Note('Referencia: $reference min hoy en apps que clasificaste como comunicación '
                  '(las llamadas con la pantalla apagada no cuentan).'),
            if (categories.isEmpty)
              const Note('Crea tus categorías (por ejemplo: trabajo, familia, amistades).'),
            for (final c in categories)
              Row(children: [
                Expanded(child: Text(c.label)),
                IconButton(
                  tooltip: 'Menos 15 min con ${c.label}',
                  icon: const Icon(Icons.remove),
                  onPressed: () => setState(() {
                    final v = (_minutes[c.id] ?? 0) - 15;
                    _minutes[c.id] = v < 0 ? 0 : v;
                  }),
                ),
                SizedBox(width: 72, child: Text('${_minutes[c.id] ?? 0} min', textAlign: TextAlign.center)),
                IconButton(
                  tooltip: 'Más 15 min con ${c.label}',
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _minutes[c.id] = (_minutes[c.id] ?? 0) + 15),
                ),
              ]),
            TextButton(
              onPressed: () async {
                final label = await askText(context, title: 'Nueva categoría', hint: 'Trabajo, familia…');
                if (label != null && label.trim().isNotEmpty) {
                  await ref.read(closeRepositoryProvider).addCategory(label);
                }
              },
              child: const Text('NUEVA CATEGORÍA'),
            ),
          ]),
        ),
        TerminalPanel(
          label: '3 · Tu pregunta',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (question == null)
              const Note('Escribe la pregunta que quieres hacerte cada noche. Respondes sí o no, sin puntaje.')
            else ...[
              Text(question, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: ChoiceChip(label: const Text('SÍ'), selected: _honest == true, onSelected: (_) => setState(() => _honest = true)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(label: const Text('NO'), selected: _honest == false, onSelected: (_) => setState(() => _honest = false)),
                ),
              ]),
              if (_honest == true) ...[
                TextField(controller: _note, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
                if (phrase != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Para la próxima vez: «$phrase»', style: Theme.of(context).textTheme.bodyLarge),
                  ),
              ],
            ],
            Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () async {
                  final text = await askText(context, title: 'Tu pregunta', initial: question);
                  if (text == null) return;
                  if (text.trim().isEmpty) {
                    await repo.remove(CloseKey.question);
                  } else {
                    await repo.set(CloseKey.question, text.trim());
                  }
                },
                child: Text(question == null ? 'ESCRIBIR PREGUNTA' : 'CAMBIAR PREGUNTA'),
              ),
              TextButton(
                onPressed: () async {
                  final text = await askText(context, title: 'Tu frase para la próxima vez', initial: phrase);
                  if (text == null) return;
                  if (text.trim().isEmpty) {
                    await repo.remove(CloseKey.phrase);
                  } else {
                    await repo.set(CloseKey.phrase, text.trim());
                  }
                },
                child: Text(phrase == null ? 'ESCRIBIR FRASE' : 'CAMBIAR FRASE'),
              ),
            ]),
          ]),
        ),
        BigButton(label: _saved ? 'Guardado · cambiar' : 'Cerrar el día', icon: Icons.nightlight_outlined, onPressed: _save),
        const _TrendsPanel(),
        const Note('Todo queda en el teléfono, cifrado. No sale en copias sin tu contraseña ni en registros.'),
      ]),
    );
  }
}

class _TrendsPanel extends ConsumerWidget {
  const _TrendsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(closeTrendsProvider);
    final minDays = ref.watch(currentAssumptionsProvider).integer(A.closeTrendMinDays);
    final closed = ref.watch(closesProvider).length;
    return TerminalPanel(
      label: 'Tendencias',
      child: t == null
          ? Note('Aparecen con $minDays días cerrados. Llevas $closed.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DataLine('Días que se usan', '${t.days}', emphasis: true),
              DataLine('Ánimo medio', fmtNum(t.moodMean, decimals: 1)),
              DataLine('Energía media', fmtNum(t.energyMean, decimals: 1)),
              DataLine('Tiempo con personas por día', fmtNum(t.interactionMeanMinutes, unit: 'min')),
              DataLine('Ánimo y tiempo con personas', correlationEs(t.moodVsInteraction)),
              DataLine('Energía y tiempo con personas', correlationEs(t.energyVsInteraction)),
              DataLine('Días con «sí» a tu pregunta', '${t.honestyYesDays} de ${t.answeredDays} respondidos'),
              const Note('Correlación no es causa: dos cosas pueden ir juntas sin que una provoque la otra.'),
            ]),
    );
  }
}
