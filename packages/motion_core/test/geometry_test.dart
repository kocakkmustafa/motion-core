import 'dart:math' as math;

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Vec3', () {
    test('normalizing a degenerate vector yields zero, not NaN', () {
      expect(Vec3.zero.normalized, Vec3.zero);
      expect(const Vec3(1e-12, 0, 0).normalized, Vec3.zero);
    });

    test('jointAngle returns NaN for a collapsed segment', () {
      // A joint whose child landmark collapsed onto it carries no angular
      // information; reporting 0 would be indistinguishable from a fully
      // folded limb.
      expect(jointAngle(Vec3.zero, Vec3.zero, const Vec3(1, 0, 0)).isNaN, isTrue);
    });

    test('jointAngle measures the interior angle at the vertex', () {
      final double a = jointAngle(
        const Vec3(0, -1, 0),
        Vec3.zero,
        const Vec3(1, 0, 0),
      );
      expect(a * radToDeg, closeTo(90, 1e-9));
    });

    test('wrapPi keeps angles in (-pi, pi]', () {
      expect(wrapPi(0), closeTo(0, 1e-12));
      expect(wrapPi(math.pi), closeTo(math.pi, 1e-12));
      expect(wrapPi(3 * math.pi), closeTo(math.pi, 1e-12));
      expect(wrapPi(-3 * math.pi / 2), closeTo(math.pi / 2, 1e-12));
    });

    test('angleDelta takes the short way round the circle', () {
      expect(angleDelta(3.0, -3.0) * radToDeg, closeTo(360 - 343.77, 0.5));
      expect(angleDelta(0.1, -0.1), closeTo(0.2, 1e-12));
    });
  });

  group('normalization', () {
    test('places the hip midpoint at the origin', () {
      final PoseFrame f =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final NormalizedPose n = PoseNormalizer().normalize(f);
      final Vec3 hipMid = midpoint(n[Lm.leftHip], n[Lm.rightHip]);
      expect(hipMid.length2D, closeTo(0, 1e-9));
    });

    test('is invariant to camera distance (uniform body scaling)', () {
      // Standing twice as far from the phone halves every measured length. If
      // that survived normalization, every score would drift as the user moved.
      final PoseFrame near = const SyntheticPoseBuilder().build(
        SyntheticPose.neutral,
        tUs: 0,
      );
      final PoseFrame far = SyntheticPoseBuilder(
        body: SyntheticBody.average.scaled(0.5),
      ).build(SyntheticPose.neutral, tUs: 0);

      final NormalizedPose a = PoseNormalizer().normalize(near);
      final NormalizedPose b = PoseNormalizer().normalize(far);

      for (final int lm in LmRegion.fullBody) {
        expect((a[lm] - b[lm]).length2D, lessThan(1e-6),
            reason: 'landmark ${Lm.nameOf(lm)} moved under pure rescaling');
      }
    });

    test('default mode preserves body lean; rotate mode removes it', () {
      final SyntheticPose leaning =
          SyntheticPose.neutral.copyWith(trunkAngle: -math.pi / 2 + 0.25);
      final PoseFrame f = const SyntheticPoseBuilder().build(leaning, tUs: 0);

      final NormalizedPose kept = PoseNormalizer().normalize(f);
      final NormalizedPose removed = PoseNormalizer(
        mode: NormalizationMode.translateScaleRotate,
      ).normalize(f);

      expect(kept.rotationApplied, 0);
      expect(kept.torsoAxisAngle, closeTo(-math.pi / 2 + 0.25, 1e-9));
      // Canonicalised: the trunk now sits vertical in the normalized frame.
      expect(removed.torsoAxisAngle, closeTo(-math.pi / 2, 1e-9));
      // ...but the raw lean is still on record for diagnostics.
      expect(removed.rawTorsoAxisAngle, closeTo(-math.pi / 2 + 0.25, 1e-9));
    });
  });

  group('joint angle extraction', () {
    test('recovers the angles the synthetic pose was built from', () {
      // Forward kinematics (angles -> positions) and extraction
      // (positions -> angles) are written independently, so agreement here is
      // real evidence rather than a tautology.
      final SyntheticPose pose = SyntheticPose.neutral.copyWith(
        leftUpperArm: math.pi / 2,
        leftForearm: math.pi / 4,
      );
      final JointAngleVector v = anglesOf(pose);

      // Elbow interior angle depends only on the difference of the two segment
      // directions: pi - |upperArm - forearm|.
      final double expected = math.pi - (math.pi / 2 - math.pi / 4);
      expect(v.byId('left_elbow')!, closeTo(expected, 1e-6));
    });

    test('orientation angles are measured relative to the trunk', () {
      final SyntheticPose upright = SyntheticPose.neutral.copyWith(
        trunkAngle: -math.pi / 2,
        leftUpperArm: 0, // straight out to the dancer's left
      );
      final SyntheticPose leaning = upright.copyWith(
        trunkAngle: -math.pi / 2 + 0.3,
        leftUpperArm: 0.3, // same arm position relative to the body
      );

      expect(
        anglesOf(upright).byId('left_upper_arm')!,
        closeTo(anglesOf(leaning).byId('left_upper_arm')!, 1e-6),
      );
    });

    test('trunk tilt is reported even in rotate mode', () {
      final SyntheticPose leaning =
          SyntheticPose.neutral.copyWith(trunkAngle: -math.pi / 2 + 0.2);
      final JointAngleVector v = anglesOf(
        leaning,
        mode: NormalizationMode.translateScaleRotate,
      );
      expect(v.byId('trunk_tilt')!, closeTo(0.2, 1e-6));
    });

    test('gating marks angles unmeasurable when a landmark is occluded', () {
      final PoseFrame f =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final List<PoseFrame> occluded =
          SyntheticNoise.occlude(<PoseFrame>[f], <int>[Lm.leftWrist]);

      const JointAngleExtractor extractor = JointAngleExtractor();
      final JointAngleVector raw =
          extractor.extract(PoseNormalizer().normalize(occluded.first));
      final JointAngleVector gated = extractor.gate(
        raw,
        occluded.first.landmarks
            .map((PoseLandmark l) => l.visibility)
            .toList(growable: false),
      );

      expect(raw.byId('left_elbow'), isNotNull);
      expect(gated.byId('left_elbow'), isNull,
          reason: 'elbow angle needs the wrist, which was occluded');
      expect(gated.byId('right_elbow'), isNotNull,
          reason: 'the other arm was unaffected');
    });
  });
}
