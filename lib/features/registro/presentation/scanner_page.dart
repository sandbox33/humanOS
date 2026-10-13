import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/widgets/hos_page.dart';

/// Opens the camera and returns the first barcode read (or a typed one).
Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerPage(), fullscreenDialog: true),
    );

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _finish(String code) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return HosPage(
      title: 'ESCANEAR',
      subtitle: 'Apunta al código de barras',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value != null && value.isNotEmpty) {
                    _finish(value);
                    return;
                  }
                }
              },
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'La cámara no está disponible (${error.errorCode.name}). '
                    'Escribe el código.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.keyboard),
              label: const Text('ESCRIBIR CÓDIGO'),
              onPressed: () async {
                final code = await askText(
                  context,
                  title: 'Código de barras',
                  keyboardType: TextInputType.number,
                );
                if (code != null && code.isNotEmpty) _finish(code);
              },
            ),
          ),
        ],
      ),
    );
  }
}
