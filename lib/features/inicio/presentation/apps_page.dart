import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/hos_page.dart';
import '../../../services/launcher.dart';
import '../../../services/services.dart';
import '../../pantalla/domain/screen_model.dart';
import '../domain/schedule_model.dart';

/// Every launchable app on the phone (read again when the page opens).
final installedAppsProvider = FutureProvider<List<InstalledApp>>((ref) => ref.watch(launcherProvider).apps());

/// The packages the user pinned to INICIO, in their order.
final pinnedPackagesProvider = Provider<List<String>>((ref) {
  final raw = (ref.watch(settingsMapProvider).value ?? const {})[LauncherKey.pinned] ?? '';
  return [
    for (final p in raw.split(','))
      if (p.trim().isNotEmpty) p.trim(),
  ];
});

/// Apps of a category the user hides in the current block are left out of
/// the home screen.
final visibleAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  final apps = await ref.watch(installedAppsProvider.future);
  final hidden = ref.watch(hiddenNowProvider);
  if (hidden.isEmpty) return apps;
  final classes = ref.watch(effectiveClassesProvider);
  return [
    for (final a in apps)
      if (!hidden.contains(classes[a.package] ?? AppCategory.sinClasificar)) a,
  ];
});

/// Opens [app]; a social app waits [socialFrictionSeconds] first when the
/// user turned that pause on.
Future<void> openApp(BuildContext context, WidgetRef ref, InstalledApp app) async {
  // Read from the source, not from a provider that may still be loading.
  final friction = await ref.read(settingsRepositoryProvider).get(ScreenKey.frictionSocial) == '1';
  if (!context.mounted) return;
  var category = AppCategory.sinClasificar;
  if (friction) {
    // Straight from the database and the phone: a provider nobody listens
    // to may be paused and never answer.
    final stored = await ref.read(screenRepositoryProvider).classes();
    var declared = const <String, int>{};
    try {
      declared = await ref.read(screenTimeProvider)?.appCategories() ?? const {};
    } on Object {
      // No suggestion: the user's own class decides.
    }
    category = stored[app.package] ?? suggestCategory(declared[app.package]);
    if (!context.mounted) return;
  }
  if (category == AppCategory.redes) {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FrictionDialog(label: app.label),
    );
    if (go != true) return;
  }
  await ref.read(launcherProvider).launch(app.package);
}

class _FrictionDialog extends StatefulWidget {
  const _FrictionDialog({required this.label});
  final String label;

  @override
  State<_FrictionDialog> createState() => _FrictionDialogState();
}

class _FrictionDialogState extends State<_FrictionDialog> {
  int _left = socialFrictionSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.label.toUpperCase()),
        content: Text('Se abre en $_left s.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('NO ABRIR')),
        ],
      );
}

/// Pinned apps that are still installed.
final pinnedAppsProvider = FutureProvider<List<InstalledApp>>((ref) async {
  final packages = ref.watch(pinnedPackagesProvider);
  if (packages.isEmpty) return const [];
  final apps = {for (final a in await ref.watch(visibleAppsProvider.future)) a.package: a};
  return [
    for (final p in packages) ?apps[p],
  ];
});

Future<void> togglePinned(WidgetRef ref, String package) async {
  final current = ref.read(pinnedPackagesProvider);
  final next = current.contains(package) ? [...current.where((p) => p != package)] : [...current, package];
  final repo = ref.read(settingsRepositoryProvider);
  if (next.isEmpty) {
    await repo.remove(LauncherKey.pinned);
  } else {
    await repo.set(LauncherKey.pinned, next.join(','));
  }
}

/// An app's own icon, or a plain glyph while it loads or when it has none.
class AppIcon extends ConsumerWidget {
  const AppIcon(this.package, {super.key, this.size = 40});

  final String package;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
        future: ref.read(launcherProvider).icon(package),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return Icon(Icons.android, size: size);
          return Image.memory(bytes, width: size, height: size, gaplessPlayback: true);
        },
      );
}

/// TODAS LAS APPS: search, open, and hold to pin or see the app's info.
class AppsPage extends ConsumerStatefulWidget {
  const AppsPage({super.key});

  @override
  ConsumerState<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends ConsumerState<AppsPage> {
  String _query = '';

  Future<void> _options(InstalledApp app) async {
    final pinned = ref.read(pinnedPackagesProvider).contains(app.package);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(app.label.toUpperCase(), style: Theme.of(context).textTheme.titleLarge)),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(pinned ? 'Quitar de INICIO' : 'Fijar en INICIO'),
            onTap: () => Navigator.of(context).pop('pin'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Información de la app'),
            onTap: () => Navigator.of(context).pop('info'),
          ),
        ]),
      ),
    );
    switch (choice) {
      case 'pin':
        await togglePinned(ref, app.package);
      case 'info':
        await ref.read(launcherProvider).appDetails(app.package);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(visibleAppsProvider);
    final hidden = ref.watch(hiddenNowProvider);
    final pinned = ref.watch(pinnedPackagesProvider);
    final q = normalizeEs(_query.trim());
    return HosPage(
      title: 'APPS',
      subtitle: hidden.isEmpty
          ? 'Toca para abrir · mantén pulsado para fijar'
          : 'Ocultas en este bloque: ${hidden.map((c) => c.labelEs).join(', ')}',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(labelText: 'Buscar app', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: apps.when(
            loading: () => const Center(child: Text('Cargando apps…')),
            error: (_, _) => const Center(child: Text('No se pudo leer la lista de apps.')),
            data: (list) {
              final shown = [
                for (final a in list)
                  if (q.isEmpty || normalizeEs(a.label).contains(q)) a,
              ];
              if (shown.isEmpty) return const Center(child: Text('Sin apps que mostrar.'));
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final app = shown[i];
                  return ListTile(
                    minVerticalPadding: 10,
                    leading: AppIcon(app.package),
                    title: Text(app.label),
                    trailing: pinned.contains(app.package) ? const Icon(Icons.push_pin) : null,
                    onTap: () => openApp(context, ref, app),
                    onLongPress: () => _options(app),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
