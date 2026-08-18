/// A detected note/beat onset. [strength] is an arbitrary non-negative,
/// implementation-defined energy unit — comparable across events from the
/// same detector, not a calibrated physical quantity.
class OnsetEvent {
  const OnsetEvent({
    required this.timestampMs,
    required this.strength,
    required this.confidence,
  });

  final int timestampMs;
  final double strength;
  final double confidence;
}
