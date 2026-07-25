import 'dart:math' as math;

import '../geometry/vec3.dart';
import '../pose/landmark_index.dart';
import '../pose/pose_frame.dart';

/// Limb lengths of a synthetic skeleton, in normalized image units.
///
/// Exists so that "does this score depend on the dancer's build?" is an
/// automated assertion rather than a hope. The same [SyntheticPose] rendered
/// through two very different bodies must score as identical movement — that is
/// the whole justification for angle-based scoring, and it deserves a test that
/// fails loudly if it ever stops being true.
final class SyntheticBody {
  const SyntheticBody({
    this.torsoLength = 0.22,
    this.shoulderWidth = 0.16,
    this.hipWidth = 0.11,
    this.upperArmLength = 0.12,
    this.forearmLength = 0.11,
    this.thighLength = 0.16,
    this.shinLength = 0.15,
    this.neckLength = 0.05,
    this.headLength = 0.06,
    this.footLength = 0.05,
  });

  final double torsoLength;
  final double shoulderWidth;
  final double hipWidth;
  final double upperArmLength;
  final double forearmLength;
  final double thighLength;
  final double shinLength;
  final double neckLength;
  final double headLength;
  final double footLength;

  static const SyntheticBody average = SyntheticBody();

  /// Long limbs, narrow frame.
  static const SyntheticBody tallSlim = SyntheticBody(
    torsoLength: 0.26,
    shoulderWidth: 0.14,
    hipWidth: 0.09,
    upperArmLength: 0.15,
    forearmLength: 0.14,
    thighLength: 0.20,
    shinLength: 0.19,
  );

  /// Short limbs, broad frame.
  static const SyntheticBody shortBroad = SyntheticBody(
    torsoLength: 0.18,
    shoulderWidth: 0.20,
    hipWidth: 0.15,
    upperArmLength: 0.10,
    forearmLength: 0.09,
    thighLength: 0.12,
    shinLength: 0.11,
  );

  /// Uniformly rescaled body — simulates standing closer to or further from
  /// the camera without changing proportions.
  SyntheticBody scaled(double k) => SyntheticBody(
        torsoLength: torsoLength * k,
        shoulderWidth: shoulderWidth * k,
        hipWidth: hipWidth * k,
        upperArmLength: upperArmLength * k,
        forearmLength: forearmLength * k,
        thighLength: thighLength * k,
        shinLength: shinLength * k,
        neckLength: neckLength * k,
        headLength: headLength * k,
        footLength: footLength * k,
      );
}

/// A pose described by absolute segment directions in the image plane.
///
/// Angle convention: radians, `0` points image-right, `pi/2` points image-down.
/// A relaxed body therefore has arms and legs near `pi/2` and a trunk at
/// `-pi/2`. Sides are anatomical (the dancer's own left), matching MediaPipe.
final class SyntheticPose {
  const SyntheticPose({
    this.trunkAngle = -math.pi / 2,
    this.leftUpperArm = math.pi / 2.2,
    this.leftForearm = math.pi / 2.2,
    this.rightUpperArm = math.pi / 1.8,
    this.rightForearm = math.pi / 1.8,
    this.leftThigh = math.pi / 2.05,
    this.leftShin = math.pi / 2,
    this.rightThigh = math.pi / 1.95,
    this.rightShin = math.pi / 2,
    this.rootX = 0.5,
    this.rootY = 0.62,
  });

  final double trunkAngle;
  final double leftUpperArm;
  final double leftForearm;
  final double rightUpperArm;
  final double rightForearm;
  final double leftThigh;
  final double leftShin;
  final double rightThigh;
  final double rightShin;

  /// Hip-midpoint position in normalized image coordinates.
  final double rootX;
  final double rootY;

  /// Neutral standing pose.
  static const SyntheticPose neutral = SyntheticPose();

