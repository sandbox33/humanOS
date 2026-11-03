import 'package:flutter/material.dart';

import '../../../app/widgets/big_button.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../app/widgets/terminal_panel.dart';

/// Prominent disclosure shown before any location permission is asked.
/// Pops `true` when the user accepts.
class DisclosurePage extends StatelessWidget {
  const DisclosurePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HosPage(
      title: 'UBICACIÓN',
      subtitle: 'Antes de activar las zonas',
      body: PanelList(children: [
        TerminalPanel(
          label: 'Qué hace HumanOS con tu ubicación',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HumanOS usa tu ubicación en segundo plano, también con la app cerrada, solo para saber '
                'cuándo entras o sales de las zonas que tú creas.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Note('Con eso calla los avisos mientras trabajas o entrenas, te sugiere la plantilla de '
                  'trabajo y muestra tus recordatorios al llegar o al salir.'),
              const Note('No sigue tu recorrido ni guarda un historial de rutas: solo la hora de cada entrada y '
                  'salida, cifrada en el teléfono. Nada sale del teléfono.'),
              const Note('Lo hace el sistema (geocercas de Google Play services), sin un servicio de ubicación '
                  'en primer plano. Puedes apagarlo cuando quieras en CONTEXTO.'),
              const Note('Android te pedirá dos permisos: primero ubicación precisa y después «Permitir todo el '
                  'tiempo».'),
            ],
          ),
        ),
        BigButton(label: 'Entendido, continuar', icon: Icons.check, onPressed: () => Navigator.of(context).pop(true)),
        BigButton(label: 'Ahora no', outlined: true, onPressed: () => Navigator.of(context).pop(false)),
      ]),
    );
  }
}
