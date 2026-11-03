import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/gram_stepper.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../domain/token_model.dart';

/// FICHAS DE OCIO (B7): optional and off by default. Off, leisure has no
/// limit and nothing is counted.
class FichasScreen extends ConsumerStatefulWidget {
  const FichasScreen({super.key});

  @override
  ConsumerState<FichasScreen> createState() => _FichasScreenState();
}

class _FichasScreenState extends ConsumerState<FichasScreen> {
  @override
  void initState() {
    super.initState();
    // A matured change applies when the screen opens, too.
    WidgetsBinding.instance.addPostFrameCallback((_) => syncTokens(ref));
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(tokensOnProvider);
    final sw = ref.watch(tokenSwitchProvider);
    final wait = ref.watch(currentAssumptionsProvider).integer(A.tokensToggleWaitH);
    final matures = sw.maturesAt(wait);
    return HosPage(
      title: 'FICHAS DE OCIO',
      subtitle: 'Opcional · apagado por defecto',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Estado',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(on ? 'ENCENDIDAS' : 'APAGADAS', style: Theme.of(context).textTheme.headlineSmall),
            Text(on
                ? 'Tus hábitos dan fichas y el ocio que elijas las usa. Sin fichas, abrir ocio pregunta; nunca bloquea.'
                : 'El ocio no tiene límite ni contador.'),
            if (sw.pendingTarget != null && matures != null)
              Note('Cambio pedido: ${sw.pendingTarget! ? 'encender' : 'apagar'} desde '
                  '${isoDate(matures)} ${formatClock(matures.hour * 60 + matures.minute)} ($wait h de espera).'),
            const SizedBox(height: 8),
            if (sw.pendingTarget == null)
              OutlinedButton(
                onPressed: () => askTokenSwitch(ref, !sw.enabled),
                child: Text(sw.enabled ? 'PEDIR APAGAR' : 'PEDIR ENCENDER'),
              )
            else
              OutlinedButton(onPressed: () => askTokenSwitch(ref, sw.enabled), child: const Text('CANCELAR EL CAMBIO')),
            const Note('Apagar no borra el historial.'),
          ]),
        ),
        const _BalancePanel(),
        const _EarnPanel(),
        const _CostPanel(),
      ]),
    );
  }
}

class _BalancePanel extends ConsumerWidget {
  const _BalancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(tokenDaysProvider).value ?? const <TokenDayRow>[];
    final byDate = <String, (int, int)>{};
    for (final r in rows) {
      final v = byDate[r.date] ?? (0, 0);
      byDate[r.date] = (v.$1 + r.earned, v.$2 + r.spent);
    }
    return TerminalPanel(
      label: 'Saldo e historial',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DataLine('Saldo', '${ref.watch(tokenBalanceProvider)} fichas', emphasis: true),
        if (byDate.isEmpty) const Note('Sin historial.'),
        for (final e in byDate.entries.take(14)) DataLine(e.key, '+${e.value.$1} · −${e.value.$2}'),
      ]),
    );
  }
}

class _EarnPanel extends ConsumerWidget {
  const _EarnPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(userDbProvider);
    final rules = {for (final r in ref.watch(earnRulesProvider).value ?? const <TokenEarnRuleRow>[]) r.source: r.tokens};
    final habits = ref.watch(_habitsProvider).value ?? const <HabitRow>[];
    final sources = <String, String>{
      ...tokenEventSources,
      for (final h in habits)
        if (h.active) 'habit:${h.id}': 'Hábito: ${h.alias}',
    };
    Future<void> edit(String source, String label) async {
      final v = await askNumber(context, title: 'Fichas por «$label»', initial: rules[source]?.toDouble(), decimals: 0);
      if (v == null) return;
      if (v <= 0) {
        await (db.delete(db.tokenEarnRules)..where((t) => t.source.equals(source))).go();
      } else {
        await db.into(db.tokenEarnRules).insertOnConflictUpdate(
              TokenEarnRulesCompanion.insert(source: source, tokens: v.round()),
            );
      }
    }

    return TerminalPanel(
      label: 'Qué da fichas',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Note('Elige qué te da fichas y cuántas (0 lo quita). Un bloque de proyecto completado: créalo como '
            'hábito en HÁBITOS y márcalo.'),
        for (final e in sources.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value),
            trailing: Text(rules[e.key] == null ? 'no' : '+${rules[e.key]}'),
            onTap: () => edit(e.key, e.value),
          ),
      ]),
    );
  }
}

final _habitsProvider = StreamProvider<List<HabitRow>>((ref) {
  final db = ref.watch(userDbProvider);
  return db.select(db.habits).watch();
});

class _CostPanel extends ConsumerWidget {
  const _CostPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(userDbProvider);
    final rules = {
      for (final r in ref.watch(costRulesProvider).value ?? const <TokenCostRuleRow>[]) r.category: r,
    };
    Future<void> edit(AppCategory c) async {
      final tokens = await askNumber(context, title: 'Fichas que cuesta «${c.labelEs}»', initial: rules[c.code]?.tokens.toDouble(), decimals: 0);
      if (tokens == null || !context.mounted) return;
      if (tokens <= 0) {
        await (db.delete(db.tokenCostRules)..where((t) => t.category.equals(c.code))).go();
        return;
      }
      final minutes = await askNumber(context, title: '¿Cada cuántos minutos?', initial: rules[c.code]?.perMinutes.toDouble(), unit: 'min', decimals: 0);
      if (minutes == null || minutes <= 0) return;
      await db.into(db.tokenCostRules).insertOnConflictUpdate(
            TokenCostRulesCompanion.insert(category: c.code, tokens: tokens.round(), perMinutes: minutes.round()),
          );
    }

    return TerminalPanel(
      label: 'Qué cuesta fichas',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Note('Por categoría de apps (PANTALLA). Sin regla, esa categoría no cuesta nada.'),
        for (final c in AppCategory.values)
          if (c != AppCategory.sinClasificar)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.labelEs),
              trailing: Text(rules[c.code] == null
                  ? 'gratis'
                  : '${rules[c.code]!.tokens} cada ${rules[c.code]!.perMinutes} min'),
              onTap: () => edit(c),
            ),
      ]),
    );
  }
}

/// Before opening an app of a priced category with no tokens left: a
/// question, never a block.
Future<bool> confirmWithoutTokens(BuildContext context, String label) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('SIN FICHAS'),
      content: Text('No te quedan fichas para «$label». ¿Abrir igual? (el saldo queda en negativo)'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('NO ABRIR')),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ABRIR IGUAL')),
      ],
    ),
  );
  return result ?? false;
}
