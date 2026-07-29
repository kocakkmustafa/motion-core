import 'dart:math' as math;

import '../geometry/joint_angles.dart';
import '../geometry/vec3.dart';
import 'dtw.dart';
import 'similarity.dart';

/// Mirrors an angle vector: swaps left/right joints and flips the sign of
/// direction-valued angles.
///
/// Flexion angles are magnitudes and survive mirroring unchanged; orientation
/// and trunk-tilt angles are signed directions and negate, because reflecting
/// the image about a vertical axis turns an angle `θ` measured from the trunk
/// into `-θ`.
extension MirrorAngles on JointAngleVector {
  JointAngleVector mirrored() {
    final List<double> out = List<double>.filled(values.length, double.nan);
    for (int i = 0; i < specs.length; i++) {
      final JointSpec spec = specs[i];
      final String id = spec.id;
      String twin = id;
      if (id.startsWith('left_')) {
        twin = 'right_${id.substring(5)}';
      } else if (id.startsWith('right_')) {
        twin = 'left_${id.substring(6)}';
      }
      int source = i;
      if (twin != id) {
        for (int k = 0; k < specs.length; k++) {
          if (specs[k].id == twin) {
            source = k;
            break;
          }
        }
      }
      final double v = values[source];
      if (v.isNaN) continue;
      out[i] = spec.kind == AngleKind.flexion ? v : wrapPi(-v);
    }
    return JointAngleVector(tUs: tUs, values: out, specs: specs);
  }
}

/// One recorded performance of a technique, ready to be merged.
final class ReferenceTake {
  const ReferenceTake({
    required this.id,
    required this.frames,
    this.source = '',
  });

  final String id;
  final List<JointAngleVector> frames;

  /// Provenance — which recording this came from. Carried through to the
  /// canonical reference so any published claim can be traced back.
  final String source;

  ReferenceTake mirrored() => ReferenceTake(
        id: id,
        source: source,
        frames: frames
            .map((JointAngleVector f) => f.mirrored())
            .toList(growable: false),
      );
}

/// Circular statistics over a set of angles.
///
/// Plain means are wrong for angles: the average of `179°` and `-179°` is `0°`,
/// a pose nobody struck. Every aggregate here goes through the unit circle.
({double mean, double dispersion, int count}) circularStats(
  Iterable<double> anglesRad,
) {
  double sumSin = 0;
  double sumCos = 0;
  int n = 0;
  for (final double a in anglesRad) {
    if (a.isNaN) continue;
    sumSin += math.sin(a);
    sumCos += math.cos(a);
    n++;
  }
  if (n == 0) {
    return (mean: double.nan, dispersion: double.nan, count: 0);
  }
  final double mean = math.atan2(sumSin / n, sumCos / n);
  final double r = math.sqrt(sumSin * sumSin + sumCos * sumCos) / n;
  // Circular standard deviation. r near 1 means tight agreement; r near 0
  // means the takes disagree completely.
  final double dispersion =
      r >= 1.0 ? 0.0 : math.sqrt(-2 * math.log(r.clamp(1e-12, 1.0)));
  return (mean: mean, dispersion: dispersion, count: n);
}

/// Outcome of the global orientation assignment (M-F-48).
final class MirrorResolution {
  const MirrorResolution({
    required this.takes,
    required this.flippedIds,
    required this.confident,
    required this.runnerUpGap,
    required this.priorDisagreements,
    this.gapMeasured = true,
    this.searchDecisive = false,
  });

  final List<ReferenceTake> takes;
  final List<String> flippedIds;

  /// False when the best assignment beat its nearest distinct rival by less
  /// than the mirror margin. Consumers apply M-F-46 rule 7 (no side-dependent
  /// verdicts from an uncertain resolution) — after checking for degeneracy:
  /// a near-tie whose rival produces the *same* reference is not uncertainty.
  ///
  /// Only ever true on a *measured* basis: a real runner-up gap above the
  /// margin, or a caller-supplied direct measurement (prior). An earlier
  /// version encoded the fallback path's UNKNOWN gap as `2 × margin`, which
  /// made this flag unconditionally true exactly where it was unknowable —
  /// three instruments proved it (M-O-25: two pools returned the identical
  /// round 0.04000; the one pool small enough to be measured said false).
  final bool confident;

