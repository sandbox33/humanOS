import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../../../services/services.dart';
import '../../inicio/domain/schedule_model.dart';
import '../../inicio/presentation/apps_page.dart' show installedAppsProvider;
import '../domain/screen_model.dart';

String _mins(int? m) => m == null ? 'sin dato' : formatWorkMinutes(m);

/// PANTALLA: minutes per app, category and schedule block, from the phone's
/// own usage events; and the user's rule for hiding categories in blocks.
class PantallaScreen extends ConsumerStatefulWidget {
  const PantallaScreen({super.key});

  @override
  ConsumerState<PantallaScreen> createState() => _PantallaScreenState();
}

class _PantallaScreenState extends ConsumerState<PantallaScreen> {
  bool? _permission;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final source = ref.read(screenTimeProvider);
    final granted = source == null ? false : await source.hasPermission();
    if (granted) {
      try {
        await syncAppUsage(ref);
      } on Object {
        // Shown below as "sin dato".
      }
    }
    if (mounted) setState(() => _permission = granted);
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(screenTimeProvider);
    return HosPage(
      title: 'PANTALLA',
      subtitle: 'Tu tiempo por app, categoría y bloque',
      body: PanelList(children: [
        if (_permission == false)
          TerminalPanel(
            label: 'Permiso',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Note('Para ver el uso por app, Android pide el permiso «Acceso a datos de uso». '
                  'Los datos se quedan en el teléfono, en la base cifrada.'),
              BigButton(
                label: 'Dar acceso a uso',
                icon: Icons.lock_open,
                onPressed: source == null ? null : () async => source.openSettings(),
              ),
              TextButton(onPressed: _refresh, child: const Text('YA LO DI, VOLVER A LEER')),
            ]),
          ),
        const _TodayPanel(),
        const _WeekPanel(),
        const _AppsPanel(),
        const _HidePanel(),
        const Note('Límite de Android: el detalle por sitio web dentro de Chrome que muestra Bienestar digital no '
            'está disponible para otras apps. Chrome cuenta como una app; los sitios se bloquean con el filtro DNS.'),
      ]),
    );
  }
}

class _TodayPanel extends ConsumerWidget {
  const _TodayPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final intervals = ref.watch(todayUsageProvider);
    final classes = ref.watch(effectiveClassesProvider);
    if (intervals == null) {
      return const TerminalPanel(label: 'Hoy', child: Note('Sin datos de uso todavía.'));
    }
    final byApp = minutesByApp(intervals, today);
    final byCategory = minutesByCategory(byApp, classes);
    final plan = ref.watch(dayPlanProvider(0));
    final byBlock = minutesByBlock(intervals: intervals, plan: plan, day: today, classes: classes);
    final rule = ref.watch(hideRuleProvider);
    final hidden = minutesWhileHidden(intervals: intervals, plan: plan, day: today, rule: rule, classes: classes);
    final total = byApp.values.fold(0, (a, b) => a + b);
    return TerminalPanel(
      label: 'Hoy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataLine('Total', _mins(total), emphasis: true),
          for (final c in AppCategory.values)
            if (byCategory[c] case final m?) DataLine(c.labelEs, _mins(m)),
          if (byBlock.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('POR BLOQUE', style: Theme.of(context).textTheme.titleSmall),
            for (final b in plan)
              if (byBlock[b.id] case final m?)
                DataLine(
                  b.title,
                  [for (final e in m.entries) '${e.key.labelEs} ${_mins(e.value)}'].join(' · '),
                ),
          ],
          if (!rule.isEmpty) DataLine('Categorías ocultas usadas en sus bloques', _mins(hidden)),
        ],
      ),
    );
  }
}

class _WeekPanel extends ConsumerWidget {
  const _WeekPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(usageDaysProvider).value ?? const <AppUsageDayRow>[];
    final classes = ref.watch(effectiveClassesProvider);
    final today = ref.watch(todayProvider);
    final totals = <String, int>{};
    final byCategory = <AppCategory, int>{};
    for (final r in rows) {
      totals[r.date] = (totals[r.date] ?? 0) + r.minutes;
      final c = classes[r.package] ?? AppCategory.sinClasificar;
      byCategory[c] = (byCategory[c] ?? 0) + r.minutes;
    }
    final trend = sevenDayTrend(totals, today);
    return TerminalPanel(
      label: 'Últimos 7 días',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in AppCategory.values)
            if (byCategory[c] case final m?) DataLine(c.labelEs, _mins(m)),
          const SizedBox(height: 6),
          Text('TENDENCIA', style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < 7; i++) DataLine(isoDate(addDays(today, i - 6)).substring(5), _mins(trend[i])),
        ],
      ),
    );
  }
}

