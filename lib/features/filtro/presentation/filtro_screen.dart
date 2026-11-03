import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';
import '../../../data/user_db.dart';
import '../domain/dns_model.dart';

/// FILTRO: the user's blocked and allowed domains, the guide to put them in
/// a private DNS profile, and the check of whether the filter works.
/// Android does not let an app set the private DNS itself.
class FiltroScreen extends ConsumerStatefulWidget {
  const FiltroScreen({super.key});

  @override
  ConsumerState<FiltroScreen> createState() => _FiltroScreenState();
}

class _FiltroScreenState extends ConsumerState<FiltroScreen> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final status = await checkFilter(ref);
    if (!mounted) return;
    setState(() => _checking = false);
    toast(context, status.labelEs);
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(filterStatusProvider);
    return HosPage(
      title: 'FILTRO',
      subtitle: 'Redes bloqueadas por DNS, sin fuerza de voluntad',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Estado',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(last?.status.labelEs ?? 'SIN COMPROBAR', style: Theme.of(context).textTheme.headlineSmall),
            if (last != null) Text('Comprobado: ${last.at.replaceFirst('T', ' ').substring(0, 16)}'),
            const SizedBox(height: 8),
            BigButton(
              label: _checking ? 'Comprobando…' : 'Comprobar ahora',
              icon: Icons.dns_outlined,
              onPressed: _checking ? null : _check,
            ),
            const Note('La comprobación pregunta por el primer dominio bloqueado y el primer permitido de tus listas. '
                'HumanOS solo lo detecta: el filtro se enciende y se apaga en los ajustes del teléfono.'),
          ]),
        ),
        const _ListPanel(list: DnsList.bloquear),
        const _ListPanel(list: DnsList.permitir),
        const _GuidePanel(),
      ]),
    );
  }
}

class _ListPanel extends ConsumerWidget {
  const _ListPanel({required this.list});
  final DnsList list;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(list == DnsList.bloquear ? 'BLOQUEAR DOMINIO' : 'PERMITIR DOMINIO'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Dominio o dirección del sitio'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('AGREGAR')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final domain = normalizeDomain(text);
    if (domain == null) {
      if (context.mounted) toast(context, 'Eso no es un dominio. Ejemplo de forma: sitio.com');
      return;
    }
    await ref.read(dnsRepositoryProvider).put(domain, list);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [
      for (final r in ref.watch(dnsDomainsProvider).value ?? const <DnsDomainRow>[])
        if (DnsList.parse(r.list) == list) r,
    ];
    final repo = ref.read(dnsRepositoryProvider);
    Future<void> copy(ExportFormat format) async {
      await Clipboard.setData(ClipboardData(text: exportDomains(rows.map((r) => r.domain), list: list, format: format)));
      if (context.mounted) toast(context, 'Copiado: ${format.labelEs.toLowerCase()}. Pégalo en tu perfil DNS.');
    }

    return TerminalPanel(
      label: list.labelEs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Note(list == DnsList.bloquear
                ? 'Sin dominios. Agrega los de las redes que quieres fuera de tu día.'
                : 'Sin dominios. Agrega los que siempre deben funcionar (por ejemplo, tu mensajería y tu video).'),
          for (final r in rows)
            Row(children: [
              Expanded(child: Text(r.domain)),
              IconButton(tooltip: 'Quitar ${r.domain}', icon: const Icon(Icons.close), onPressed: () => repo.remove(r.id)),
            ]),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('AGREGAR'),
              onPressed: () => _add(context, ref),
            ),
            if (rows.isNotEmpty) ...[
              OutlinedButton(onPressed: () => copy(ExportFormat.lineas), child: const Text('COPIAR LISTA')),
              OutlinedButton(onPressed: () => copy(ExportFormat.adguard), child: const Text('COPIAR REGLAS ADGUARD')),
            ],
          ]),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('$n. $text', style: style),
        );
    return TerminalPanel(
      label: 'Guía paso a paso',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('OPCIÓN A · NEXTDNS (GRATIS)', style: Theme.of(context).textTheme.titleSmall),
          step('1', 'En el navegador, entra a la página de NextDNS y crea una cuenta gratuita.'),
          step('2', 'Abre tu configuración. En «Configurar», pestaña Android, copia el nombre de host que te muestra.'),
          step('3', 'En el teléfono: Ajustes → Conexión y compartir → DNS privado → «Nombre de host del proveedor» '
              '→ pega ese nombre → Guardar.'),
          step('4', 'Aquí, en Bloqueados, COPIAR LISTA, y pégala en la «Lista de bloqueo» (Denylist) de NextDNS. '
              'Haz lo mismo con Permitidos en la «Lista de permitidos» (Allowlist).'),
          step('5', 'Opcional, en NextDNS → Control parental → Categorías: contenido para adultos y apuestas.'),
          step('6', 'Vuelve aquí y toca COMPROBAR AHORA.'),
          const Note('El plan gratuito de NextDNS tiene un cupo mensual de consultas. Si se agota, el filtrado se '
              'suspende hasta el mes siguiente (las páginas siguen cargando). Revisa el cupo en su panel.'),
          const SizedBox(height: 8),
          Text('OPCIÓN B · ADGUARD DNS', style: Theme.of(context).textTheme.titleSmall),
          step('1', 'Crea una cuenta gratuita en AdGuard DNS y un «servidor» para tu teléfono.'),
          step('2', 'Pon su nombre de host en Ajustes → Conexión y compartir → DNS privado.'),
          step('3', 'Aquí, COPIAR REGLAS ADGUARD en cada lista y pégalas en «Reglas de usuario».'),
          const SizedBox(height: 8),
          Text('ANTES DE CONFIAR EN EL FILTRO', style: Theme.of(context).textTheme.titleSmall),
          const Note('Facebook, Messenger, Instagram y WhatsApp comparten infraestructura. Bloquear un dominio '
              'compartido puede romper fotos o avatares en WhatsApp. Tras activar el filtro, envía y recibe una foto '
              'y haz una llamada por WhatsApp; si algo falla, quita de Bloqueados el último dominio que agregaste.'),
          const Note('Para quitar el filtro: Ajustes → Conexión y compartir → DNS privado → Automático. '
              'HumanOS solo lo detecta; no cambia nada por su cuenta.'),
        ],
      ),
    );
  }
}
