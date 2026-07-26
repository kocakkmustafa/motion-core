import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Swaps the arm and leg chains, keeping every visibility at 1.0.
///
/// This reproduces the family's M-019 failure in miniature: on an inverted body
/// the pose model can decide the person is upright and hand back arms and legs
/// exchanged — confidently. Every landmark is "certain", the skeleton is a
/// clean articulated figure, and every joint angle computed from it is about
/// the wrong limb.
PoseFrame swapArmsAndLegs(PoseFrame f) {
  final List<PoseLandmark> lm = List<PoseLandmark>.of(f.landmarks);
  void swap(int a, int b) {
    final PoseLandmark t = lm[a];
    lm[a] = lm[b];
    lm[b] = t;
  }

  swap(Lm.leftElbow, Lm.leftKnee);
  swap(Lm.leftWrist, Lm.leftAnkle);
  swap(Lm.rightElbow, Lm.rightKnee);
  swap(Lm.rightWrist, Lm.rightAnkle);
  return PoseFrame(tUs: f.tUs, landmarks: lm, modelVersion: f.modelVersion);
}

void main() {
  group('StructuralValidator', () {
    test('accepts an ordinary human skeleton', () {
      final StructuralValidator v = StructuralValidator();
      for (final PoseFrame f in basicSideStep().sample(fps: 30)) {
        expect(v.check(f).plausible, isTrue, reason: 'frame at ${f.tUs}');
      }
    });

    test('catches a confidently-reported arm/leg swap (M-019)', () {
      // The confidence gate cannot see this: nothing is uncertain. Only an
      // anatomical invariant catches it.
      final PoseFrame clean =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final PoseFrame swapped = swapArmsAndLegs(clean);

      expect(const ConfidenceGate().evaluate(swapped).judgeable, isTrue,
          reason: 'every landmark is still fully visible — this is exactly why '
              'confidence gating is not enough');

      final StructuralCheck check = StructuralValidator().check(swapped);
      expect(check.plausible, isFalse);
      expect(check.faults, contains(StructuralFault.limbProportionImplausible));
    });

    test('catches a limb that changed length between frames', () {
      final PoseFrame a =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final PoseFrame b = SyntheticPoseBuilder(
        body: const SyntheticBody(forearmLength: 0.30),
      ).build(SyntheticPose.neutral, tUs: 33333);

      final StructuralValidator v = StructuralValidator();
      expect(v.check(a).plausible, isTrue);
      final StructuralCheck second = v.check(b);
      expect(second.plausible, isFalse);
      expect(second.faults,
          anyOf(contains(StructuralFault.boneLengthInstability),
              contains(StructuralFault.bilateralAsymmetry)));
    });

    test('catches a skeleton that teleported', () {
      final PoseFrame a =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final PoseFrame b = const SyntheticPoseBuilder()
          .build(SyntheticPose.neutral.copyWith(rootX: 0.95), tUs: 16667);

      final StructuralValidator v = StructuralValidator();
      v.check(a);
      final StructuralCheck jump = v.check(b);
      expect(jump.plausible, isFalse);
      expect(jump.faults, contains(StructuralFault.temporalDiscontinuity));
    });

    test('does not fire on ordinary fast dancing', () {
      // The point of the temporal check is to catch tracking artefacts, not to
      // penalise energetic movement. A four-count phrase at full tempo must
      // pass cleanly.
      final StructuralValidator v = StructuralValidator();
      int flagged = 0;
      for (final PoseFrame f
          in fourCountPhrase(beatIntervalUs: 400000).sample(fps: 30)) {
        if (!v.check(f).plausible) flagged++;
      }
      expect(flagged, 0);
    });

    test('tolerates tracker jitter', () {
      final StructuralValidator v = StructuralValidator();
      final List<PoseFrame> noisy = SyntheticNoise.jitter(
        basicSideStep().sample(fps: 30),
        seed: 11,
        sigma: 0.005,
      );
      final int flagged =
          noisy.where((PoseFrame f) => !v.check(f).plausible).length;
      expect(flagged, 0);
    });
  });

  group('ConfidenceGate variants (M-018)', () {
    test('each variant carries its own thresholds', () {
      // Visibility is not comparable across model variants, so a single shared
      // threshold would quietly mean something different on each device tier.
      final ConfidenceGate lite =
          ConfidenceGate.forVariant(PoseModelVariant.lite);
      final ConfidenceGate full =
          ConfidenceGate.forVariant(PoseModelVariant.full);
      final ConfidenceGate heavy =
          ConfidenceGate.forVariant(PoseModelVariant.heavy);

      expect(lite.variant, PoseModelVariant.lite);
      expect(lite.landmarkThreshold, lessThan(full.landmarkThreshold));
      expect(heavy.landmarkThreshold, greaterThan(full.landmarkThreshold));
    });
  });

  group('PosePipeline', () {
    test('a structurally impossible frame is not judgeable', () {
      final PosePipeline p = PosePipeline();
      final PoseFrame clean =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final ProcessedFrame out = p.process(swapArmsAndLegs(clean));

      expect(out.quality.judgeable, isTrue, reason: 'confidence says fine');
      expect(out.structure.plausible, isFalse, reason: 'anatomy says no');
      expect(out.judgeable, isFalse, reason: 'both gates must agree');
    });
  });
}