  /// Mean-per-pair cost gap between the best and runner-up assignments.
  ///
  /// NaN when [gapMeasured] is false — an unknown must read as unknown, not
  /// as a plausible number (the sentinel-above-margin encoding is how M-O-25
  /// happened).
  final double runnerUpGap;

  /// Whether [runnerUpGap] came from an exhaustive search (true) or the
  /// assignment came from the heuristic fallback whose rival cost is unknown
  /// (false). Honesty flags carry their basis, not just their verdict.
  final bool gapMeasured;

  /// Whether the mirror SEARCH itself was decisive — a measured runner-up
  /// gap above the margin, independent of any prior (M-J-09). [confident]
  /// conflates two bases: "a prior was trusted" and "the search separated
  /// the candidates". JabLab measured the confusion on real stance data:
  /// with a prior, `confident` is true while the underlying search sat at
  /// gap 0.0038 << margin 0.02 — a consumer reading `confident` as "the
  /// data resolved this" would be wrong. A flag carries its basis.
  final bool searchDecisive;

  /// Takes where a caller-supplied lead-side prior contradicted consensus.
  /// The prior wins (it is a direct measurement); the contradiction is
  /// reported because at small n it is the only visible symptom of a
  /// consensus that would have resolved wrongly.
  final List<String> priorDisagreements;
}

/// Thrown when the sources do not agree enough to distil a reference
/// (M-F-47): a count gate alone cannot see that 23° and 112° are both "in".
final class ReferenceAgreementError implements Exception {
  ReferenceAgreementError(this.deviationsDegById, this.toleranceDeg);

  /// Per-take mean angular deviation from the consensus, in degrees.
  final Map<String, double> deviationsDegById;
  final double toleranceDeg;

  @override
  String toString() {
    // An infinite deviation is not a huge angle — it means the take had no
    // measurable overlap with its peers (all cells NaN, or no peers at all).
    // Printing "Infinity°" would dress a structural gap as a number (L-143).
    final String detail = deviationsDegById.entries
        .map((MapEntry<String, double> e) => e.value.isFinite
            ? '${e.key}: ${e.value.toStringAsFixed(1)}°'
            : '${e.key}: no measurable overlap with peers')
        .join(', ');
    return 'ReferenceAgreementError(cluster within $toleranceDeg° too small '
        '— $detail)';
  }
}

/// Where a published tolerance number actually came from (G-050 / M-F-55).
enum ToleranceSource {
  /// Observed instructor disagreement — the only source that lets a consumer
  /// claim the tolerance is variance-derived (M-F-38).
  variance,

  /// The product floor bound — survivors agreed more tightly than the floor,
  /// so the number says nothing about disagreement.
  floor,

  /// The product ceiling bound — disagreement exceeded the cap; the joint is
  /// effectively unscored territory.
  ceiling,

  /// No usable measurements at this point.
  unmeasured,
}

/// A reference distilled from several real performances.
final class CanonicalReference {
  const CanonicalReference({
    required this.frames,
    required this.dispersion,
    required this.contributingTakes,
    required this.sources,
    required this.mirroredTakeIds,
    this.mirrorConfident = true,
    this.mirrorGapMeasured = true,
    this.mirrorSearchDecisive = false,
    this.excludedOutlierIds = const <String>[],
    this.priorDisagreements = const <String>[],
  });

  /// M-F-46 rule 7 input: whether the orientation assignment was decisive.
  final bool mirrorConfident;

  /// Basis of [mirrorConfident] — see [MirrorResolution.gapMeasured].
  final bool mirrorGapMeasured;

  /// Prior-independent search decisiveness — see
  /// [MirrorResolution.searchDecisive] (M-J-09).
  final bool mirrorSearchDecisive;

  /// Sources measured, named and *excluded* by the agreement gate (M-F-47) —
  /// reported rather than silently averaged into the consensus.
  final List<String> excludedOutlierIds;

  /// See [MirrorResolution.priorDisagreements].
  final List<String> priorDisagreements;

  /// Per-frame circular mean of the contributing takes.
  final List<JointAngleVector> frames;

