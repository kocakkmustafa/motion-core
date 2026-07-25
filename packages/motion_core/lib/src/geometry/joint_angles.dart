import '../pose/landmark_index.dart';
import 'normalization.dart';
import 'vec3.dart';

/// What a [JointSpec] measures.
enum AngleKind {
  /// Interior angle at a vertex — "how bent is this joint".
  flexion,

  /// Direction of a segment relative to the trunk — "where is this limb
  /// pointing". Flexion alone cannot distinguish an arm held out to the side
  /// from the same arm held in front: both have an identical elbow angle. For
  /// dance, where limb placement in space *is* the content, orientation is not
  /// optional.
  orientation,

  /// Trunk tilt relative to image vertical.
  trunkTilt,
}

/// Definition of one measurable angle.
final class JointSpec {
  const JointSpec({
    required this.id,
    required this.kind,
    required this.a,
    required this.b,
    this.c = -1,
    this.weight = 1.0,
  });

  final String id;
  final AngleKind kind;

  /// For [AngleKind.flexion]: the three landmarks, vertex at [b].
  /// For [AngleKind.orientation]: the segment runs from [a] to [b].
  final int a;
  final int b;
  final int c;

  /// Relative importance when aggregating into a similarity score.
  final double weight;

  /// Landmarks this angle depends on — used to route confidence gating.
  List<int> get requiredLandmarks =>
      kind == AngleKind.flexion ? <int>[a, b, c] : <int>[a, b];

  JointSpec withWeight(double w) => JointSpec(
        id: id,
        kind: kind,
        a: a,
        b: b,
        c: c,
        weight: w,
      );
}

/// The family's standard angle sets.
///
/// Rule sets reference these by id, so a change to the skeleton contract shows
/// up as a compile error rather than as a silently different score.
abstract final class StandardJoints {
  // ---- flexion (the classic eight) -------------------------------------
  static const JointSpec leftElbow = JointSpec(
      id: 'left_elbow', kind: AngleKind.flexion, a: Lm.leftShoulder, b: Lm.leftElbow, c: Lm.leftWrist);
  static const JointSpec rightElbow = JointSpec(
      id: 'right_elbow', kind: AngleKind.flexion, a: Lm.rightShoulder, b: Lm.rightElbow, c: Lm.rightWrist);
  static const JointSpec leftShoulder = JointSpec(
      id: 'left_shoulder', kind: AngleKind.flexion, a: Lm.leftElbow, b: Lm.leftShoulder, c: Lm.leftHip);
  static const JointSpec rightShoulder = JointSpec(
      id: 'right_shoulder', kind: AngleKind.flexion, a: Lm.rightElbow, b: Lm.rightShoulder, c: Lm.rightHip);
  static const JointSpec leftHip = JointSpec(
      id: 'left_hip', kind: AngleKind.flexion, a: Lm.leftShoulder, b: Lm.leftHip, c: Lm.leftKnee);
  static const JointSpec rightHip = JointSpec(
      id: 'right_hip', kind: AngleKind.flexion, a: Lm.rightShoulder, b: Lm.rightHip, c: Lm.rightKnee);
  static const JointSpec leftKnee = JointSpec(
      id: 'left_knee', kind: AngleKind.flexion, a: Lm.leftHip, b: Lm.leftKnee, c: Lm.leftAnkle);
  static const JointSpec rightKnee = JointSpec(
      id: 'right_knee', kind: AngleKind.flexion, a: Lm.rightHip, b: Lm.rightKnee, c: Lm.rightAnkle);

  // ---- orientation (trunk-relative limb direction) ----------------------
  static const JointSpec leftUpperArm = JointSpec(
      id: 'left_upper_arm', kind: AngleKind.orientation, a: Lm.leftShoulder, b: Lm.leftElbow);
  static const JointSpec rightUpperArm = JointSpec(
      id: 'right_upper_arm', kind: AngleKind.orientation, a: Lm.rightShoulder, b: Lm.rightElbow);
  static const JointSpec leftForearm = JointSpec(
      id: 'left_forearm', kind: AngleKind.orientation, a: Lm.leftElbow, b: Lm.leftWrist);
  static const JointSpec rightForearm = JointSpec(
      id: 'right_forearm', kind: AngleKind.orientation, a: Lm.rightElbow, b: Lm.rightWrist);
  static const JointSpec leftThigh = JointSpec(
      id: 'left_thigh', kind: AngleKind.orientation, a: Lm.leftHip, b: Lm.leftKnee);
  static const JointSpec rightThigh = JointSpec(
      id: 'right_thigh', kind: AngleKind.orientation, a: Lm.rightHip, b: Lm.rightKnee);
  static const JointSpec leftShin = JointSpec(
      id: 'left_shin', kind: AngleKind.orientation, a: Lm.leftKnee, b: Lm.leftAnkle);
  static const JointSpec rightShin = JointSpec(
      id: 'right_shin', kind: AngleKind.orientation, a: Lm.rightKnee, b: Lm.rightAnkle);

  /// Trunk tilt against image vertical.
  ///
  /// Weighted low by default: unlike the trunk-relative angles, this one moves
  /// when the *phone* is tilted, so it carries camera error as well as body
  /// information.
  static const JointSpec trunkTilt =
      JointSpec(id: 'trunk_tilt', kind: AngleKind.trunkTilt, a: -1, b: -1, weight: 0.5);