  SyntheticPose copyWith({
    double? trunkAngle,
    double? leftUpperArm,
    double? leftForearm,
    double? rightUpperArm,
    double? rightForearm,
    double? leftThigh,
    double? leftShin,
    double? rightThigh,
    double? rightShin,
    double? rootX,
    double? rootY,
  }) =>
      SyntheticPose(
        trunkAngle: trunkAngle ?? this.trunkAngle,
        leftUpperArm: leftUpperArm ?? this.leftUpperArm,
        leftForearm: leftForearm ?? this.leftForearm,
        rightUpperArm: rightUpperArm ?? this.rightUpperArm,
        rightForearm: rightForearm ?? this.rightForearm,
        leftThigh: leftThigh ?? this.leftThigh,
        leftShin: leftShin ?? this.leftShin,
        rightThigh: rightThigh ?? this.rightThigh,
        rightShin: rightShin ?? this.rightShin,
        rootX: rootX ?? this.rootX,
        rootY: rootY ?? this.rootY,
      );

  static double _lerpAngle(double a, double b, double t) =>
      a + wrapPi(b - a) * t;

  /// Shortest-path angular interpolation toward [other].
  SyntheticPose lerp(SyntheticPose other, double t) => SyntheticPose(
        trunkAngle: _lerpAngle(trunkAngle, other.trunkAngle, t),
        leftUpperArm: _lerpAngle(leftUpperArm, other.leftUpperArm, t),
        leftForearm: _lerpAngle(leftForearm, other.leftForearm, t),
        rightUpperArm: _lerpAngle(rightUpperArm, other.rightUpperArm, t),
        rightForearm: _lerpAngle(rightForearm, other.rightForearm, t),
        leftThigh: _lerpAngle(leftThigh, other.leftThigh, t),
        leftShin: _lerpAngle(leftShin, other.leftShin, t),
        rightThigh: _lerpAngle(rightThigh, other.rightThigh, t),
        rightShin: _lerpAngle(rightShin, other.rightShin, t),
        rootX: rootX + (other.rootX - rootX) * t,
        rootY: rootY + (other.rootY - rootY) * t,
      );
}

/// Forward kinematics: turns a [SyntheticPose] plus a [SyntheticBody] into a
/// full 33-landmark [PoseFrame].
///
/// Written independently of the angle *extractor* on purpose. The generator
/// goes angles → positions; the engine goes positions → angles. Because the two
/// directions are implemented separately, a round-trip test is a real check on
/// both, not a tautology that would pass even if the maths were wrong.
final class SyntheticPoseBuilder {
  const SyntheticPoseBuilder({this.body = SyntheticBody.average});

  final SyntheticBody body;

  static Vec3 _step(Vec3 from, double angle, double length) => Vec3(
        from.x + math.cos(angle) * length,
        from.y + math.sin(angle) * length,
        0,
      );