  /// Per-frame, per-joint circular standard deviation in radians.
  ///
  /// The most valuable output here, and the thing a single reference recording
  /// can never provide: where many independent teachers do the same thing,
  /// that is the step; where they diverge, that is personal styling. Scoring a
  /// learner against the parts teachers themselves disagree on would penalise
  /// them for having a style.
  final List<List<double>> dispersion;

  final int contributingTakes;
  final List<String> sources;

  /// Takes that had to be flipped to agree with the rest.
  final List<String> mirroredTakeIds;

  int get length => frames.length;

  /// A tolerance derived from how much the teachers themselves varied.
  ///
  /// Free band tracks observed disagreement (floored, so a suspiciously
  /// unanimous joint still leaves room for measurement noise); the zero point
  /// scales with it. Joints nobody agrees on end up almost unscored, which is
  /// the honest outcome.
  Tolerance toleranceAt(
    int frameIndex,
    int jointIndex, {
    double freeFloorDeg = 8,
    double freeCeilingDeg = 45,
    double zeroMultiplier = 3.2,
  }) {
    final double sd = dispersion[frameIndex][jointIndex];
    final double freeDeg = sd.isNaN
        ? freeCeilingDeg
        : (sd * radToDeg).clamp(freeFloorDeg, freeCeilingDeg);
    return Tolerance.degrees(free: freeDeg, zeroAt: freeDeg * zeroMultiplier);
  }

  /// Which bound produced the number [toleranceAt] returned (G-050 / M-F-55).
  ///
  /// Measured on Gravita's first real reference: all nine joints' survivor
  /// dispersion (5.9–8.0°) sat BELOW the 8° floor, so every published
  /// tolerance was the floor wearing a variance-derived costume. The number
  /// is real either way — what changes is the claim a consumer may make:
  /// only [ToleranceSource.variance] measures instructor disagreement;
  /// `floor` is a product minimum, `ceiling` a product cap, `unmeasured`
  /// an admission. A reference whose joints are floor-bound cannot close a
  /// "tolerance is variance-derived" claim (G-014).
  ToleranceSource toleranceSourceAt(
    int frameIndex,
    int jointIndex, {
    double freeFloorDeg = 8,
    double freeCeilingDeg = 45,
  }) {
    final double sd = dispersion[frameIndex][jointIndex];
    if (sd.isNaN) return ToleranceSource.unmeasured;
    final double sdDeg = sd * radToDeg;
    if (sdDeg <= freeFloorDeg) return ToleranceSource.floor;
    if (sdDeg >= freeCeilingDeg) return ToleranceSource.ceiling;
    return ToleranceSource.variance;
  }

  /// Per joint: the share of measured frames where the floor binds.
  ///
  /// The artifact-level honesty number — `1.0` means the joint's published
  /// tolerance never once came from observed disagreement. Unmeasured
  /// frames are excluded from the denominator rather than diluting it.
  Map<String, double> floorBoundShare({double freeFloorDeg = 8}) {
    if (frames.isEmpty) return const <String, double>{};
    final List<JointSpec> specs = frames.first.specs;
    final Map<String, double> out = <String, double>{};
    for (int j = 0; j < specs.length; j++) {
      int measured = 0;
      int floored = 0;
      for (int f = 0; f < dispersion.length; f++) {
        final double sd = dispersion[f][j];
        if (sd.isNaN) continue;
        measured++;
        if (sd * radToDeg <= freeFloorDeg) floored++;
      }
      if (measured > 0) out[specs[j].id] = floored / measured;
    }
    return out;
  }

