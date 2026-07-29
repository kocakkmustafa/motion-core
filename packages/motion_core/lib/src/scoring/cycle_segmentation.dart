import 'dart:math' as math;

import '../geometry/joint_angles.dart';

/// Result of measuring a take's repetition period.
///
/// Unmeasured is a verdict of "this material did not demonstrate a period",
/// never a default to be papered over: the caller must either treat the take
/// as non-cyclic material or exclude it by name — silently assuming a period
/// would re-create the exact failure cycle segmentation exists to fix
/// (L-139: whole-video DTW bending 4 reps into 9).
final class CyclePeriodEstimate {
  const CyclePeriodEstimate.measured({
    required this.periodFrames,
    required this.periodicity,
    required this.prominence,
  })  : measured = true,
        reason = 'ok';

  const CyclePeriodEstimate.unmeasured(this.reason)
      : measured = false,
        periodFrames = 0,
        periodicity = 0,
        prominence = 0;

  final bool measured;

  /// Repetition period in frames of the take's own sampling.
  final int periodFrames;

  /// ACF value at the chosen peak, in `[0, 1]`-ish (overlap-normalised).
  final double periodicity;

  /// Rise of the peak over the higher of its neighbouring valleys.
  final double prominence;

  final String reason;
}

/// Measures a take's repetition period from its joint-angle series — the
/// canonical (Dart) sibling of the harvest rig's `_periodicity` and the
/// entry point of CLI cycle segmentation (L-139 / 0.8.0).
///
/// M-C-25, carried over verbatim: the ACF's *global maximum* over the lag
/// range is structurally wrong on real recordings. Continuous motion makes
/// adjacent frames similar, so the ACF decays monotonically and its maximum
/// sits at the smallest allowed lag on every non-repetitive take — the
/// "period" would be the search floor, not a measurement. Only interior
/// local maxima rising at least [minProminence] above their neighbouring
/// valleys count; a take whose ACF has no such peak is *moving but not
/// repeating* and stays unmeasured.
///
/// Mean-centring is what stops a held pose from scoring 1.0: subtracting the
/// per-joint mean leaves a static take with almost no signal to correlate.
///
/// Units (M-O-23): the search bounds are declared in SECONDS and converted
/// per take using the take's own measured median frame interval — never an
/// assumed frame rate.
final class CyclePeriodEstimator {
  const CyclePeriodEstimator({
    this.minPeriodS = 0.4,
    this.maxPeriodS = 4.0,
    this.minPeriodicity = 0.5,
    this.minProminence = 0.08,
  });

  final double minPeriodS;
  final double maxPeriodS;

  /// Weakest ACF peak accepted as a period (harvest rig default carried over).
  final double minPeriodicity;

  /// Minimum rise over the higher neighbouring valley for a peak to count
  /// (M-C-25: a micro-bump on a decaying slope has a shallow uphill side and
  /// fails this).
  final double minProminence;

  CyclePeriodEstimate estimate(List<JointAngleVector> frames) {
    final int n = frames.length;
    if (n < 8) {
      return const CyclePeriodEstimate.unmeasured(
          'too few frames to search for a period');
    }

    // Measured median frame interval — frames are DERIVED from seconds here,
    // never the other way round.
    final List<int> dts = <int>[
      for (int i = 1; i < n; i++) frames[i].tUs - frames[i - 1].tUs,
    ]..sort();
    final int dtUs = dts[dts.length ~/ 2];
    if (dtUs <= 0) {
      return const CyclePeriodEstimate.unmeasured(
          'non-monotonic timestamps — frame interval cannot be measured');
    }

    final int lo = math.max(2, (minPeriodS * 1e6 / dtUs).round());
    // Segmentation needs at least two full cycles in the take, and so does
    // an honest phase search (CycleAligner refuses wrap-around) — so a
    // period beyond n/2 is unmeasurable by construction.
    final int hi = math.min((maxPeriodS * 1e6 / dtUs).round(), n ~/ 2);
    if (lo >= hi) {
      return const CyclePeriodEstimate.unmeasured(
          'take too short for the declared period range');
    }

    final int dim = frames.first.length;
    // Per-joint means over measurable cells; NaN cells contribute nothing
    // after centring instead of poisoning the correlation.
    final List<double> means = List<double>.filled(dim, 0);
    final List<int> counts = List<int>.filled(dim, 0);
    for (final JointAngleVector f in frames) {
      for (int d = 0; d < dim; d++) {
        final double v = f[d];
        if (v.isNaN) continue;
        means[d] += v;
        counts[d]++;
      }
    }
    for (int d = 0; d < dim; d++) {
      means[d] = counts[d] > 0 ? means[d] / counts[d] : 0;
    }
    final List<List<double>> c = <List<double>>[
      for (final JointAngleVector f in frames)
        <double>[
          for (int d = 0; d < dim; d++)
            f[d].isNaN ? 0 : f[d] - means[d],
        ],
    ];

    // Per-frame energy, prefix-summed so overlap normalisation is O(1)/lag.
    final List<double> frameEnergy = <double>[
      for (final List<double> f in c)
        f.fold(0, (double s, double v) => s + v * v),
    ];
    final double totalEnergy =
        frameEnergy.fold(0, (double s, double e) => s + e);
    if (totalEnergy < 1e-9) {
      return const CyclePeriodEstimate.unmeasured(
          'no motion signal — material is static');
    }
    final List<double> prefix = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + frameEnergy[i];
    }

    final List<int> lags = <int>[for (int l = lo; l <= hi; l++) l];
    final List<double> r = <double>[];
    for (final int lag in lags) {
      double num = 0;
      for (int t = 0; t < n - lag; t++) {
        final List<double> a = c[t];
        final List<double> b = c[t + lag];
        for (int d = 0; d < dim; d++) {
          num += a[d] * b[d];
        }
      }
      final double e1 = prefix[n - lag];
      final double e2 = prefix[n] - prefix[lag];
      final double denom = math.sqrt(e1 * e2);
      r.add(denom >= 1e-12 ? num / denom : 0.0);
    }

    double best = 0;
    int bestLag = 0;
    double bestProminence = 0;
    for (int k = 1; k < r.length - 1; k++) {
      if (!(r[k] > r[k - 1] && r[k] >= r[k + 1])) continue;
      int j = k;
      while (j > 0 && r[j - 1] < r[j]) {
        j--;
      }
      final double leftValley = r[j];
      j = k;
      while (j < r.length - 1 && r[j + 1] < r[j]) {
        j++;
      }
      final double rightValley = r[j];
      final double prominence = r[k] - math.max(leftValley, rightValley);
      if (prominence < minProminence) continue;
      if (r[k] > best) {
        best = r[k];
        bestLag = lags[k];
        bestProminence = prominence;
      }
    }

    if (bestLag == 0) {
      return const CyclePeriodEstimate.unmeasured(
          'moving but not repeating — no prominent ACF peak (M-C-25)');
    }
    if (best < minPeriodicity) {
      return CyclePeriodEstimate.unmeasured(
          'periodicity ${best.toStringAsFixed(2)} below '
          '$minPeriodicity — repetition too weak to assert a period');
    }
    return CyclePeriodEstimate.measured(
      periodFrames: bestLag,
      periodicity: best,
      prominence: bestProminence,
    );
  }
}
