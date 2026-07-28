import 'dart:math' as math;

import 'dtw.dart';

/// Result of aligning two takes of *periodic* material (M-C-18).
final class CycleAlignment {
  const CycleAlignment({
    required this.resolved,
    required this.phaseOffset,
    required this.phaseMargin,
    required this.normalizedCost,
    required this.dtw,
    required this.reason,
    this.secondCycleCost,
  });

  const CycleAlignment.undetermined(String why)
      : resolved = false,
        phaseOffset = 0,
        phaseMargin = 0,
        normalizedCost = 1.0,
        dtw = null,
        secondCycleCost = null,
        reason = why;

  /// Whether the phase search produced a trustworthy winner.
  ///
  /// False is a verdict of "undetermined", never of "bad": ambiguous material
  /// (a near-constant hold, a phase-symmetric wiggle) gives every candidate
  /// phase the same cost, and picking one anyway would silently compare
  /// mismatched moments — the exact failure this class exists to prevent.
  final bool resolved;

  /// Learner-frame offset at which the learner's cycle best matches the
  /// reference cycle's start.
  final int phaseOffset;

  /// Cost gap between the best phase and the best *distant* competitor,
  /// normalised like the cost itself. Small margin = ambiguous phase.
  final double phaseMargin;

  /// Cost of the winning cycle-to-cycle alignment (same units as [Dtw]).
  final double normalizedCost;

  /// The winning per-cycle alignment, for timing feedback. Null when
  /// unresolved.
  final DtwResult? dtw;

  /// Cost of re-checking the winning phase against the learner's *next*
  /// cycle, when one exists. A second cycle that disagrees wildly with the
  /// first says the material was not actually periodic at this period.
  final double? secondCycleCost;

  final String reason;

  double get similarity =>
      resolved ? (1.0 - normalizedCost).clamp(0.0, 1.0) : 0.0;
}

/// Cycle-aware alignment for periodic movement (M-C-18, family rule M-F-21).
///
/// Fixed-endpoint DTW is the wrong tool for looped material: two recordings
/// of the same step loop legitimately start at different points in the cycle,
/// and forcing `(0,0)` and `(n-1,m-1)` to match imposes a bad alignment no
/// band width can repair (measured on real harvest takes: costs pinned at
/// ~0.16 with mirror margins of ±0.002 — pure noise). The honest procedure is
/// what a human does: take one repetition, find where in the other take that
/// repetition begins, and compare repetition against repetition.
///
/// This class does exactly that: a phase search over one learner period,
/// each candidate scored with the family's banded, park-resistant [Dtw] over
/// a single cycle — where fixed endpoints are *correct*, because the caller
/// asserted the period. Periods come from the caller (the harvest side
/// already measures them via autocorrelation); this class never guesses them.
final class CycleAligner {
  const CycleAligner({
    this.dtw = const Dtw(bandRadius: 8, minBandRadius: 3),
    this.phaseStep = 1,
    this.minPhaseMargin = 0.02,
  });

  /// Per-cycle aligner. The default corridor is deliberately tighter than the
  /// long-form default: within a single asserted cycle, drift beyond a few
  /// frames *is* the signal, not noise to be absorbed.
  final Dtw dtw;

  /// Phase-search stride in frames. 1 = exhaustive over one period.
  final int phaseStep;

  /// Minimum best-vs-runner-up cost gap for the phase to count as resolved.
  ///
  /// The runner-up is the best candidate at least an eighth of a period away
  /// from the winner — adjacent offsets always score similarly and prove
  /// nothing about ambiguity.
  final double minPhaseMargin;

  /// Align one reference cycle against a periodic learner sequence.
  ///
  /// [refStart] is where the reference's representative cycle begins;
  /// [refPeriod] and [learnerPeriod] are the asserted cycle lengths in
  /// frames; [learnerLen] is the learner sequence length; [cost] is indexed
  /// over the *full* sequences, exactly like [Dtw.align]'s.
  CycleAlignment align({
    required int refStart,
    required int refPeriod,
    required int learnerLen,
    required int learnerPeriod,
    required PairCost cost,
  }) {
    if (refPeriod < 4 || learnerPeriod < 4) {
      return const CycleAlignment.undetermined(
          'period too short to align (< 4 frames)');
    }
    // Phase search needs every window [s, s+period) for s in [0, period) to
    // exist without wrap-around: real recordings are finite, and wrapping
    // would stitch the learner's end onto their beginning as if it were
    // motion. Two full cycles is the minimum honest requirement.
    if (learnerLen < 2 * learnerPeriod) {
      return const CycleAlignment.undetermined(
          'learner sequence shorter than two cycles — phase cannot be '
          'searched without wrap-around');
    }

    double bestCost = double.infinity;
    int bestPhase = 0;
    DtwResult? bestDtw;
    final List<double> costs =
        List<double>.filled(learnerPeriod, double.infinity);

    for (int s = 0; s < learnerPeriod; s += phaseStep) {
      final DtwResult r = dtw.align(
        refPeriod,
        learnerPeriod,
        (int i, int j) => cost(refStart + i, s + j),
      );
      costs[s] = r.normalizedCost;
      if (r.normalizedCost < bestCost) {
        bestCost = r.normalizedCost;
        bestPhase = s;
        bestDtw = r;
      }
    }

    if (bestDtw == null || bestCost.isInfinite) {
      return const CycleAlignment.undetermined(
          'no candidate phase produced a finite alignment');
    }

    // Runner-up must be a genuinely different phase, not the winner's
    // neighbour.
    final int separation = math.max(1, learnerPeriod ~/ 8);
    double runnerUp = double.infinity;
    for (int s = 0; s < learnerPeriod; s += phaseStep) {
      final int dist = math.min(
          (s - bestPhase).abs(), learnerPeriod - (s - bestPhase).abs());
      if (dist < separation) continue;
      if (costs[s] < runnerUp) runnerUp = costs[s];
    }
    final double margin =
        runnerUp.isInfinite ? 0.0 : (runnerUp - bestCost);

    // Stability probe: the same phase, one cycle later. Disagreement here
    // means the asserted period does not describe the material.
    double? secondCost;
    final int secondStart = bestPhase + learnerPeriod;
    if (secondStart + learnerPeriod <= learnerLen) {
      secondCost = dtw
          .align(
            refPeriod,
            learnerPeriod,
            (int i, int j) => cost(refStart + i, secondStart + j),
          )
          .normalizedCost;
    }

    if (margin < minPhaseMargin) {
      return CycleAlignment(
        resolved: false,
        phaseOffset: bestPhase,
        phaseMargin: margin,
        normalizedCost: bestCost,
        dtw: bestDtw,
        secondCycleCost: secondCost,
        reason: 'phase ambiguous: margin ${margin.toStringAsFixed(4)} < '
            '$minPhaseMargin — material may be static or phase-symmetric',
      );
    }

    return CycleAlignment(
      resolved: true,
      phaseOffset: bestPhase,
      phaseMargin: margin,
      normalizedCost: bestCost,
      dtw: bestDtw,
      secondCycleCost: secondCost,
      reason: 'ok',
    );
  }
}
