import '../geometry/joint_angles.dart';
import '../geometry/vec3.dart';

/// A graded tolerance band: full credit inside [free], no credit beyond
/// [zeroAt], smoothly interpolated in between.
///
/// Preferred over a Gaussian because both numbers are directly meaningful to
/// whoever authors or reviews a rule set ("12 degrees is fine, 55 is a
/// different move"), and because the same two numbers are what we can honestly
/// show a user when explaining a score. An opaque sigma is neither.
final class Tolerance {
  const Tolerance({required this.free, required this.zeroAt})
      : assert(zeroAt > free, 'zeroAt must exceed free');

  /// Deviation that still earns a similarity of 1.0.
  final double free;

  /// Deviation at which similarity reaches 0.0.
  final double zeroAt;

  /// Degrees-based constructor for angular tolerances.
  factory Tolerance.degrees({required double free, required double zeroAt}) =>
      Tolerance(free: free * degToRad, zeroAt: zeroAt * degToRad);

  /// Default angular tolerance for beginner-level whole-body comparison.
  ///
  /// Deliberately generous: the pose model's own joint noise is a real part of
  /// the measured deviation, so a tight band would score the tracker, not the
  /// dancer. Tightening happens per level, in versioned config — never as a
  /// hidden constant.
  static final Tolerance angleDefault =
      Tolerance.degrees(free: 12, zeroAt: 55);

  /// Torso-relative distance tolerance for position similarity.
  static const Tolerance positionDefault = Tolerance(free: 0.06, zeroAt: 0.35);

  double similarity(double deviation) {
    final double d = deviation.abs();
    if (d <= free) return 1.0;
    if (d >= zeroAt) return 0.0;
    final double t = (d - free) / (zeroAt - free);
    // Smoothstep: zero derivative at both ends, so a score does not visibly
    // jitter when a joint hovers right at the edge of the band.
    return 1.0 - (t * t * (3 - 2 * t));
  }
}

/// Per-joint contribution to a similarity result.
final class JointScore {
  const JointScore({
    required this.id,
    required this.similarity,
    required this.deviation,
    required this.measured,
    required this.weight,
  });

  final String id;
  final double similarity;

  /// Absolute deviation in radians (angles) or torso units (positions).
  final double deviation;

  /// False when the angle was unmeasurable — such joints are excluded from the
  /// score rather than counted as mismatches.
  final bool measured;

  final double weight;

  double get deviationDegrees => deviation * radToDeg;

  @override
  String toString() => measured
      ? '$id: ${(similarity * 100).toStringAsFixed(0)}% '
          '(${deviationDegrees.toStringAsFixed(1)}°)'
      : '$id: unmeasured';
}

/// Outcome of comparing one learner pose against one reference pose.
final class PoseSimilarityResult {
  const PoseSimilarityResult({
    required this.score,
    required this.coverage,
    required this.joints,
  });

  /// Weighted mean similarity over *measured* joints, in `[0, 1]`.
  final double score;

  /// Fraction of the requested joints that could actually be measured.
  ///
  /// A high score at low coverage is not a good performance — it is a mostly
  /// unobserved one. Callers must gate on coverage before showing a score;
  /// [isReportable] encodes the family's default bar.
  final double coverage;

  final List<JointScore> joints;

  /// Worst measured joint — the seed of the single spoken correction.
  JointScore? get worst {
    JointScore? out;
    for (final JointScore j in joints) {
      if (!j.measured) continue;
      if (out == null || j.similarity < out.similarity) out = j;
    }
    return out;
  }

  bool isReportable({double minCoverage = 0.6}) => coverage >= minCoverage;

  @override
  String toString() =>
      'PoseSimilarity(score=${(score * 100).toStringAsFixed(1)}%, '
      'coverage=${(coverage * 100).toStringAsFixed(0)}%)';
}

/// Joint Angular Similarity — the proportion-invariant comparison the family
/// scores on.
///
/// Reference: joint-angle similarity scoring for dance pose evaluation
/// (JPSS/JASS family of formulas), reimplemented here from the published
/// definition; no reference implementation was available to depend on.
final class AngularSimilarity {
  const AngularSimilarity({Tolerance? tolerance, this.perJointTolerance = const <String, Tolerance>{}})
      : _tolerance = tolerance;

  final Tolerance? _tolerance;

  /// Overrides for individual joints, e.g. a tighter band on the knees for a
  /// style where knee bend is the defining feature.
  final Map<String, Tolerance> perJointTolerance;

  Tolerance get defaultTolerance => _tolerance ?? Tolerance.angleDefault;

  Tolerance toleranceFor(String jointId) =>
      perJointTolerance[jointId] ?? defaultTolerance;

  PoseSimilarityResult compare(
    JointAngleVector reference,
    JointAngleVector learner,
  ) {
    assert(reference.specs.length == learner.specs.length,
        'angle vectors must share a spec list');

    final List<JointScore> scores = <JointScore>[];
    double weighted = 0;
    double weightSum = 0;
    double measurable = 0;

    for (int i = 0; i < reference.specs.length; i++) {
      final JointSpec spec = reference.specs[i];
      final double r = reference.values[i];
      final double l = learner.values[i];
      final bool measured = !r.isNaN && !l.isNaN;

      if (!measured) {
        scores.add(JointScore(
          id: spec.id,
          similarity: 0,
          deviation: double.nan,
          measured: false,
          weight: spec.weight,
        ));
        continue;
      }

      // Orientation and trunk-tilt angles are circular: 179° and -179° are two
      // degrees apart, not 358.
      final double deviation = spec.kind == AngleKind.flexion
          ? (r - l).abs()
          : angleDelta(r, l);

      final double sim = toleranceFor(spec.id).similarity(deviation);
      weighted += sim * spec.weight;
      weightSum += spec.weight;
      measurable += 1;

      scores.add(JointScore(
        id: spec.id,
        similarity: sim,
        deviation: deviation,
        measured: true,
        weight: spec.weight,
      ));
    }

    return PoseSimilarityResult(
      score: weightSum > 0 ? weighted / weightSum : 0,
      coverage: reference.specs.isEmpty ? 0 : measurable / reference.specs.length,
      joints: scores,
    );
  }

  /// Distance in `[0, 1]` — the cost function handed to DTW.
  double distance(JointAngleVector reference, JointAngleVector learner) =>
      1.0 - compare(reference, learner).score;
}
