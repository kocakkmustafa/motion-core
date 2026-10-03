import 'dart:math' as math;

/// A single-pitch estimate at one point in time. Carries only measured
/// signal (frequency, confidence) — never a judgment about whether the
/// pitch was "correct" for whatever the caller's curriculum expects.
class PitchEstimate {
  const PitchEstimate({
    required this.frequencyHz,
    required this.confidence,
    required this.timestampMs,
  });

  final double frequencyHz;
  final double confidence;
  final int timestampMs;

  /// Nearest MIDI note number under standard 12-TET tuning (A4 = 69 =
  /// 440 Hz). Fail-closed: a non-positive frequency (silence, unvoiced
  /// input, or a sensor error sentinel), non-finite frequency, or numeric
  /// underflow yields `null` rather than a nonsensical note or an exception.
  int? get midiNote {
    if (!frequencyHz.isFinite || frequencyHz <= 0) return null;
    final semitonesFromA4 = 12 * (math.log(frequencyHz / 440) / math.ln2);
    if (!semitonesFromA4.isFinite) return null;
    return (69 + semitonesFromA4).round();
  }
}
