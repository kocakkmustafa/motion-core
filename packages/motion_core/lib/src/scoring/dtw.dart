import 'dart:math' as math;
import 'dart:typed_data';

/// Cost of matching reference index `i` against learner index `j`.
typedef PairCost = double Function(int i, int j);

/// Stable, machine-readable reasons why a DTW alignment was refused.
enum DtwLimitReason {
  sequenceLengthExceeded('dtw_sequence_length_exceeded'),
  storedCellLimitExceeded('dtw_stored_cell_limit_exceeded');

  const DtwLimitReason(this.code);

  final String code;
}

/// Capacity preflight for one prospective [Dtw.align] call.
final class DtwCapacity {
  const DtwCapacity({
    required this.referenceLength,
    required this.learnerLength,
    required this.storedCells,
    required this.maxSequenceLength,
    required this.maxStoredCells,
    required this.reason,
  });

  final int referenceLength;
  final int learnerLength;

  /// Number of numeric accumulator cells the slope-adjusted band would store.
  final int storedCells;

  /// Effective limits after library-wide hard ceilings are applied.
  final int maxSequenceLength;
  final int maxStoredCells;

  final DtwLimitReason? reason;

  bool get allowed => reason == null;
}

/// Named fail-closed exception from a direct [Dtw.align] call.
///
/// This is an [ArgumentError] so existing batch/CLI boundaries that already
/// reject invalid input continue to stop cleanly instead of silently treating
/// a refused alignment as a poor match.
final class DtwLimitExceeded extends ArgumentError {
  DtwLimitExceeded(this.capacity)
      : reason = capacity.reason!,
        super(
          '${capacity.reason!.code}: alignment '
          '${capacity.referenceLength}x${capacity.learnerLength} requires '
          '${capacity.storedCells} stored cells; limits are '
          '${capacity.maxSequenceLength} frames per sequence and '
          '${capacity.maxStoredCells} stored cells',
        );

  final DtwCapacity capacity;
  final DtwLimitReason reason;
}

/// Result of a dynamic time warping alignment.
final class DtwResult {
  const DtwResult({
    required this.normalizedCost,
    required this.pathRef,
    required this.pathLearner,
    required this.refToLearner,
    required this.bandSaturated,
    this.bandEdgeRatio = 0,
  });

  /// Accumulated cost divided by path length, in the same units as the cost
  /// function (for [AngularSimilarity.distance], `[0, 1]`).
  final double normalizedCost;

  /// Warping path, as two parallel index arrays.
  final List<int> pathRef;
  final List<int> pathLearner;

  /// For each reference index, the representative learner index it matched.
  ///
  /// This — not the cost — is what timing feedback is built from: comparing the
  /// timestamps of `refToLearner[i]` and `i` says whether the learner was ahead
  /// of or behind the reference at that moment.
  final List<int> refToLearner;

  /// True when the optimal path spent a meaningful share of its length pressed
  /// against the band limit.
  ///
  /// An honest failure signal. A saturated band means the learner's timing was
  /// so far off that the alignment itself is unreliable — the right response is
  /// "you're way off the beat, let's slow down", never a shape score computed
  /// along a path we do not trust.
  final bool bandSaturated;

  /// Share of the path that rode the band edge, in `[0, 1]`.
  final double bandEdgeRatio;

  double get similarity => (1.0 - normalizedCost).clamp(0.0, 1.0);

  /// Signed time offsets in microseconds, one per reference index.
  ///
  /// Positive means the learner reached that moment *late*.
  List<int> timingOffsetsUs(List<int> refTimesUs, List<int> learnerTimesUs) =>
      List<int>.generate(
        refToLearner.length,
        (int i) => learnerTimesUs[refToLearner[i]] - refTimesUs[i],
        growable: false,
      );
}

