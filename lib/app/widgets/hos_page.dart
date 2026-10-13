import 'package:flutter/material.dart';

import 'crt_header.dart';

/// Page frame used by every screen: CRT header (with a back arrow when the
/// page was pushed), optional actions and tab bar, then the body.
class HosPage extends StatelessWidget {
  const HosPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.floatingActionButton,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canPop)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                Expanded(child: CrtHeader(title, subtitle: subtitle)),
                ...actions,
              ],
            ),
            if (bottom != null) bottom!,
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Standard scrolling list of panels.
class PanelList extends StatelessWidget {
  const PanelList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
        children: children,
      );
}

/// Shows a short message at the bottom of the screen.
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Yes/no confirmation; true only when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String accept = 'ACEPTAR',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title.toUpperCase()),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(accept),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for a line of text; null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  bool obscure = false,
  TextInputType? keyboardType,
  String? suffix,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => TextPromptDialog(
        title: title,
        initial: initial,
        hint: hint,
        obscure: obscure,
        keyboardType: keyboardType,
        suffix: suffix,
      ),
    );

/// Single-field dialog that owns its controller (disposed with the route,
/// after the closing transition).
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    this.initial,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  final String title;
  final String? initial;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? suffix;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title.toUpperCase()),
        content: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(hintText: widget.hint, suffixText: widget.suffix),
          onSubmitted: (_) => _accept(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCELAR'),
          ),
          FilledButton(onPressed: _accept, child: const Text('ACEPTAR')),
        ],
      );
}
