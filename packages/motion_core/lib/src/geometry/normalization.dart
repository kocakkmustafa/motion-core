import 'dart:math' as math;

import '../pose/landmark_index.dart';
import '../pose/pose_frame.dart';
import 'vec3.dart';

/// How much of the camera/body pose is factored out before comparison.
enum NormalizationMode {
  /// Translate to the hip midpoint and divide by torso length.
  ///
  /// Removes where the user stands and how big they are, but **keeps** body
  /// lean and tilt. This is the default for dance: a body roll, a contra-body
  /// lean or a hip drop is signal, not noise, and canonicalising the torso to
  /// vertical would silently erase the very thing being taught.
  translateScale,

  /// Additionally rotate the torso axis to vertical in the image plane.
  ///
  /// Use only for techniques where absolute trunk orientation is noise — e.g.
  /// comparing an arm shape independent of how the user happened to lean, or
  /// absorbing camera roll on a propped-up phone.
  translateScaleRotate,
}

/// Body dimensions measured from a frame, in raw input units.
final class BodyScale {
  const BodyScale({
    required this.torsoLength,
    required this.shoulderWidth,
    required this.hipWidth,
  });

  final double torsoLength;
  final double shoulderWidth;
  final double hipWidth;

  /// A composite scale that is more stable than torso length alone.
  ///
  /// Torso length foreshortens when the user leans toward or away from the
  /// lens; shoulder width foreshortens when they turn sideways. Blending the
  /// two means no single rotation can collapse the reference — which matters
  /// because everything downstream is divided by this number.
  double get composite {
    final double t = torsoLength;
    final double s = shoulderWidth;
    if (t < 1e-6) return s < 1e-6 ? 1.0 : s;
    if (s < 1e-6) return t;
    return 0.7 * t + 0.3 * (s * 1.6);
  }

  bool get isUsable => torsoLength > 1e-4;

  static BodyScale measure(PoseFrame f) {
    final Vec3 shoulderMid = midpoint(f.point(Lm.leftShoulder), f.point(Lm.rightShoulder));
    final Vec3 hipMid = midpoint(f.point(Lm.leftHip), f.point(Lm.rightHip));
    return BodyScale(
      torsoLength: (shoulderMid - hipMid).length2D,
      shoulderWidth: (f.point(Lm.leftShoulder) - f.point(Lm.rightShoulder)).length2D,
      hipWidth: (f.point(Lm.leftHip) - f.point(Lm.rightHip)).length2D,
    );
  }
}

/// A per-user reference captured by the camera calibration wizard.
///
/// Using a *stored* scale rather than a per-frame one keeps the normalized
/// skeleton stable when the user steps toward or away from the phone mid-
/// movement — otherwise a step forward would shrink every measured limb and
/// read as a technique change.
final class CalibrationProfile {
  const CalibrationProfile({
    required this.referenceScale,
    this.capturedAtUs = 0,
  });

  final double referenceScale;
  final int capturedAtUs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'referenceScale': referenceScale,
        'capturedAtUs': capturedAtUs,
      };

  static CalibrationProfile fromJson(Map<String, dynamic> json) =>
      CalibrationProfile(
        referenceScale: (json['referenceScale'] as num).toDouble(),
        capturedAtUs: (json['capturedAtUs'] as num? ?? 0).toInt(),
      );
}

/// A pose expressed in torso-relative units: origin at the hip midpoint,
/// one unit ≈ one torso length.
///
/// Two people of very different proportions performing the same movement
/// produce nearly the same normalized pose — which is the precondition for
/// comparing a learner against a reference at all.
final class NormalizedPose {
  const NormalizedPose({
    required this.tUs,
    required this.points,
    required this.scaleUsed,
    required this.origin,
    required this.rotationApplied,
    required this.torsoAxisAngle,
    required this.rawTorsoAxisAngle,
  });

  final int tUs;

  /// 33 torso-relative points, in landmark index order.
  final List<Vec3> points;

