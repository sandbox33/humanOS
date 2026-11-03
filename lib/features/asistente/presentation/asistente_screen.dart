import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../contexto/domain/context_model.dart';
import '../../estado/domain/targets.dart';
import '../../indice/presentation/catalog_search.dart';
import '../../registro/presentation/add_item_sheet.dart';
import '../../registro/presentation/registro_screen.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;
import '../../trabajo/presentation/work_entry_sheet.dart';
import '../data/model_manager.dart';
import '../domain/assistant_model.dart';
import '../domain/local_assistant.dart';

/// ASISTENTE: one phrase becomes one record of a fixed schema, shown in
/// its form; nothing is saved until the user confirms. It does not chat
/// and gives no advice.
class AsistenteScreen extends ConsumerStatefulWidget {
  const AsistenteScreen({super.key});

  @override
  ConsumerState<AsistenteScreen> createState() => _AsistenteScreenState();
}

class _AsistenteScreenState extends ConsumerState<AsistenteScreen> {
  final _phrase = TextEditingController();
  AssistantAnswer? _answer;
  bool _busy = false;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _interpret() async {
    final text = _phrase.text.trim();
    if (text.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final answer = await ref.read(assistantProvider).interpret(text);
    if (mounted) {
      setState(() {
        _answer = answer;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return HosPage(
      title: 'ASISTENTE',
      subtitle: 'Una frase → un registro que tú confirmas',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Frase',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _phrase,
                decoration: const InputDecoration(labelText: 'Escribe lo que hiciste', hintText: 'trabajé 6 horas, peso 70,4…'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _interpret(),
              ),
              const SizedBox(height: 8),
              BigButton(label: _busy ? 'Interpretando…' : 'Interpretar', icon: Icons.auto_fix_high, onPressed: _busy ? null : _interpret),
              const Note('No conversa ni da consejos: solo convierte la frase en un registro de trabajo, peso, '
                  'comida, estado o termo. Nada se guarda sin tu confirmación.'),
            ],
          ),
        ),
        if (answer != null) _AnswerPanel(answer: answer),
        const _ModelPanel(),
        const _EvaluationPanel(),
      ]),
    );
  }
}

List<(String, String)> describeIntentEs(LogIntent intent) {
  final f = intent.fields;
  String? text(String key) => f[key] as String?;
  num? number(String key) => f[key] as num?;
  return switch (intent.action) {
    LogAction.workEntry => [
        if (text('label') case final label?) ('Trabajo', label),
        if (number('minutes') case final m?) ('Horas', formatWorkMinutes(m.toInt())),
        if (text('start') case final start?) ('Inicio', start),
        if (text('end') case final end?) ('Fin', end),
        if (number('rate_cents') case final r?) ('Tarifa', '${formatCents(r.toInt())}/h'),
        if (number('total_cents') case final t?) ('Total', formatCents(t.toInt())),
      ],
    LogAction.weight => [('Peso', '${formatDecimal(number('kg')!.toDouble(), decimals: 1)} kg')],
    LogAction.foodLog => [
        ('Alimento', text('food') ?? 'sin dato'),
        if (number('grams') case final g?) ('Gramos', '${formatWhole(g.toDouble())} g'),
        if (number('quantity') case final q?) ('Cantidad', formatDecimal(q.toDouble(), decimals: 1)),
      ],
    LogAction.state => [('Estado', '${number('value')} de 5')],
    LogAction.thermos => [
        ('Momento', switch (text('moment')) {
          'antes' => 'antes del trabajo',
          'pausa' => 'en la pausa',
          _ => 'sin dato',
        }),
      ],
  };
}

/// Opens the form of [intent], pre-filled. Writes only after the user
/// confirms in that form or dialog.
Future<void> openIntentForm(BuildContext context, WidgetRef ref, LogIntent intent) async {
  final today = ref.read(todayProvider);
  final now = ref.read(clockProvider)();
  final f = intent.fields;
  switch (intent.action) {
    case LogAction.workEntry:
      await WorkEntrySheet.show(context, prefill: intent);
    case LogAction.weight:
      final kg = (f['kg']! as num).toDouble();
      final ok = await confirm(context,
          title: 'Guardar peso', message: '${formatDecimal(kg, decimals: 1)} kg para hoy.', accept: 'GUARDAR');
      if (ok) await ref.read(bodyRepositoryProvider).setWeight(isoDate(today), kg);
    case LogAction.state:
      final value = f['value']! as int;
      final ok = await confirm(context, title: 'Guardar estado', message: '$value de 5.', accept: 'GUARDAR');
      if (ok) await ref.read(contextRepositoryProvider).addCheckin(now, value);
    case LogAction.thermos:
      var moment = f['moment'] as String?;
      moment ??= await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('¿CUÁNDO LLENASTE EL TERMO?'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.of(dialogContext).pop('antes'), child: const Text('ANTES DEL TRABAJO')),
            SimpleDialogOption(onPressed: () => Navigator.of(dialogContext).pop('pausa'), child: const Text('EN LA PAUSA')),
          ],
        ),
      );
      if (moment == null || !context.mounted) return;
      final ok = await confirm(context,
          title: 'Guardar termo', message: moment == 'antes' ? 'Antes del trabajo, hoy.' : 'En la pausa, hoy.', accept: 'GUARDAR');
      if (!ok) return;
      await ref.read(dailyLogRepositoryProvider).update(
            isoDate(today),
            moment == 'antes'
                ? const DailyLogsCompanion(thermoPre: Value(true))
                : const DailyLogsCompanion(thermoBreak: Value(true)),
          );
    case LogAction.foodLog:
      final choice = await pickFood(context, title: 'Añadir', pantryFirst: true, initialQuery: f['food'] as String?);
      if (choice == null || !context.mounted) return;
      await showAddItemSheet(
        context,
        choice: choice,
        date: isoDate(today),
        block: blockNear(slotsFor(ref, today), now),
        initialGrams: (f['grams'] as num?)?.toDouble(),
      );
  }
}

