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

/// A reference distilled from several real performances.
final class CanonicalReference {
  const CanonicalReference({
    required this.frames,
    required this.dispersion,
    required this.contributingTakes,
    required this.sources,
    required this.mirroredTakeIds,
  });

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

  /// How much better the flipped orientation must score before a take is
  /// mirrored. Near-ties are left alone rather than coin-flipped.
  final double mirrorMargin;

  double _distance(List<JointAngleVector> a, List<JointAngleVector> b) =>
      dtw.align(a.length, b.length,
          (int i, int j) => similarity.distance(a[i], b[j])).normalizedCost;

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

  /// Decides, per take, whether it must be flipped to agree with the group.
  ///
  /// No outside knowledge of handedness is needed or available: the question is
  /// resolved by consensus, by asking which assignment makes the group agree
  /// with itself most. Two passes, because the first pass' anchor may itself
  /// have been the mirrored one.
  List<ReferenceTake> resolveMirroring(List<ReferenceTake> takes) {
    if (takes.length < 2) return takes;
    List<ReferenceTake> current = List<ReferenceTake>.of(takes);

    for (int pass = 0; pass < 2; pass++) {
      final int anchor = selectMedoid(current);
      final List<JointAngleVector> ref = current[anchor].frames;
      current = List<ReferenceTake>.generate(current.length, (int i) {
        if (i == anchor) return current[i];
        final ReferenceTake asIs = current[i];
        final ReferenceTake flipped = asIs.mirrored();
        final double costAsIs = _distance(ref, asIs.frames);
        final double costFlipped = _distance(ref, flipped.frames);
        return (costAsIs - costFlipped) > mirrorMargin ? flipped : asIs;
      }, growable: false);
    }
    return current;
  }

  /// Merges takes into a canonical reference.
  ///
  /// Throws [ArgumentError] when given fewer than [minTakes].
  CanonicalReference build(List<ReferenceTake> rawTakes) {
    if (rawTakes.length < minTakes) {
      throw ArgumentError(
        'need at least $minTakes takes to estimate dispersion, '
        'got ${rawTakes.length}',
      );
    }

    final List<ReferenceTake> takes = resolveMirroring(rawTakes);
    final List<String> flipped = <String>[
      for (int i = 0; i < takes.length; i++)
        if (!identical(takes[i], rawTakes[i])) takes[i].id,
    ];

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
          (int i, int j) => similarity.distance(base[i], other[j]));
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
    );
  }
}
