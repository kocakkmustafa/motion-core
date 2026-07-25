import 'dart:math' as math;

/// A mapping between wall time on the shared monotonic clock and musical beats.
///
/// Deliberately an interface with several implementations rather than a single
/// BPM field: V1 ships a metronome and known-BPM royalty-free tracks (constant
/// tempo), while V1.5 adds one-off offline analysis of a user's own track,
/// which yields an explicit and slightly irregular list of beat times. Both
/// must drive the identical scoring path, so the *source* of the grid is not
/// allowed to leak into the engine.
abstract interface class BeatGrid {
  /// Nominal tempo in beats per minute.
  double get bpm;

  /// Beats per bar (4 for the 8-count material that dominates V1 styles).
  int get beatsPerBar;

  /// Timestamp of a beat index on the shared monotonic clock.
  int timeOfBeatUs(int beatIndex);

  /// Fractional beat position at a timestamp. `2.5` means halfway between
  /// beats 2 and 3 — this is what an "and" count lands on.
  double beatPositionAt(int tUs);

  /// Highest valid beat index, or `null` when the grid is unbounded
  /// (a free-running metronome).
  int? get lastBeatIndex;
}

extension BeatGridQueries on BeatGrid {
  int beatIndexAt(int tUs) => beatPositionAt(tUs).floor();

  /// Position within the current beat, in `[0, 1)`.
  double phaseAt(int tUs) {
    final double p = beatPositionAt(tUs);
    return p - p.floorToDouble();
  }

  int nearestBeatIndexAt(int tUs) => beatPositionAt(tUs).round();

  /// Signed distance to the nearest beat. Positive means *after* the beat.
  int offsetToNearestBeatUs(int tUs) =>
      tUs - timeOfBeatUs(nearestBeatIndexAt(tUs));

  /// Bar number and beat-within-bar, both 0-based.
  (int bar, int beatInBar) barPositionAt(int tUs) {
    final int b = beatIndexAt(tUs);
    final int bpB = math.max(1, beatsPerBar);
    return (b ~/ bpB, b % bpB);
  }

  /// The "1" of the 8-count phrase containing [tUs], as a beat index.
  int phraseStartBeatAt(int tUs, {int phraseBeats = 8}) {
    final int b = beatIndexAt(tUs);
    return (b ~/ phraseBeats) * phraseBeats;
  }

  int get beatIntervalUs => (60000000 / bpm).round();
}

/// Fixed-tempo grid: a metronome, or a track whose BPM is known up front.
final class ConstantTempoBeatGrid implements BeatGrid {
  const ConstantTempoBeatGrid({
    required this.bpm,
    this.firstBeatUs = 0,
    this.beatsPerBar = 4,
    this.lastBeatIndex,
  }) : assert(bpm > 0, 'bpm must be positive');

  @override
  final double bpm;

  /// Timestamp of beat 0 — the track's downbeat, not the moment playback was
  /// requested. A file's first beat is almost never at sample zero.
  final int firstBeatUs;

  @override
  final int beatsPerBar;

  @override
  final int? lastBeatIndex;

  double get _intervalUs => 60000000.0 / bpm;

  @override
  int timeOfBeatUs(int beatIndex) =>
      firstBeatUs + (beatIndex * _intervalUs).round();

  @override
  double beatPositionAt(int tUs) => (tUs - firstBeatUs) / _intervalUs;

  ConstantTempoBeatGrid withFirstBeat(int tUs) => ConstantTempoBeatGrid(
        bpm: bpm,
        firstBeatUs: tUs,
        beatsPerBar: beatsPerBar,
        lastBeatIndex: lastBeatIndex,
      );

  /// Same music, practised slower. Used by the teach-then-try loop, where a
  /// step is first drilled under tempo and only then taken to full speed.
  ConstantTempoBeatGrid atTempoRatio(double ratio) => ConstantTempoBeatGrid(
        bpm: bpm * ratio,
        firstBeatUs: firstBeatUs,
        beatsPerBar: beatsPerBar,
        lastBeatIndex: lastBeatIndex,
      );
}

/// Grid backed by an explicit list of beat timestamps.
///
/// Produced by one-off offline analysis of a user-supplied track (V1.5), and by
/// hand-annotated fixtures. Real music drifts; forcing analysed beats through a
/// single BPM would reintroduce the error the analysis just removed.
final class ExplicitBeatGrid implements BeatGrid {
  ExplicitBeatGrid({
    required List<int> beatTimesUs,
    this.beatsPerBar = 4,
  })  : assert(beatTimesUs.length >= 2, 'need at least two beats'),
        _beats = List<int>.unmodifiable(beatTimesUs);

  final List<int> _beats;

  @override
  final int beatsPerBar;

  List<int> get beatTimesUs => _beats;

  @override
  int? get lastBeatIndex => _beats.length - 1;

  @override
  double get bpm {
    final List<int> gaps = <int>[
      for (int i = 1; i < _beats.length; i++) _beats[i] - _beats[i - 1],
    ]..sort();
    // Median, not mean: a single mis-detected beat doubles or halves one gap,
    // and a mean would carry that error into every tempo-derived tolerance.
    final int median = gaps[gaps.length ~/ 2];
    return median <= 0 ? 0 : 60000000.0 / median;
  }

  @override
  int timeOfBeatUs(int beatIndex) {
    if (beatIndex < 0) {
      final int gap = _beats[1] - _beats[0];
      return _beats[0] + beatIndex * gap;
    }
    if (beatIndex >= _beats.length) {
      final int gap = _beats[_beats.length - 1] - _beats[_beats.length - 2];
      return _beats.last + (beatIndex - (_beats.length - 1)) * gap;
    }
    return _beats[beatIndex];
  }

  @override
  double beatPositionAt(int tUs) {
    if (tUs <= _beats.first) {
      final int gap = _beats[1] - _beats[0];
      return (tUs - _beats.first) / gap;
    }
    if (tUs >= _beats.last) {
      final int gap = _beats[_beats.length - 1] - _beats[_beats.length - 2];
      return (_beats.length - 1) + (tUs - _beats.last) / gap;
    }
    int lo = 0;
    int hi = _beats.length - 1;
    while (hi - lo > 1) {
      final int mid = (lo + hi) ~/ 2;
      if (_beats[mid] <= tUs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final int span = _beats[hi] - _beats[lo];
    return lo + (span == 0 ? 0 : (tUs - _beats[lo]) / span);
  }
}