class _AnswerPanel extends ConsumerWidget {
  const _AnswerPanel({required this.answer});

  final AssistantAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intent = answer.best;
    if (intent == null) {
      return TerminalPanel(
        label: 'Resultado',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Note('No es un registro de trabajo, peso, comida, estado ni termo. Abre el formulario que necesites:'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => WorkEntrySheet.show(context), child: const Text('TRABAJO')),
              OutlinedButton(
                onPressed: () => openIntentForm(context, ref, const LogIntent(LogAction.foodLog, {'food': ''})),
                child: const Text('COMIDA'),
              ),
            ]),
          ],
        ),
      );
    }
    return TerminalPanel(
      label: 'Resultado · ${intent.action.labelEs}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in describeIntentEs(intent)) DataLine(label, value),
          for (final p in answer.problemsEs) Note(p),
          Text(
            'Entendido por ${answer.source == 'modelo' ? 'el modelo del teléfono' : 'las reglas'} en '
            '${answer.elapsed.inMilliseconds} ms.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          BigButton(label: 'Revisar y guardar', icon: Icons.fact_check_outlined, onPressed: () => openIntentForm(context, ref, intent)),
        ],
      ),
    );
  }
}

class _ModelPanel extends ConsumerStatefulWidget {
  const _ModelPanel();

  @override
  ConsumerState<_ModelPanel> createState() => _ModelPanelState();
}

class _ModelPanelState extends ConsumerState<_ModelPanel> {
  ModelStatus? _status;
  bool? _hasToken;

  @override
  void initState() {
    super.initState();
    ref.read(tokenStoreProvider).read().then((t) {
      if (mounted) setState(() => _hasToken = t != null && t.isNotEmpty);
    });
  }

  Future<String?> _token() async {
    final token = await ref.read(tokenStoreProvider).read();
    if ((token == null || token.isEmpty) && mounted) {
      toast(context, 'Primero guarda tu token de Hugging Face (con la licencia de Gemma aceptada).');
      return null;
    }
    return token;
  }

