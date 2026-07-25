import 'dart:math' as math;

/// Cost of matching reference index `i` against learner index `j`.
typedef PairCost = double Function(int i, int j);

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
    this.minBandRadius = 4,
    this.saturationRatio = 0.15,
    this.warpPenalty = 0.08,
  });

  /// Corridor half-width in frames around the slope-adjusted diagonal.
  ///
  /// At 30 fps, 24 frames ≈ 0.8 s of tolerated drift over a phrase — roughly a
  /// beat at 75 BPM. Tune per style in versioned config, not here.
  final int bandRadius;

  final int minBandRadius;

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

  DtwResult align(int n, int m, PairCost cost) {
    if (n == 0 || m == 0) {
      return const DtwResult(
        normalizedCost: 1.0,
        pathRef: <int>[],
        pathLearner: <int>[],
        refToLearner: <int>[],
        bandSaturated: true,
      );
    }

    final int radius = math.max(minBandRadius, bandRadius);
    final double slope = (n > 1) ? (m - 1) / (n - 1) : 0.0;

    // The band as the *slope* defines it, before clipping to the array. Edge
    // detection must use these: clipping at the corners would make cell (0,0)
    // look like it was pinned against the wall on every alignment, including
    // a perfect one.
    double loBand(int i) => (i * slope) - radius;
    double hiBand(int i) => (i * slope) + radius;

    int lowFor(int i) => math.max(0, loBand(i).floor());
    int highFor(int i) => math.min(m - 1, hiBand(i).ceil());

    final List<List<double>> acc = List<List<double>>.generate(
      n,
      (_) => List<double>.filled(m, _inf),
      growable: false,
    );

    for (int i = 0; i < n; i++) {
      final int lo = lowFor(i);
      final int hi = highFor(i);
      for (int j = lo; j <= hi; j++) {
        final double c = cost(i, j);
        if (i == 0 && j == 0) {
          acc[i][j] = c;
          continue;
        }
        double best = _inf;
        if (i > 0 && acc[i - 1][j] + warpPenalty < best) {
          best = acc[i - 1][j] + warpPenalty;
        }
        if (j > 0 && acc[i][j - 1] + warpPenalty < best) {
          best = acc[i][j - 1] + warpPenalty;
        }
        if (i > 0 && j > 0 && acc[i - 1][j - 1] < best) best = acc[i - 1][j - 1];
        acc[i][j] = best.isInfinite ? _inf : best + c;
      }
    }

    if (acc[n - 1][m - 1].isInfinite) {
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
      final double diag = acc[i - 1][j - 1];
      final double up = acc[i - 1][j] + warpPenalty;
      final double left = acc[i][j - 1] + warpPenalty;
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
