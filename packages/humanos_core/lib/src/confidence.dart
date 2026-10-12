/// Confidence levels shown next to every derived number. Stored in the
/// databases with their Spanish codes (`alta`, `media`, `baja`).
library;

enum Confidence {
  alta('alta'),
  media('media'),
  baja('baja');

  const Confidence(this.code);

  /// Code stored in SQLite and shown in chips.
  final String code;

  /// Parses a stored code; unknown values degrade to [Confidence.baja] so a
  /// bad row never looks more certain than it is.
  static Confidence parse(String? code) {
    for (final value in Confidence.values) {
      if (value.code == code) return value;
    }
    return Confidence.baja;
  }

  /// The less certain of two levels.
  Confidence min(Confidence other) => index >= other.index ? this : other;

  /// Lowers the level by [steps], never below [Confidence.baja].
  Confidence lower([int steps = 1]) {
    final target = (index + steps).clamp(0, Confidence.values.length - 1);
    return Confidence.values[target];
  }
}
