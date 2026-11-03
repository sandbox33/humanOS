import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/format.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../inicio/presentation/horario_page.dart';
import '../domain/meal_day.dart';
import '../domain/pantry_model.dart';

/// COMIDAS: today's plan by meal from the pantry, what to cook once, and
/// how each food keeps and travels (the user corrects the suggestion).
class MealsTab extends ConsumerWidget {
  const MealsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mealDayPlanProvider);
    final slots = ref.watch(scheduleMealSlotsProvider(0));
    final stock = {for (final s in ref.watch(stockViewProvider)) s.key: s};
    final cook = ref.watch(cookTodayProvider);
    final fridge = ref.watch(hasFridgeProvider);
    return PanelList(children: [
      Note(fridge
          ? 'Con refrigeradora: lo fresco de la despensa se usa cualquier día.'
          : 'Sin refrigeradora (o sin respuesta): la carne, el pescado y los lácteos frescos se usan solo el día de '
              'la compra. Cámbialo en AJUSTES → METAS DE COMIDA.'),
      if (slots.isEmpty) ...[
        const Note('Tus comidas salen de tu HORARIO: crea bloques de desayuno, media mañana, almuerzo, media tarde '
            'o cena.'),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HorarioPage())),
          child: const Text('ABRIR HORARIO'),
        ),
      ] else if (plans.isEmpty)
        const Note('Registra tu peso para calcular lo que toca en cada comida.'),
      for (final p in plans)
        TerminalPanel(
          label: '${p.slot.clock} · ${p.slot.contextEs}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (p.noteEs != null)
                Note(p.noteEs!)
              else ...[
                DataLine('Falta', '${fmtNum(p.kcal, unit: 'kcal')} · ${fmtNum(p.proteinG, unit: 'g')} de proteína'),
                for (final e in p.grams.entries) DataLine(stock[e.key]?.food.name ?? e.key, fmtNum(e.value, unit: 'g')),
                if (p.plan != null && p.plan!.status != DietStatus.optimal) Note(p.plan!.messageEs),
                if (p.varietyNoteEs != null) Note(p.varietyNoteEs!),
                if (p.plan != null && p.plan!.excludedEs.isNotEmpty)
                  Note('No usados: ${p.plan!.excludedEs.join('; ')}. Pon el precio al registrar la compra.'),
                if (p.slot.block == MealBlock.midMorning || p.slot.block == MealBlock.afternoon)
                  const Note('Vianda: solo alimentos que marcaste (o que se sugieren) para llevar y que no se cocinan.'),
              ],
            ],
          ),
        ),
      if (cook.isNotEmpty)
        TerminalPanel(
          label: 'Cocción en dos tiempos',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Note('Cocina una sola vez temprano (en tu bloque COCINAR o a la hora de tu primera comida) lo del '
                'almuerzo y la cena; aparta la porción del almuerzo y recaliéntala al mediodía hasta que humee. '
                'Un solo aviso te lo recuerda.'),
            for (final e in cook.entries) DataLine(stock[e.key]?.food.name ?? e.key, fmtNum(e.value, unit: 'g')),
          ]),
        ),
      const _HandlingPanel(),
    ]);
  }
}

/// How each pantry food keeps and travels: the suggestion from its food
/// group until the user says otherwise.
class _HandlingPanel extends ConsumerWidget {
  const _HandlingPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockViewProvider);
    final handling = ref.watch(stockHandlingProvider);
    final flags = ref.watch(handlingFlagsProvider).value ?? const {};
    final db = ref.read(userDbProvider);
    final seen = <String>{};
    return TerminalPanel(
      label: 'Cómo se guarda cada alimento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note('Sugerido según el grupo del alimento. Toca para corregir; tu respuesta manda.'),
          for (final s in stock)
            if (seen.add(foodKeyOf(foodId: s.row.foodId, barcode: s.row.barcode)))
              Builder(builder: (context) {
                final key = foodKeyOf(foodId: s.row.foodId, barcode: s.row.barcode);
                final h = handling[s.key] ?? const FoodHandling();
                final own = flags[key];
                Future<void> save({bool? cold, bool? portable, bool? cooking}) => setHandling(
                      db,
                      key,
                      needsCold: cold ?? own?.needsCold,
                      portable: portable ?? own?.portable,
                      needsCooking: cooking ?? own?.needsCooking,
                      now: ref.read(clockProvider)(),
                    );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(s.food.name, style: Theme.of(context).textTheme.titleSmall),
                    Wrap(spacing: 6, children: [
                      FilterChip(
                        label: const Text('NECESITA FRÍO'),
                        selected: h.needsCold ?? false,
                        onSelected: (v) => save(cold: v),
                      ),
                      FilterChip(
                        label: const Text('PARA VIANDA'),
                        selected: h.portable ?? false,
                        onSelected: (v) => save(portable: v),
                      ),
                      FilterChip(
                        label: const Text('SE COCINA'),
                        selected: h.needsCooking ?? false,
                        onSelected: (v) => save(cooking: v),
                      ),
                    ]),
                  ]),
                );
              }),
          if (stock.isEmpty) const Note('La despensa está vacía.'),
        ],
      ),
    );
  }
}

/// LISTA: what to buy to keep eating at last week's pace, with its cost.
class ShoppingTab extends ConsumerWidget {
  const ShoppingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(shoppingListProvider);
    final days = ref.watch(currentAssumptionsProvider).integer(A.shoppingCoverDays);
    return PanelList(children: [
      Note('Lo que comiste por día en la última semana, para $days días, menos lo que hay en la despensa. '
          'Los días se cambian en SUPUESTOS → DESPENSA Y PLAN.'),
      list.when(
        loading: () => const Note('Calculando…'),
        error: (_, _) => const Note('No se pudo calcular la lista.'),
        data: (l) => TerminalPanel(
          label: 'Lista de compra',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (l.lines.isEmpty) const Note('Nada que comprar con lo registrado esta semana.'),
            for (final line in l.lines)
              DataLine(
                line.name,
                '${fmtNum(line.grams, unit: 'g')} · ${line.costCents == null ? 'sin precio' : formatCents(line.costCents!)}',
              ),
            if (l.lines.isNotEmpty) ...[
              const Divider(),
              DataLine('Costo conocido', formatCents(l.knownCents), emphasis: true),
              if (l.unpriced > 0) Note('${l.unpriced} producto(s) sin precio: el costo real será mayor.'),
            ],
          ]),
        ),
      ),
    ]);
  }
}