  /// Mean agreement across all joints of a frame, in `[0, 1]`.
  double agreementAt(int frameIndex) {
    final List<double> row = dispersion[frameIndex];
    double sum = 0;
    int n = 0;
    for (final double sd in row) {
      if (sd.isNaN) continue;
      // Map dispersion to a 0..1 agreement; one radian of spread is already
      // near-total disagreement for a technique reference.
      sum += math.exp(-sd);
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  /// Joints the teachers disagreed on so much that scoring them is dishonest.
  List<String> unreliableJoints({double sdThresholdDeg = 35}) {
    if (frames.isEmpty) return const <String>[];
    final List<JointSpec> specs = frames.first.specs;
    final List<String> out = <String>[];
    for (int j = 0; j < specs.length; j++) {
      double sum = 0;
      int n = 0;
      for (int f = 0; f < dispersion.length; f++) {
        final double sd = dispersion[f][j];
        if (sd.isNaN) continue;
        sum += sd;
        n++;
      }
      if (n == 0 || (sum / n) * radToDeg > sdThresholdDeg) {
        out.add(specs[j].id);
      }
    }
    return out;
  }
}

/// Distils many real performances of the same technique into one reference.
///
/// Built for a specific problem: recordings of real teachers arrive with no
/// shared clock, no shared tempo, and no agreement about which way round they
/// are facing — instructors habitually mirror themselves for the viewer, and
/// nothing in the video says so. Merging them therefore needs three things at
/// once: a common time base, a resolved handedness, and an aggregate that
/// respects the circular nature of angles.
final class ReferenceBuilder {
  const ReferenceBuilder({
    this.similarity = const AngularSimilarity(),
    this.dtw = const Dtw(),
    this.minTakes = 3,
    this.minSources = 3,
    this.mirrorMargin = 0.02,
  });

  final AngularSimilarity similarity;
  final Dtw dtw;

  /// Fewest takes that may produce a reference.
  ///
  /// Below this the dispersion estimate is meaningless, and a dispersion-derived
  /// tolerance built on two samples would be a confident number with nothing
  /// behind it.
  final int minTakes;

  /// Fewest *distinct sources* (instructors) that may produce a reference.
  ///
  /// [minTakes] counts repetitions; this counts people — and they answer
  /// different questions. Twelve takes from one instructor sail past the
  /// take gate yet carry zero information about *inter-instructor* variance,
  /// which is the only thing a dispersion-derived tolerance is made of
  /// (M-F-38): agreement across independent teachers is what separates "the
  /// technique" from "this teacher's habit". Both gates run. Set to 1 only
  /// for explicitly single-teacher prototypes, where the tolerance must be
  /// read as style, not consensus.
  final int minSources;

  /// How much better the flipped orientation must score before a take is
  /// mirrored. Near-ties are left alone rather than coin-flipped.
  final double mirrorMargin;

  static int? _dtUsOf(List<JointAngleVector> frames) =>
      Dtw.medianDtUs(<int>[for (final JointAngleVector f in frames) f.tUs]);

  double _distance(List<JointAngleVector> a, List<JointAngleVector> b) =>
      dtw
          .align(a.length, b.length,
              (int i, int j) => similarity.distance(a[i], b[j]),
              dtUs: _dtUsOf(b))
          .normalizedCost;

  /// Index of the take most similar to all the others — used as the time base.
  ///
  /// A medoid rather than the first take: whichever recording happens to be
  /// listed first should not decide the tempo and phrasing of the reference.
  int selectMedoid(List<ReferenceTake> takes) {
    int best = 0;
    double bestCost = double.infinity;
    for (int i = 0; i < takes.length; i++) {
      double total = 0;
      for (int j = 0; j < takes.length; j++) {
        if (i == j) continue;
        total += _distance(takes[i].frames, takes[j].frames);
      }
      if (total < bestCost) {
        bestCost = total;
        best = i;
      }
    }
    return best;
  }

  /// Decides, per take, whether it must be flipped to agree with the group —
  /// as a **global assignment problem**, not a sequence of local choices.
  ///
  /// The earlier version anchored every decision to a single medoid take.
  /// Choreia measured the failure mode of anchor/greedy schemes on real dance
  /// takes (M-F-48): with near-tie margins, per-take decisions accumulate an
  /// early coin-flip into the rest of the set, and the outcome depends on
  /// which take happens to lead — *"a consensus that depends on file order
  /// is not a consensus."* Here every relative-flip combination is scored by
  /// total pairwise disagreement and the best one wins; take 0 is pinned
  /// upright to break the global mirror symmetry (flipping everything is the
  /// same reference).
  ///
  /// A [prior] (M-J-06) short-circuits the search: when the caller measured
  /// handedness directly (lead foot, lead hand — geometric, per take), that
  /// measurement outranks consensus, because at small n a consensus that
  /// resolves wrongly is *silent* — arms disperse, legs stay coherent, and
  /// the result reads exactly like style variance. Consensus still runs and
  /// disagreements are reported, never hidden.
  MirrorResolution resolveMirroring(
    List<ReferenceTake> takes, {
    Map<String, bool>? prior,
  }) {
    if (takes.length < 2) {
      // One take has no rival assignment to lose to — "confident" is
      // vacuously true, but the gap was never MEASURED, and saying otherwise
      // is the exact M-O-25 shape (an unknowable reported as a number).
      return MirrorResolution(
        takes: takes,
        flippedIds: const <String>[],
        confident: true,
        runnerUpGap: double.infinity,
        priorDisagreements: const <String>[],
        gapMeasured: false,
        searchDecisive: false,
      );
    }

    final int n = takes.length;
    final List<ReferenceTake> mirroredTakes =
        takes.map((ReferenceTake t) => t.mirrored()).toList(growable: false);

    // Pair cost depends only on the RELATIVE flip: mirroring both takes is an
    // isometry of the angle representation. Two DTW runs per pair.
    final List<List<double>> costSame =
        List<List<double>>.generate(n, (_) => List<double>.filled(n, 0));
    final List<List<double>> costDiff =
        List<List<double>>.generate(n, (_) => List<double>.filled(n, 0));
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        costSame[i][j] = _distance(takes[i].frames, takes[j].frames);
        costDiff[i][j] =
            _distance(takes[i].frames, mirroredTakes[j].frames);
      }
    }
    final int pairs = n * (n - 1) ~/ 2;

    double totalFor(int mask) {
      double total = 0;
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          final bool same = ((mask >> i) & 1) == ((mask >> j) & 1);
          total += same ? costSame[i][j] : costDiff[i][j];
        }
      }
      return total;
    }

    int bestMask = 0;
    double bestTotal = double.infinity;
    double runnerUpTotal = double.infinity;

    // 18 takes = 2^17 masks × 153 pairs ≈ 20M cost adds — measured 777 ms
    // end-to-end (incl. pair-table DTW) on an M-class laptop, and this runs
    // at reference-build time, never in a frame loop. Raised from 12 after
    // M-O-26: the family's own per-pool quality target (≥12 accepted takes)
    // sat exactly on the old switch point, so every pool that MET the
    // quality bar simultaneously lost its measured mirror gap. Two
    // thresholds owned by different components collided without either
    // knowing.
    bool gapMeasured = true;
    if (n <= 18) {
      // Exhaustive over 2^(n-1) with bit 0 pinned to 0.
      for (int mask = 0; mask < (1 << n); mask += 2) {
        final double total = totalFor(mask);
        if (total < bestTotal) {
          runnerUpTotal = bestTotal;
          bestTotal = total;
          bestMask = mask;
        } else if (total < runnerUpTotal) {
          runnerUpTotal = total;
        }
      }
    } else {
      // Beyond exhaustive reach: anchor-based two-pass fallback. Each flip
      // clears a per-take margin, so applying the assignment is defensible —
      // but the GLOBAL runner-up cost is unknown, and it stays unknown in
      // the output (M-O-25): no sentinel, no plausible stand-in.
      List<ReferenceTake> current = List<ReferenceTake>.of(takes);
      for (int pass = 0; pass < 2; pass++) {
        final int anchor = selectMedoid(current);
        final List<JointAngleVector> ref = current[anchor].frames;
        current = List<ReferenceTake>.generate(current.length, (int i) {
          if (i == anchor) return current[i];
          final double asIs = _distance(ref, current[i].frames);
          final double flippedCost =
              _distance(ref, current[i].mirrored().frames);
          return (asIs - flippedCost) > mirrorMargin
              ? current[i].mirrored()
              : current[i];
        }, growable: false);
      }
      for (int i = 0; i < n; i++) {
        if (!identical(current[i], takes[i])) bestMask |= 1 << i;
      }
      bestTotal = totalFor(bestMask);
      runnerUpTotal = double.nan;
      gapMeasured = false;
    }

    // Mean-per-pair gap between best and best-distinct-runner-up. Below the
    // mirror margin the assignment is not trusted (M-F-46 rule 7) — though a
    // tiny gap can also mean *degeneracy* (two assignments producing the same
    // reference, Choreia's measured distinction); consumers decide with a
    // sensitivity probe, we report honestly.
    final double runnerUpGap = !gapMeasured
        ? double.nan
        : pairs == 0
            ? double.infinity
            : (runnerUpTotal - bestTotal) / pairs;

    // The search fixes only the RELATIVE assignment; the absolute convention
    // is ours to pick (Choreia's lesson: the whole set mirrored together is
    // the same reference). Two policies, both deliberate:
    //  * decisive result → flip the MINORITY: fewer transformed takes, and
    //    the reference keeps the handedness most instructors actually showed;
    //  * near-tie (gap ≤ margin) → flip NOTHING: an ambiguous resolution must
    //    not transform anyone's take on the strength of a coin flip — the
    //    old guard behavior, now also reported via [MirrorResolution.confident].
    // NaN-aware on purpose: an UNMEASURED gap is not a near-tie — the
    // fallback's per-take flips each cleared their own margin, so they are
    // applied; only the *confidence claim* is withheld. A measured near-tie
    // still flips nothing (a coin flip must not transform anyone's take).
    int chosenMask;
    if (gapMeasured && runnerUpGap <= mirrorMargin) {
      chosenMask = 0;
    } else {
      int popcount = 0;
      for (int i = 0; i < n; i++) {
        popcount += (bestMask >> i) & 1;
      }
      chosenMask =
          popcount * 2 > n ? (~bestMask & ((1 << n) - 1)) : bestMask;
    }
    final List<String> priorDisagreements = <String>[];
    if (prior != null && prior.isNotEmpty) {
      int priorMask = 0;
      for (int i = 0; i < n; i++) {
        if (prior[takes[i].id] ?? false) priorMask |= 1 << i;
      }
      // The prior is absolute; consensus is relative (bit 0 pinned). Compare
      // in the frame where they agree on take 0.
      final int consensusAbs =
          ((priorMask & 1) == 1) ? (~bestMask & ((1 << n) - 1)) : bestMask;
      for (int i = 0; i < n; i++) {
        if (((priorMask >> i) & 1) != ((consensusAbs >> i) & 1)) {
          priorDisagreements.add(takes[i].id);
        }
      }
      chosenMask = priorMask;
    }

    final List<ReferenceTake> resolved = List<ReferenceTake>.generate(
      n,
      (int i) => ((chosenMask >> i) & 1) == 1 ? mirroredTakes[i] : takes[i],
      growable: false,
    );
    return MirrorResolution(
      takes: resolved,
      flippedIds: <String>[
        for (int i = 0; i < n; i++)
          if (((chosenMask >> i) & 1) == 1) takes[i].id,
      ],
      confident:
          prior != null || (gapMeasured && runnerUpGap > mirrorMargin),
      searchDecisive: gapMeasured && runnerUpGap > mirrorMargin,
      runnerUpGap: runnerUpGap,
      gapMeasured: gapMeasured,
      priorDisagreements: priorDisagreements,
    );
  }

  /// Merges takes into a canonical reference.
  ///
  /// **Gate scope (M-J-08):** the agreement gate is a *take-level, coarse*
  /// "same movement?" check — it is NOT the scoring authority. Which joints
  /// may score is decided per joint by measured dispersion (M-F-41/46), on
  /// the app side. On style-heavy references (a static stance whose arms
  /// legitimately spread 36° while legs agree at 8°) the take-level median
  /// can over-block; callers may widen [clusterToleranceDeg] for such
  /// references while keeping per-joint authority strict. A finer per-joint
  /// gate was attempted and measured to be structurally blind to
  /// different-movement outliers (each take finds SOME agreeing joints);
  /// the design remains open in the family ledger — this doc records the
  /// triangle so nobody re-walks it: different-movement ⊗ style ⊗ per-joint
  /// authority cannot all be served by one take-level statistic.
  ///
  /// Throws [ArgumentError] below [minTakes] and [ReferenceAgreementError]
  /// when fewer than [minTakes] sources agree within [clusterToleranceDeg]
  /// (M-F-47: the count gate alone cannot see that 23° and 112° are both
  /// "in" — a reference distilled from that range sets a meaningless target).
  /// Outliers outside a still-sufficient cluster are excluded *and named*,
  /// never silently averaged.
  CanonicalReference build(
    List<ReferenceTake> rawTakes, {
    Map<String, bool>? leadSidePrior,
    double clusterToleranceDeg = 14,
  }) {
    // Structural impossibilities are refused up front, with the real reason
    // — never left to surface deep in consensus math as a crash or as a
    // convincing-but-wrong gate verdict (L-143 and its review):
    //  - an empty pool has no medoid to select;
    //  - a single take has no peers, so leave-one-out deviation is +∞ for
    //    every input and the M-F-47 gate reports "no measurable overlap with
    //    peers", which reads like a measurement finding and gets believed.
    if (rawTakes.isEmpty) {
      throw ArgumentError('cannot build a reference from zero takes');
    }
    if (rawTakes.length == 1) {
      throw ArgumentError(
        'a single take has no peers — consensus and dispersion cannot be '
        'measured, for any gate setting; even a single-teacher prototype '
        'needs at least 2 takes from that teacher',
      );
    }
    // A take with zero frames cannot participate in alignment at all — DTW
    // against it yields an empty warp path and the crash surfaces frames
    // deep inside consensus math, where it reads as a gate refusal (L-143).
    // Refuse here, by name, before any count is computed over it.
    final List<String> frameless = <String>[
      for (final ReferenceTake t in rawTakes)
        if (t.frames.isEmpty) t.id,
    ];
    if (frameless.isNotEmpty) {
      throw ArgumentError(
        'takes with zero measurable frames cannot be aligned: '
        '${frameless.join(', ')} — every frame was dropped upstream '
        '(undetected or gated); exclude them by name before building',
      );
    }
    if (rawTakes.length < minTakes) {
      throw ArgumentError(
        'need at least $minTakes takes to estimate dispersion, '
        'got ${rawTakes.length}',
      );
    }
    final Set<String> rawSources =
        rawTakes.map((ReferenceTake t) => t.source).toSet();
    if (rawSources.length < minSources) {
      throw ArgumentError(
        'need takes from at least $minSources distinct sources — tolerance '
        'derives from inter-instructor variance, and ${rawTakes.length} takes '
        'from ${rawSources.length} source(s) cannot measure it (M-F-38); '
        'pass minSources: 1 only for an explicit single-teacher prototype',
      );
    }

    final MirrorResolution resolution =
        resolveMirroring(rawTakes, prior: leadSidePrior);
    List<ReferenceTake> takes = resolution.takes;
    final List<String> flipped = resolution.flippedIds;

    // ---- M-F-47 agreement gate --------------------------------------------
    // Per-take mean angular deviation from the (provisional) consensus.
    final Map<String, double> deviationDeg = _deviationsFromConsensus(takes);
    final List<ReferenceTake> cluster = <ReferenceTake>[
      for (final ReferenceTake t in takes)
        if (deviationDeg[t.id]! <= clusterToleranceDeg) t,
    ];
    if (cluster.length < minTakes) {
      throw ReferenceAgreementError(deviationDeg, clusterToleranceDeg);
    }
    // The agreement gate can silently cost a *person*, not just a take: if
    // every take an instructor contributed fell outside the cluster, the
    // survivors may still satisfy the take count while the consensus has
    // narrowed to fewer teachers than [minSources] demands.
    if (cluster.map((ReferenceTake t) => t.source).toSet().length <
        minSources) {
      throw ReferenceAgreementError(deviationDeg, clusterToleranceDeg);
    }
    final List<String> excluded = <String>[
      for (final ReferenceTake t in takes)
        if (deviationDeg[t.id]! > clusterToleranceDeg) t.id,
    ];
    takes = cluster;

    final int medoid = selectMedoid(takes);
    final List<JointAngleVector> base = takes[medoid].frames;
    final List<JointSpec> specs = base.first.specs;

    // Warp every take onto the medoid's time base.
    final List<List<JointAngleVector>> aligned = <List<JointAngleVector>>[];
    for (int t = 0; t < takes.length; t++) {
      if (t == medoid) {
        aligned.add(base);
        continue;
      }
      final List<JointAngleVector> other = takes[t].frames;
      final DtwResult r = dtw.align(base.length, other.length,
          (int i, int j) => similarity.distance(base[i], other[j]),
          dtUs: _dtUsOf(other));
      aligned.add(List<JointAngleVector>.generate(
        base.length,
        (int i) => other[r.refToLearner[i]],
        growable: false,
      ));
    }

    final List<JointAngleVector> mean = <JointAngleVector>[];
    final List<List<double>> dispersion = <List<double>>[];

    for (int f = 0; f < base.length; f++) {
      final List<double> meanRow = List<double>.filled(specs.length, double.nan);
      final List<double> sdRow = List<double>.filled(specs.length, double.nan);
      for (int j = 0; j < specs.length; j++) {
        final ({double mean, double dispersion, int count}) stats =
            circularStats(aligned.map((List<JointAngleVector> t) => t[f][j]));
        // A joint only counts when most takes actually measured it; otherwise
        // the "consensus" is one lucky recording.
        if (stats.count * 2 >= takes.length) {
          meanRow[j] = stats.mean;
          sdRow[j] = stats.dispersion;
        }
      }
      mean.add(JointAngleVector(tUs: base[f].tUs, values: meanRow, specs: specs));
      dispersion.add(sdRow);
    }

    return CanonicalReference(
      frames: mean,
      dispersion: dispersion,
      contributingTakes: takes.length,
      sources: takes.map((ReferenceTake t) => t.source).toList(growable: false),
      mirroredTakeIds: flipped,
      mirrorConfident: resolution.confident,
      mirrorGapMeasured: resolution.gapMeasured,
      mirrorSearchDecisive: resolution.searchDecisive,
      excludedOutlierIds: excluded,
      priorDisagreements: resolution.priorDisagreements,
    );
  }

  /// Mean per-take angular deviation from the group consensus, in degrees.
  ///
  /// Alignment-aware: each take is warped onto the medoid's time base first,
  /// so a slower demonstration of the same movement does not read as
  /// disagreement.
  Map<String, double> _deviationsFromConsensus(List<ReferenceTake> takes) {
    final int medoid = selectMedoid(takes);
    final List<JointAngleVector> base = takes[medoid].frames;
    final List<List<JointAngleVector>> aligned = <List<JointAngleVector>>[
      for (int t = 0; t < takes.length; t++)
        t == medoid
            ? base
            : (() {
                final DtwResult r = dtw.align(
                    base.length,
                    takes[t].frames.length,
                    (int i, int j) =>
                        similarity.distance(base[i], takes[t].frames[j]),
                    dtUs: _dtUsOf(takes[t].frames));
                return List<JointAngleVector>.generate(base.length,
                    (int i) => takes[t].frames[r.refToLearner[i]],
                    growable: false);
              })(),
    ];

    final int jointCount = base.first.specs.length;
    final Map<String, double> out = <String, double>{};
    for (int t = 0; t < takes.length; t++) {
      // Per-joint time-averaged deviation first, then the MEDIAN across
      // joints. The choice of robust statistic carries the rule's meaning:
      // a take performing a *different movement* deviates on most joints
      // (median high → excluded), while a take *styling* a minority of
      // joints — the variance the family turns into tolerance, never into
      // exclusion — cannot move the median. A grand mean would dilute the
      // first case (L-113's single-number trap); a high percentile would
      // punish the second.
      final List<double> perJoint = <double>[];
      for (int j = 0; j < jointCount; j++) {
        double sum = 0;
        int n = 0;
        for (int f = 0; f < base.length; f++) {
          // Consensus per cell, excluding the take under test so its own
          // outlierhood cannot drag the consensus toward itself.
          final List<double> others = <double>[
            for (int u = 0; u < takes.length; u++)
              if (u != t) aligned[u][f][j],
          ];
          final ({double mean, double dispersion, int count}) stats =
              circularStats(others);
          final double own = aligned[t][f][j];
          if (own.isNaN || stats.count == 0) continue;
          sum += wrapPi(own - stats.mean).abs();
          n++;
        }
        if (n > 0) perJoint.add(sum / n);
      }
      if (perJoint.isEmpty) {
        out[takes[t].id] = double.infinity;
        continue;
      }
      perJoint.sort();
      final double median = perJoint[perJoint.length ~/ 2];
      out[takes[t].id] = median * radToDeg;
    }
    return out;
  }
}
