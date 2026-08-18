/// A simultaneous set of pitch classes (0 = C, 1 = C#/Db, … 11 = B),
/// deliberately not a chord *name* — naming a chord is a music-theory
/// judgment that belongs to a caller's curriculum, not this package.
class ChordEstimate {
  const ChordEstimate({
    required this.pitchClasses,
    required this.confidence,
    required this.timestampMs,
  });

  final Set<int> pitchClasses;
  final double confidence;
  final int timestampMs;

  /// A non-empty set where every pitch class is in 0-11. Fail-closed:
  /// anything else is not well-formed, so a caller can reject a corrupt
  /// estimate before acting on it instead of trusting out-of-range data.
  bool get isWellFormed =>
      pitchClasses.isNotEmpty && pitchClasses.every((pc) => pc >= 0 && pc <= 11);
}