/// Banded dynamic time warping over two index ranges.
///
/// The band is not an optimisation here, it is a correctness constraint.
/// Unconstrained DTW will happily stretch one frame of the learner across half
/// the reference to minimise cost, which awards a high shape score to a
/// performance that was never in time. Restricting the path to a corridor
/// around the diagonal means "the shapes matched" can only be reported for a
/// learner who was at least roughly in time — and when they were not, the band
/// saturates and says so.
final class Dtw {
  const Dtw({
    this.bandRadius = 24,
    this.bandRadiusS = 0.8,
    this.minBandRadius = 4,
    this.saturationRatio = 0.15,
    this.warpPenalty = 0.08,
    this.maxSequenceLength = hardMaxSequenceLength,
    this.maxStoredCells = hardMaxStoredCells,
  });

  /// Absolute per-alignment ceiling: 10 minutes at 30 fps, or 5 at 60 fps.
  ///
  /// Callers may lower this with [maxSequenceLength], but cannot raise it.
  static const int hardMaxSequenceLength = 18000;

  /// Absolute per-alignment ceiling for numeric accumulator storage.
  ///
  /// Two million Float64 cells are 16 MB (about 15.3 MiB). Row metadata and
  /// the linear result structures are additionally bounded by
  /// [hardMaxSequenceLength].
  static const int hardMaxStoredCells = 2000000;

  /// Corridor half-width in frames around the slope-adjusted diagonal.
  ///
  /// Legacy fallback, used only when [align] is not told the frame interval:
  /// 24 frames is 0.8 s *at the 30 fps this number was tuned on*, and at any
  /// other rate it silently means a different amount of time — the M-O-23
  /// unit-leak class (wf_dfb1dcd3 confirmed it here). Callers that know
  /// their material's measured `dtUs` should pass it so [bandRadiusS]
  /// governs instead.
  final int bandRadius;

  /// Corridor half-width in SECONDS — the declared meaning of the band.
  ///
  /// The tolerated drift is temporal ("roughly a beat at 75 BPM"), so the
  /// parameter is temporal; frames are derived per call from the measured
  /// frame interval, never assumed (doc 60 §1). Null disables the
  /// time-based path entirely.
  final double? bandRadiusS;

  final int minBandRadius;

  /// Caller-selected sequence ceiling, clamped by
  /// [hardMaxSequenceLength].
  final int maxSequenceLength;

  /// Caller-selected band-cell ceiling, clamped by [hardMaxStoredCells].
  final int maxStoredCells;

  int get effectiveMaxSequenceLength =>
      math.max(0, math.min(maxSequenceLength, hardMaxSequenceLength));

  int get effectiveMaxStoredCells =>
      math.max(0, math.min(maxStoredCells, hardMaxStoredCells));

  /// The corridor radius in frames for material with the given measured
  /// frame interval; falls back to the legacy [bandRadius] when the
  /// interval is unknown.
  int effectiveRadius(int? dtUs) {
    if (bandRadiusS != null && dtUs != null && dtUs > 0) {
      return math.max(minBandRadius, (bandRadiusS! * 1e6 / dtUs).round());
    }
    return math.max(minBandRadius, bandRadius);
  }

  /// Median frame interval of [timestampsUs], in µs — the measured `dtUs`
  /// that [align] wants. Null when it cannot be measured (fewer than two
  /// frames or non-increasing timestamps).
  static int? medianDtUs(List<int> timestampsUs) {
    if (timestampsUs.length < 2) return null;
    final List<int> dts = <int>[
      for (int i = 1; i < timestampsUs.length; i++)
        timestampsUs[i] - timestampsUs[i - 1],
    ]..sort();
    final int dt = dts[dts.length ~/ 2];
    return dt > 0 ? dt : null;
  }

  /// Share of the path that must ride the band edge before the alignment is
  /// declared untrustworthy.
  ///
  /// A single touch is not evidence of anything — even a perfect alignment
  /// brushes the corridor when the two takes differ slightly in length. What
  /// matters is a path that is *held* against the wall, which is what a learner
  /// dancing at the wrong moment produces.
  final double saturationRatio;