  void _progress(ModelStatus s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _download(ModelSpec spec) async {
    final token = await _token();
    if (token == null) return;
    if (!await ref.read(deviceContextProvider).unmeteredNetwork()) {
      if (mounted) toast(context, 'Conéctate a Wi-Fi: el modelo pesa ${spec.sizeEs}.');
      return;
    }
    final result = await ref.read(modelManagerProvider).download(spec, token: token, onProgress: _progress);
    _progress(result);
    ref.invalidate(modelInstalledProvider);
  }

  Future<void> _import(ModelSpec spec) async {
    final token = await _token();
    if (token == null) return;
    final picked = await openFile();
    if (picked == null) return;
    final result =
        await ref.read(modelManagerProvider).importFile(spec, File(picked.path), token: token, onProgress: _progress);
    _progress(result);
    ref.invalidate(modelInstalledProvider);
  }

  Future<void> _saveToken() async {
    final token = await askText(context, title: 'Token de Hugging Face', obscure: true, hint: 'hf_…');
    if (token == null) return;
    await ref.read(tokenStoreProvider).write(token);
    if (mounted) setState(() => _hasToken = token.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final spec = ref.watch(selectedModelProvider);
    final installed = ref.watch(modelInstalledProvider).value ?? false;
    final enabled = ref.watch(modelEnabledProvider);
    final bridge = ref.watch(llmBridgeProvider);
    final settings = ref.read(settingsRepositoryProvider);
    final status = _status;
    final theme = Theme.of(context);
    return TerminalPanel(
      label: 'Modelo en el teléfono (opcional)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note('Solo entra cuando las reglas no entienden una frase. No va dentro del APK: se descarga una '
              'vez por Wi-Fi desde la fuente oficial y se usa solo si su SHA-256 coincide.'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in modelSpecs)
              ChoiceChip(
                label: Text('${s.labelEs} · ${s.sizeEs}'),
                selected: s.id == spec.id,
                onSelected: (_) => settings.set(AssistantKey.model, s.id),
              ),
          ]),
          Text(spec.noteEs, style: theme.textTheme.bodySmall),
          DataLine('Estado', installed ? 'instalado' : 'no instalado'),
          DataLine('Token', _hasToken == true ? 'guardado en el Keystore' : 'falta'),
          if (status != null)
            Note(switch (status.state) {
              ModelState.checking => 'Comprobando el archivo oficial…',
              ModelState.downloading =>
                'Descargando: ${(status.receivedBytes / spec.sizeBytes * 100).clamp(0, 100).toStringAsFixed(0)} %',
              ModelState.verifying => 'Verificando el SHA-256…',
              ModelState.ready => 'Listo: el archivo coincide con el oficial.',
              ModelState.failed => status.messageEs ?? 'No se pudo.',
              ModelState.missing => '',
            }),
          if (bridge == null) const Note('Este dispositivo no puede ejecutar el modelo.'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _saveToken, child: const Text('TOKEN')),
            OutlinedButton(onPressed: () => _download(spec), child: const Text('DESCARGAR (WI-FI)')),
            OutlinedButton(onPressed: () => _import(spec), child: const Text('IMPORTAR ARCHIVO')),
            if (installed)
              OutlinedButton(
                onPressed: () async {
                  await ref.read(modelManagerProvider).remove(spec);
                  ref.invalidate(modelInstalledProvider);
                },
                child: const Text('BORRAR'),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('USAR EL MODELO'),
            subtitle: const Text('Por defecto se activa solo si la evaluación de abajo alcanza la exactitud mínima.'),
            value: enabled,
            onChanged: installed && bridge != null ? (v) => settings.setBool(AssistantKey.enabled, v) : null,
          ),
          Note('Gemma se usa bajo los Términos de uso de Gemma de Google. Acepta la licencia con tu cuenta en '
              '${spec.pageUrl} y crea un token de lectura antes de descargar.'),
        ],
      ),
    );
  }
}

class _EvaluationPanel extends ConsumerStatefulWidget {
  const _EvaluationPanel();

  @override
  ConsumerState<_EvaluationPanel> createState() => _EvaluationPanelState();
}

class _EvaluationPanelState extends ConsumerState<_EvaluationPanel> {
  bool _running = false;
  int _failures = 0;

  Future<void> _run() async {
    setState(() => _running = true);
    final cases = await loadEvalSet();
    final withModel = ref.read(llmBridgeProvider) != null && (ref.read(modelInstalledProvider).value ?? false);
    final spec = ref.read(selectedModelProvider);
    final assistant = ChainedAssistant(
      rules: const RulesAssistant(),
      model: withModel
          ? ModelAssistant(modelCompleter(
              bridge: ref.read(llmBridgeProvider),
              manager: ref.read(modelManagerProvider),
              spec: spec,
              assumptions: ref.read(currentAssumptionsProvider),
            ))
          : null,
    );
    final report = await evaluateAssistant(assistant, cases);
    final record = EvaluationRecord(
      modelId: withModel ? spec.id : null,
      withModel: withModel,
      total: report.total,
      correct: report.correct,
      medianMs: report.medianMs,
      p95Ms: report.p95Ms,
      at: stampOf(ref.read(clockProvider)()),
    );
    await ref.read(settingsRepositoryProvider).set(AssistantKey.evaluation, jsonEncode(record.toJson()));
    if (mounted) {
      setState(() {
        _running = false;
        _failures = report.failures.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final eval = ref.watch(evaluationProvider);
    final threshold = ref.watch(currentAssumptionsProvider)[A.assistantMinAccuracy];
    return TerminalPanel(
      label: 'Evaluación en este teléfono',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eval == null)
            const Note('Aún sin evaluar.')
          else ...[
            DataLine('Exactitud', '${formatDecimal(eval.accuracy * 100, decimals: 1)} % (${eval.correct} de ${eval.total})'),
            DataLine('Demora', 'mediana ${eval.medianMs} ms · p95 ${eval.p95Ms} ms'),
            DataLine('Con', eval.withModel ? (specById(eval.modelId)?.labelEs ?? 'modelo') : 'solo reglas'),
            if (_failures > 0) DataLine('Fallos', '$_failures'),
          ],
          Note('El modelo se activa por defecto solo con al menos ${formatWhole(threshold * 100)} % '
              '(SUPUESTOS → ASISTENTE).'),
          BigButton(
            label: _running ? 'Evaluando…' : 'Evaluar (frases de prueba)',
            icon: Icons.rule,
            outlined: true,
            onPressed: _running ? null : _run,
          ),
        ],
      ),
    );
  }
}
