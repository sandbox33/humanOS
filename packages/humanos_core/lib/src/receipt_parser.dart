/// Reads the text of a receipt photo (recognised on the phone) into lines
/// the user confirms or corrects (B4). Nothing is trusted blindly: a line
/// without a clear amount is left for the user, and every line goes
/// through the user before it reaches the pantry or the expenses.
library;

import 'money.dart';
import 'text_es.dart';

/// One product line of a receipt.
class ReceiptLine {
  const ReceiptLine({
    required this.text,
    required this.name,
    required this.amountCents,
    this.grams,
  });

  /// The line as recognised.
  final String text;

  /// The product words (without amounts or units).
  final String name;
  final int amountCents;

  /// Grams written on the line ("2KG", "500 G", "1 LB"); null when none.
  final double? grams;
}

class ParsedReceipt {
  const ParsedReceipt({required this.lines, this.totalCents});

  final List<ReceiptLine> lines;

  /// The total printed on the receipt, when one was found.
  final int? totalCents;

  /// Sum of the product lines, to compare with [totalCents].
  int get linesCents => lines.fold(0, (s, l) => s + l.amountCents);
}

final _amountAtEnd = RegExp(
  r'(-?\$?\s?\d{1,6}(?:[.,]\d{3})*[.,]\d{2})\s*[A-Z*]{0,2}\s*$',
  caseSensitive: false,
);
final _weight = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(KG|KILOS?|GR?S?|LBS?|LIBRAS?)\b',
  caseSensitive: false,
);
final _summaryWords = RegExp(
  r'\b(SUB\s?TOTAL|TOTAL|IVA|I\.V\.A|CAMBIO|VUELTO|EFECTIVO|TARJETA|DESCUENTO|SALDO|PAGO|RECIBIDO)\b',
  caseSensitive: false,
);
final _totalWord = RegExp(
  r'^\s*(TOTAL|TOTAL A PAGAR|VALOR TOTAL)\b',
  caseSensitive: false,
);

/// Grams in one pound (exact definition of the international pound).
const gramsPerPound = 453.59237;

double? _grams(String line) {
  final m = _weight.firstMatch(line);
  if (m == null) return null;
  final value = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (value == null || value <= 0) return null;
  final unit = m.group(2)!.toUpperCase();
  if (unit.startsWith('K')) return value * 1000;
  if (unit.startsWith('L')) return value * gramsPerPound;
  return value;
}

/// Splits the recognised text into product lines with their amounts and
/// the printed total. Header lines, taxes, change and payment lines are
/// skipped; a line whose amount cannot be read is left out (the user adds
/// what is missing).
ParsedReceipt parseReceipt(String text) {
  final lines = <ReceiptLine>[];
  int? total;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = _amountAtEnd.firstMatch(line);
    if (m == null) continue;
    final cents = parseCents(
      m.group(1)!.replaceAll(r'$', '').replaceAll(' ', ''),
    );
    if (cents == null) continue;
    if (_summaryWords.hasMatch(line)) {
      if (_totalWord.hasMatch(line) &&
          !RegExp('SUB', caseSensitive: false).hasMatch(line)) {
        total = cents;
      }
      continue;
    }
    if (cents <= 0) continue;
    var name = line.substring(0, m.start);
    name = name.replaceAll(_weight, ' ');
    name = name.replaceAll(RegExp(r'^\s*\d+\s*[xX*]?\s+'), ' ');
    name = name.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) continue;
    lines.add(
      ReceiptLine(
        text: line,
        name: name,
        amountCents: cents,
        grams: _grams(line),
      ),
    );
  }
  return ParsedReceipt(lines: lines, totalCents: total);
}

/// The key a receipt line is remembered by, so each product is linked to
/// the reference database once: accents, case and spaces do not matter.
String receiptKey(String name) => normalizeEs(name);