  /// Extra cost charged for each non-diagonal step.
  ///
  /// The band alone does not stop DTW from cheating. Inside a wide-enough
  /// corridor the cheapest path is often to *park*: hold one learner frame
  /// while the reference advances through its most distinctive moments, so the
  /// learner's resting pose gets matched against the reference's peak and the
  /// attempt scores well for doing nothing. Charging for every frame of warping
  /// makes parking cost more than it saves, and leaves genuine elasticity —
  /// a step taken slightly slow — essentially free.
  ///
  /// The penalty steers the alignment only. The cost reported back is measured
  /// along the chosen path from the raw distances, so a score is never inflated
  /// or deflated by a regularisation term.
  final double warpPenalty;

  static const double _inf = double.infinity;

  /// Computes the exact sparse-band storage needed by [align] without
  /// allocating it.
  DtwCapacity capacityFor(int n, int m, {int? dtUs}) {
    final int sequenceLimit = effectiveMaxSequenceLength;
    final int cellLimit = effectiveMaxStoredCells;
    if (n < 0 || m < 0 || n > sequenceLimit || m > sequenceLimit) {
      return DtwCapacity(
        referenceLength: n,
        learnerLength: m,
        storedCells: 0,
        maxSequenceLength: sequenceLimit,
        maxStoredCells: cellLimit,
        reason: DtwLimitReason.sequenceLengthExceeded,
      );
    }
    if (n == 0 || m == 0) {
      return DtwCapacity(
        referenceLength: n,
        learnerLength: m,
        storedCells: 0,
        maxSequenceLength: sequenceLimit,
        maxStoredCells: cellLimit,
        reason: null,
      );
    }

    final int radius = effectiveRadius(dtUs);
    final double slope = (n > 1) ? (m - 1) / (n - 1) : 0.0;
    int storedCells = 0;
    for (int i = 0; i < n; i++) {
      final int low = math.max(0, ((i * slope) - radius).floor());
      final int high = math.min(m - 1, ((i * slope) + radius).ceil());
      if (high >= low) storedCells += high - low + 1;
    }

    return DtwCapacity(
      referenceLength: n,
      learnerLength: m,
      storedCells: storedCells,
      maxSequenceLength: sequenceLimit,
      maxStoredCells: cellLimit,
      reason: storedCells > cellLimit
          ? DtwLimitReason.storedCellLimitExceeded
          : null,
    );
  }

  /// Whether [align] can run within both library-wide resource ceilings.
  bool canAlign(int n, int m, {int? dtUs}) =>
      capacityFor(n, m, dtUs: dtUs).allowed;