class _AppsPanel extends ConsumerWidget {
  const _AppsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final intervals = ref.watch(todayUsageProvider) ?? const <UsageInterval>[];
    final byApp = minutesByApp(intervals, today).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final stored = ref.watch(appClassesProvider).value ?? const {};
    final classes = ref.watch(effectiveClassesProvider);
    final labels = {for (final a in ref.watch(installedAppsProvider).value ?? const []) a.package: a.label};
    return TerminalPanel(
      label: 'Apps de hoy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (byApp.isEmpty) const Note('Sin uso registrado hoy.'),
          for (final e in byApp)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(labels[e.key] ?? e.key),
              subtitle: Text(
                '${(classes[e.key] ?? AppCategory.sinClasificar).labelEs}'
                '${stored.containsKey(e.key) ? '' : ' (sugerida)'}',
              ),
              trailing: Text(_mins(e.value)),
              onTap: () => classifyApp(context, ref, e.key, labels[e.key] ?? e.key),
            ),
          const Note('Toca una app para cambiar su categoría.'),
        ],
      ),
    );
  }
}

/// Lets the user choose the category of [package].
Future<void> classifyApp(BuildContext context, WidgetRef ref, String package, String label) async {
  final chosen = await showDialog<AppCategory>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(label.toUpperCase()),
      children: [
        for (final c in AppCategory.values)
          SimpleDialogOption(onPressed: () => Navigator.of(context).pop(c), child: Text(c.labelEs)),
      ],
    ),
  );
  if (chosen != null) await ref.read(screenRepositoryProvider).setClass(package, chosen);
}

class _HidePanel extends ConsumerWidget {
  const _HidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = ref.watch(hideRuleProvider);
    final blocks = [
      for (final r in ref.watch(blockRowsProvider).value ?? const <ScheduleBlockRow>[])
        if (r.status == 'activo') r,
    ];
    final settings = ref.read(settingsRepositoryProvider);
    Future<void> save({Set<int>? blockIds, Set<AppCategory>? categories}) async {
      final ids = blockIds ?? rule.blockIds;
      final cats = categories ?? rule.categories;
      if (ids.isEmpty) {
        await settings.remove(ScreenKey.hideBlocks);
      } else {
        await settings.set(ScreenKey.hideBlocks, ids.join(','));
      }
      if (cats.isEmpty) {
        await settings.remove(ScreenKey.hideCategories);
      } else {
        await settings.set(ScreenKey.hideCategories, cats.map((c) => c.code).join(','));
      }
    }

    return TerminalPanel(
      label: 'Ocultar en bloques',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note('Las apps de estas categorías desaparecen de INICIO solo durante los bloques que marques. '
              'Fuera de ellos se abren directo, sin contador.'),
          Text('CATEGORÍAS', style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final c in AppCategory.values)
              if (c != AppCategory.sinClasificar)
                FilterChip(
                  label: Text(c.labelEs),
                  selected: rule.categories.contains(c),
                  onSelected: (on) => save(categories: on ? {...rule.categories, c} : ({...rule.categories}..remove(c))),
                ),
          ]),
          const SizedBox(height: 6),
          Text('BLOQUES', style: Theme.of(context).textTheme.titleSmall),
          if (blocks.isEmpty) const Note('Crea tus bloques en INICIO → HORARIO.'),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final b in blocks)
              FilterChip(
                label: Text('${b.startClock} ${b.label ?? BlockKind.parse(b.kind).labelEs}'),
                selected: rule.blockIds.contains(b.id),
                onSelected: (on) => save(blockIds: on ? {...rule.blockIds, b.id} : ({...rule.blockIds}..remove(b.id))),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('PAUSA DE 10 S ANTES DE REDES'),
            subtitle: const Text('Opcional. Solo para la categoría Redes; el ocio se abre directo.'),
            value: ref.watch(socialFrictionProvider),
            onChanged: (v) => settings.setBool(ScreenKey.frictionSocial, v),
          ),
        ],
      ),
    );
  }
}
