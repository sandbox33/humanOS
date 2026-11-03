import 'package:flutter/material.dart';

import '../../../services/launcher.dart';

/// The last resort of the home screen: if a screen fails to build, this
/// plain list of apps takes its place, so the phone is never left on a
/// blank screen. It needs nothing from the rest of the app (no theme, no
/// database), only the launcher channel.
class SafeAppList extends StatefulWidget {
  const SafeAppList({super.key, required this.launcher, this.reason});

  final LauncherService launcher;
  final String? reason;

  @override
  State<SafeAppList> createState() => _SafeAppListState();
}

class _SafeAppListState extends State<SafeAppList> {
  late final Future<List<InstalledApp>> _apps = widget.launcher.apps();

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(color: Color(0xFFFFFFFF), fontSize: 18);
    Widget button(String label, VoidCallback onTap) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(label, style: text)),
        );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('HUMANOS · MODO SEGURO', style: TextStyle(color: Color(0xFF39FF14), fontSize: 22)),
                ),
                if (widget.reason != null) Text(widget.reason!, style: text.copyWith(fontSize: 13), maxLines: 3),
                button('> TELÉFONO', widget.launcher.openDialer),
                button('> ELEGIR OTRA PANTALLA DE INICIO', widget.launcher.openHomeSettings),
                Expanded(
                  child: FutureBuilder<List<InstalledApp>>(
                    future: _apps,
                    builder: (context, snapshot) {
                      final apps = snapshot.data ?? const <InstalledApp>[];
                      return ListView(children: [
                        for (final a in apps) button(a.label, () => widget.launcher.launch(a.package)),
                      ]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