  DtwResult align(int n, int m, PairCost cost, {int? dtUs}) {
    final DtwCapacity capacity = capacityFor(n, m, dtUs: dtUs);
    if (!capacity.allowed) throw DtwLimitExceeded(capacity);

    if (n == 0 || m == 0) {
      return const DtwResult(
        normalizedCost: 1.0,
        pathRef: <int>[],
        pathLearner: <int>[],
        refToLearner: <int>[],
        bandSaturated: true,
      );
    }

    final int radius = effectiveRadius(dtUs);
    final double slope = (n > 1) ? (m - 1) / (n - 1) : 0.0;

    // The band as the *slope* defines it, before clipping to the array. Edge
    // detection must use these: clipping at the corners would make cell (0,0)
    // look like it was pinned against the wall on every alignment, including
    // a perfect one.
    double loBand(int i) => (i * slope) - radius;
    double hiBand(int i) => (i * slope) + radius;

    int lowFor(int i) => math.max(0, loBand(i).floor());
    int highFor(int i) => math.min(m - 1, hiBand(i).ceil());

    final List<int> rowStarts = List<int>.generate(n, lowFor, growable: false);
    final List<Float64List> acc = List<Float64List>.generate(n, (int i) {
      final int width = math.max(0, highFor(i) - rowStarts[i] + 1);
      final Float64List row = Float64List(width);
      row.fillRange(0, width, _inf);
      return row;
    }, growable: false);

    double accumulatedAt(int i, int j) {
      if (i < 0 || i >= n) return _inf;
      final int offset = j - rowStarts[i];
      if (offset < 0 || offset >= acc[i].length) return _inf;
      return acc[i][offset];
    }

    void setAccumulatedAt(int i, int j, double value) {
      acc[i][j - rowStarts[i]] = value;
    }

    for (int i = 0; i < n; i++) {
      final int lo = lowFor(i);
      final int hi = highFor(i);
      for (int j = lo; j <= hi; j++) {
        final double c = cost(i, j);
        if (i == 0 && j == 0) {
          setAccumulatedAt(i, j, c);
          continue;
        }
        double best = _inf;
        if (i > 0 && accumulatedAt(i - 1, j) + warpPenalty < best) {
          best = accumulatedAt(i - 1, j) + warpPenalty;
        }
        if (j > 0 && accumulatedAt(i, j - 1) + warpPenalty < best) {
          best = accumulatedAt(i, j - 1) + warpPenalty;
        }
        if (i > 0 &&
            j > 0 &&
            accumulatedAt(i - 1, j - 1) < best) {
          best = accumulatedAt(i - 1, j - 1);
        }
        setAccumulatedAt(i, j, best.isInfinite ? _inf : best + c);
      }
    }

    if (accumulatedAt(n - 1, m - 1).isInfinite) {
      // The corridor could not reach the end — the two sequences differ in
      // length far beyond the tolerated drift.
      return DtwResult(
        normalizedCost: 1.0,
        pathRef: const <int>[],
        pathLearner: const <int>[],
        refToLearner: List<int>.generate(n, (int i) => math.min(m - 1, i), growable: false),
        bandSaturated: true,
        bandEdgeRatio: 1.0,
      );
    }

    // Backtrace.
    final List<int> pr = <int>[];
    final List<int> pl = <int>[];
    int edgeTouches = 0;
    int i = n - 1;
    int j = m - 1;
    while (true) {
      pr.add(i);
      pl.add(j);
      if (j <= loBand(i) || j >= hiBand(i)) edgeTouches++;
      if (i == 0 && j == 0) break;
      if (i == 0) {
        j -= 1;
        continue;
      }
      if (j == 0) {
        i -= 1;
        continue;
      }
      final double diag = accumulatedAt(i - 1, j - 1);
      final double up = accumulatedAt(i - 1, j) + warpPenalty;
      final double left = accumulatedAt(i, j - 1) + warpPenalty;
      if (diag <= up && diag <= left) {
        i -= 1;
        j -= 1;
      } else if (up <= left) {
        i -= 1;
      } else {
        j -= 1;
      }
    }
    final List<int> pathRef = pr.reversed.toList(growable: false);
    final List<int> pathLearner = pl.reversed.toList(growable: false);

    // One representative learner index per reference index. When several
    // learner frames map to the same reference frame (the learner moved
    // slower), the median keeps the estimate centred instead of biasing it to
    // whichever end the backtrace happened to reach first.
    final List<List<int>> buckets =
        List<List<int>>.generate(n, (_) => <int>[], growable: false);
    for (int k = 0; k < pathRef.length; k++) {
      buckets[pathRef[k]].add(pathLearner[k]);
    }
    final List<int> refToLearner = List<int>.generate(
      n,
      (int idx) {
        final List<int> b = buckets[idx];
        if (b.isEmpty) return math.min(m - 1, (idx * slope).round());
        return b[b.length ~/ 2];
      },
      growable: false,
    );

    // Report the raw distance along the chosen path, excluding the warping
    // penalty that steered it there — the penalty is a search prior, not part
    // of how well the learner danced.
    double pathCost = 0;
    for (int k = 0; k < pathRef.length; k++) {
      pathCost += cost(pathRef[k], pathLearner[k]);
    }

    final double edgeRatio = edgeTouches / pathRef.length;
    return DtwResult(
      normalizedCost: pathCost / pathRef.length,
      pathRef: pathRef,
      pathLearner: pathLearner,
      refToLearner: refToLearner,
      bandSaturated: edgeRatio > saturationRatio,
      bandEdgeRatio: edgeRatio,
    );
  }
}