  PoseFrame build(
    SyntheticPose pose, {
    required int tUs,
    double visibility = 1.0,
    String modelVersion = 'synthetic-v1',
  }) {
    final Vec3 hipMid = Vec3(pose.rootX, pose.rootY, 0);
    final Vec3 shoulderMid = _step(hipMid, pose.trunkAngle, body.torsoLength);

    // Perpendicular to the trunk, pointing toward the dancer's left, which is
    // image-right when they face the camera.
    final double lateral = pose.trunkAngle + math.pi / 2;
    final double lx = math.cos(lateral);
    final double ly = math.sin(lateral);

    Vec3 offset(Vec3 c, double half) =>
        Vec3(c.x + lx * half, c.y + ly * half, 0);

    final Vec3 leftHip = offset(hipMid, body.hipWidth / 2);
    final Vec3 rightHip = offset(hipMid, -body.hipWidth / 2);
    final Vec3 leftShoulder = offset(shoulderMid, body.shoulderWidth / 2);
    final Vec3 rightShoulder = offset(shoulderMid, -body.shoulderWidth / 2);

    final Vec3 leftElbow = _step(leftShoulder, pose.leftUpperArm, body.upperArmLength);
    final Vec3 leftWrist = _step(leftElbow, pose.leftForearm, body.forearmLength);
    final Vec3 rightElbow = _step(rightShoulder, pose.rightUpperArm, body.upperArmLength);
    final Vec3 rightWrist = _step(rightElbow, pose.rightForearm, body.forearmLength);

    final Vec3 leftKnee = _step(leftHip, pose.leftThigh, body.thighLength);
    final Vec3 leftAnkle = _step(leftKnee, pose.leftShin, body.shinLength);
    final Vec3 rightKnee = _step(rightHip, pose.rightThigh, body.thighLength);
    final Vec3 rightAnkle = _step(rightKnee, pose.rightShin, body.shinLength);

    final Vec3 neck = _step(shoulderMid, pose.trunkAngle, body.neckLength);
    final Vec3 head = _step(neck, pose.trunkAngle, body.headLength);

    // Feet point along the trunk's lateral axis (dancer facing camera).
    final double footAngle = lateral;
    final Vec3 leftFootIndex = _step(leftAnkle, footAngle, body.footLength);
    final Vec3 rightFootIndex = _step(rightAnkle, footAngle + math.pi, body.footLength);
    final Vec3 leftHeel = _step(leftAnkle, footAngle + math.pi, body.footLength * 0.4);
    final Vec3 rightHeel = _step(rightAnkle, footAngle, body.footLength * 0.4);

    final List<Vec3> p = List<Vec3>.filled(Lm.count, Vec3.zero);
    p[Lm.nose] = head;
    p[Lm.leftEyeInner] = offset(head, 0.008);
    p[Lm.leftEye] = offset(head, 0.014);
    p[Lm.leftEyeOuter] = offset(head, 0.020);
    p[Lm.rightEyeInner] = offset(head, -0.008);
    p[Lm.rightEye] = offset(head, -0.014);
    p[Lm.rightEyeOuter] = offset(head, -0.020);
    p[Lm.leftEar] = offset(head, 0.026);
    p[Lm.rightEar] = offset(head, -0.026);
    p[Lm.mouthLeft] = offset(_step(head, pose.trunkAngle + math.pi, body.headLength * 0.3), 0.010);
    p[Lm.mouthRight] = offset(_step(head, pose.trunkAngle + math.pi, body.headLength * 0.3), -0.010);
    p[Lm.leftShoulder] = leftShoulder;
    p[Lm.rightShoulder] = rightShoulder;
    p[Lm.leftElbow] = leftElbow;
    p[Lm.rightElbow] = rightElbow;
    p[Lm.leftWrist] = leftWrist;
    p[Lm.rightWrist] = rightWrist;
    p[Lm.leftPinky] = _step(leftWrist, pose.leftForearm, 0.02);
    p[Lm.rightPinky] = _step(rightWrist, pose.rightForearm, 0.02);
    p[Lm.leftIndex] = _step(leftWrist, pose.leftForearm, 0.025);
    p[Lm.rightIndex] = _step(rightWrist, pose.rightForearm, 0.025);
    p[Lm.leftThumb] = _step(leftWrist, pose.leftForearm, 0.015);
    p[Lm.rightThumb] = _step(rightWrist, pose.rightForearm, 0.015);
    p[Lm.leftHip] = leftHip;
    p[Lm.rightHip] = rightHip;
    p[Lm.leftKnee] = leftKnee;
    p[Lm.rightKnee] = rightKnee;
    p[Lm.leftAnkle] = leftAnkle;
    p[Lm.rightAnkle] = rightAnkle;
    p[Lm.leftHeel] = leftHeel;
    p[Lm.rightHeel] = rightHeel;
    p[Lm.leftFootIndex] = leftFootIndex;
    p[Lm.rightFootIndex] = rightFootIndex;

    return PoseFrame(
      tUs: tUs,
      landmarks: List<PoseLandmark>.generate(
        Lm.count,
        (int i) => PoseLandmark(p[i].x, p[i].y, p[i].z, visibility),
        growable: false,
      ),
      modelVersion: modelVersion,
    );
  }
}

/// A keyframe in a synthetic movement.
final class SyntheticKeyframe {
  const SyntheticKeyframe(this.tUs, this.pose);

  final int tUs;
  final SyntheticPose pose;
}

/// Builds movement sequences by interpolating between keyframes and sampling
/// at a chosen frame rate.
final class SyntheticSequence {
  const SyntheticSequence(this.keyframes)
      : assert(keyframes.length >= 1, 'need at least one keyframe');

  final List<SyntheticKeyframe> keyframes;