  /// Eight flexion angles — the JASS-style baseline, proportion-invariant by
  /// construction (an angle has no units to scale).
  static const List<JointSpec> flexionEight = <JointSpec>[
    leftElbow, rightElbow, leftShoulder, rightShoulder,
    leftHip, rightHip, leftKnee, rightKnee,
  ];

  static const List<JointSpec> orientationEight = <JointSpec>[
    leftUpperArm, rightUpperArm, leftForearm, rightForearm,
    leftThigh, rightThigh, leftShin, rightShin,
  ];

  /// Flexion + orientation + trunk tilt: the default feature set for whole-body
  /// choreography comparison.
  static const List<JointSpec> fullBody = <JointSpec>[
    ...flexionEight,
    ...orientationEight,
    trunkTilt,
  ];

  /// Legs and trunk only — for footwork-dominant material where arm styling is
  /// free and should not be scored.
  static const List<JointSpec> lowerBody = <JointSpec>[
    leftHip, rightHip, leftKnee, rightKnee,
    leftThigh, rightThigh, leftShin, rightShin,
    trunkTilt,
  ];

  static const List<JointSpec> upperBody = <JointSpec>[
    leftElbow, rightElbow, leftShoulder, rightShoulder,
    leftUpperArm, rightUpperArm, leftForearm, rightForearm,
    trunkTilt,
  ];

  static JointSpec? byId(String id) {
    for (final JointSpec j in fullBody) {
      if (j.id == id) return j;
    }
    return null;
  }
}

/// One frame reduced to a fixed-length vector of angles, in radians.
///
/// Entries are `double.nan` where the angle could not be measured. Every
/// consumer must handle NaN explicitly — the similarity scorer treats it as
/// missing evidence and shrinks the denominator, rather than scoring it as a
/// mismatch. Otherwise a briefly occluded wrist would read as a technique
/// error, which is the single most trust-destroying failure this engine can
/// make.
final class JointAngleVector {
  const JointAngleVector({
    required this.tUs,
    required this.values,
    required this.specs,
  });

  final int tUs;
  final List<double> values;
  final List<JointSpec> specs;

  int get length => values.length;

  double operator [](int index) => values[index];

  double? byId(String id) {
    for (int i = 0; i < specs.length; i++) {
      if (specs[i].id == id) {
        final double v = values[i];
        return v.isNaN ? null : v;
      }
    }
    return null;
  }

  /// Degrees, for logging and rule authoring — rules are far easier to review
  /// in degrees than in radians.
  double? degreesById(String id) {
    final double? r = byId(id);
    return r == null ? null : r * radToDeg;
  }

  int get measuredCount => values.where((double v) => !v.isNaN).length;

  double get coverage => values.isEmpty ? 0 : measuredCount / values.length;
}

/// Extracts [JointAngleVector]s from normalized poses.
final class JointAngleExtractor {
  const JointAngleExtractor({this.specs = StandardJoints.fullBody, this.planar = true});

  final List<JointSpec> specs;

  /// Compute angles in the image plane only.
  ///
  /// Default true: single-camera depth is the weakest channel BlazePose emits,
  /// and letting a noisy z leak into every angle degrades all of them. Depth is
  /// opted into per technique, not assumed.
  final bool planar;

  JointAngleVector extract(NormalizedPose pose) {
    final List<double> out = List<double>.filled(specs.length, double.nan);
    for (int i = 0; i < specs.length; i++) {
      final JointSpec s = specs[i];
      switch (s.kind) {
        case AngleKind.flexion:
          final Vec3 a = pose[s.a];
          final Vec3 b = pose[s.b];
          final Vec3 c = pose[s.c];
          out[i] = planar ? jointAngle2D(a, b, c) : jointAngle(a, b, c);
        case AngleKind.orientation:
          final Vec3 a = pose[s.a];
          final Vec3 b = pose[s.b];
          if ((b - a).length2D < 1e-6) {
            out[i] = double.nan;
          } else {
            // Relative to the trunk axis, so leaning the whole body does not
            // change what an arm's direction reads as.
            out[i] = wrapPi(segmentAngle2D(a, b) - pose.torsoAxisAngle);
          }
        case AngleKind.trunkTilt:
          // Measured on the *raw* trunk angle: in rotate mode the normalized
          // trunk is vertical by construction, so reading it there would always
          // report zero lean.
          out[i] = wrapPi(pose.rawTorsoAxisAngle - (-3.141592653589793 / 2));
      }
    }
    return JointAngleVector(tUs: pose.tUs, values: out, specs: specs);
  }

  /// Marks angles as unmeasurable when any landmark they depend on is below
  /// [minVisibility] in the source frame.
  ///
  /// Kept separate from [extract] so that geometry and confidence stay
  /// independently testable.
  JointAngleVector gate(
    JointAngleVector v,
    List<double> visibilities, {
    double minVisibility = 0.5,
  }) {
    final List<double> out = List<double>.of(v.values);
    for (int i = 0; i < v.specs.length; i++) {
      for (final int lm in v.specs[i].requiredLandmarks) {
        if (lm >= 0 && visibilities[lm] < minVisibility) {
          out[i] = double.nan;
          break;
        }
      }
    }
    return JointAngleVector(tUs: v.tUs, values: out, specs: v.specs);
  }
}