  final double scaleUsed;
  final Vec3 origin;

  /// Rotation applied in radians (zero in [NormalizationMode.translateScale]).
  final double rotationApplied;

  /// Angle of the hip→shoulder axis **in this normalized frame**, in radians.
  ///
  /// Limb orientations are expressed relative to this, so it must describe the
  /// trunk as it sits in [points] — not as it sat in the source image. In
  /// [NormalizationMode.translateScaleRotate] the points have been rotated, so
  /// this is the canonical `-pi/2`; using the pre-rotation angle here would
  /// subtract the rotation a second time and skew every orientation feature.
  final double torsoAxisAngle;

  /// The trunk angle as measured in the source image, before normalization.
  /// Diagnostic only — a persistently tilted value usually means a tilted
  /// phone, which is a camera-setup problem rather than a posture one.
  final double rawTorsoAxisAngle;

  Vec3 operator [](int index) => points[index];

  double get tSeconds => tUs / 1e6;
}

/// Converts raw pose frames into [NormalizedPose].
final class PoseNormalizer {
  PoseNormalizer({
    this.mode = NormalizationMode.translateScale,
    this.calibration,
    this.scaleSmoothing = 0.15,
  });

  final NormalizationMode mode;

  /// When present, its `referenceScale` is used instead of a per-frame scale.
  final CalibrationProfile? calibration;

  /// EMA factor for the running scale estimate used when no calibration
  /// profile exists. Small values track slowly, which is what we want: real
  /// body size does not change during a session, only the measurement does.
  final double scaleSmoothing;

  double? _runningScale;

  /// Resets the running scale estimate (call between sessions/takes).
  void reset() => _runningScale = null;

  /// The scale currently in use, or `null` before the first frame.
  double? get currentScale => calibration?.referenceScale ?? _runningScale;

  NormalizedPose normalize(PoseFrame frame) {
    final Vec3 shoulderMid =
        midpoint(frame.point(Lm.leftShoulder), frame.point(Lm.rightShoulder));
    final Vec3 hipMid = midpoint(frame.point(Lm.leftHip), frame.point(Lm.rightHip));
    final BodyScale measured = BodyScale.measure(frame);

    final double scale;
    final double? fixed = calibration?.referenceScale;
    if (fixed != null && fixed > 1e-6) {
      scale = fixed;
    } else {
      final double instant = measured.isUsable ? measured.composite : 1.0;
      final double? prev = _runningScale;
      scale = _runningScale =
          (prev == null) ? instant : prev + (instant - prev) * scaleSmoothing;
    }

    final Vec3 torsoAxis = shoulderMid - hipMid;
    final double torsoAxisAngle = math.atan2(torsoAxis.y, torsoAxis.x);

    double rotation = 0;
    if (mode == NormalizationMode.translateScaleRotate) {
      // Image coordinates grow downward, so "up" is -y and the canonical
      // torso axis angle is -pi/2.
      rotation = (-math.pi / 2) - torsoAxisAngle;
    }
    final double cosR = math.cos(rotation);
    final double sinR = math.sin(rotation);
    final double invScale = scale > 1e-9 ? 1.0 / scale : 1.0;

    final List<Vec3> out = List<Vec3>.generate(
      Lm.count,
      (int i) {
        final Vec3 p = frame.point(i) - hipMid;
        final double sx = p.x * invScale;
        final double sy = p.y * invScale;
        final double sz = p.z * invScale;
        if (rotation == 0) return Vec3(sx, sy, sz);
        return Vec3(sx * cosR - sy * sinR, sx * sinR + sy * cosR, sz);
      },
      growable: false,
    );

    return NormalizedPose(
      tUs: frame.tUs,
      points: out,
      scaleUsed: scale,
      origin: hipMid,
      rotationApplied: rotation,
      torsoAxisAngle: wrapPi(torsoAxisAngle + rotation),
      rawTorsoAxisAngle: torsoAxisAngle,
    );
  }
}