  int get startUs => keyframes.first.tUs;
  int get endUs => keyframes.last.tUs;

  SyntheticPose poseAt(int tUs) {
    if (keyframes.length == 1 || tUs <= startUs) return keyframes.first.pose;
    if (tUs >= endUs) return keyframes.last.pose;
    for (int i = 1; i < keyframes.length; i++) {
      final SyntheticKeyframe b = keyframes[i];
      if (tUs <= b.tUs) {
        final SyntheticKeyframe a = keyframes[i - 1];
        final int span = b.tUs - a.tUs;
        final double t = span == 0 ? 0 : (tUs - a.tUs) / span;
        // Smoothstep easing: real movement accelerates out of and decelerates
        // into a position, and linear interpolation would produce impossible
        // instantaneous velocity changes at every keyframe.
        final double e = t * t * (3 - 2 * t);
        return a.pose.lerp(b.pose, e);
      }
    }
    return keyframes.last.pose;
  }

  /// Samples the sequence into pose frames.
  ///
  /// [timeShiftUs] offsets every timestamp — the cheapest way to synthesise a
  /// learner who does the right movement at the wrong moment, which is the
  /// central case Choreia has to detect.
  List<PoseFrame> sample({
    required int fps,
    SyntheticBody body = SyntheticBody.average,
    int timeShiftUs = 0,
    double visibility = 1.0,
    double tempoRatio = 1.0,
  }) {
    final SyntheticPoseBuilder builder = SyntheticPoseBuilder(body: body);
    final int stepUs = (1e6 / fps).round();
    final int duration = ((endUs - startUs) / tempoRatio).round();
    final List<PoseFrame> out = <PoseFrame>[];
    for (int t = 0; t <= duration; t += stepUs) {
      final int sourceT = startUs + (t * tempoRatio).round();
      out.add(builder.build(
        poseAt(sourceT),
        tUs: startUs + t + timeShiftUs,
        visibility: visibility,
      ));
    }
    return out;
  }
}

/// Deterministic perturbations used to build negative and degraded fixtures.
abstract final class SyntheticNoise {
  /// Adds Gaussian jitter to every coordinate.
  ///
  /// Seeded so a failing test reproduces exactly; a flaky fixture is worse than
  /// no fixture, because it trains everyone to ignore the suite.
  static List<PoseFrame> jitter(
    List<PoseFrame> frames, {
    required int seed,
    double sigma = 0.004,
  }) {
    final math.Random rng = math.Random(seed);
    double gauss() {
      final double u1 = 1 - rng.nextDouble();
      final double u2 = rng.nextDouble();
      return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    }

    return frames
        .map((PoseFrame f) => PoseFrame(
              tUs: f.tUs,
              landmarks: f.landmarks
                  .map((PoseLandmark l) => PoseLandmark(
                        l.x + gauss() * sigma,
                        l.y + gauss() * sigma,
                        l.z,
                        l.visibility,
                      ))
                  .toList(growable: false),
              modelVersion: f.modelVersion,
            ))
        .toList(growable: false);
    }

  /// Drops the visibility of chosen landmarks — simulates occlusion.
  static List<PoseFrame> occlude(
    List<PoseFrame> frames,
    List<int> landmarks, {
    double visibility = 0.15,
    int fromIndex = 0,
    int? toIndex,
  }) {
    final int end = toIndex ?? frames.length;
    return List<PoseFrame>.generate(frames.length, (int i) {
      if (i < fromIndex || i >= end) return frames[i];
      final List<PoseLandmark> lms = List<PoseLandmark>.of(frames[i].landmarks);
      for (final int lm in landmarks) {
        lms[lm] = lms[lm].copyWith(visibility: visibility);
      }
      return PoseFrame(
        tUs: frames[i].tUs,
        landmarks: lms,
        modelVersion: frames[i].modelVersion,
      );
    }, growable: false);
  }

  /// Removes frames to simulate a dropped frame rate under thermal load.
  static List<PoseFrame> decimate(List<PoseFrame> frames, int keepEvery) => <PoseFrame>[
        for (int i = 0; i < frames.length; i++)
          if (i % keepEvery == 0) frames[i],
      ];
}
