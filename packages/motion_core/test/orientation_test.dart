import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'structural_test.dart' show swapArmsAndLegs;

/// A coherent *correctly labeled* inverted body: every landmark's y flipped
/// around the frame centre. Bone lengths and chain identities are preserved —
/// this is what a pose model that truly understood handstands would report.
PoseFrame invert(PoseFrame f) {
  final List<PoseLandmark> lm = f.landmarks
      .map((PoseLandmark l) => l.copyWith(y: 1.0 - l.y))
      .toList(growable: false);
  return PoseFrame(tUs: f.tUs, landmarks: lm, modelVersion: f.modelVersion);
}

/// A body lying flat: y compressed to a narrow band so the torso axis is
/// horizontal and no orientation can honestly be asserted.
PoseFrame flatten(PoseFrame f) {
  final List<PoseLandmark> lm = f.landmarks
      .map((PoseLandmark l) => l.copyWith(y: 0.5 + (l.y - 0.5) * 0.05))
      .toList(growable: false);
  return PoseFrame(tUs: f.tUs, landmarks: lm, modelVersion: f.modelVersion);
}

PoseFrame _upright({int tUs = 0}) =>
    const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: tUs);

/// Simulates the measured D1 behaviour of the pose model on a person who is
/// actually holding a handstand:
///
/// * a plain (upright) pass confidently mislabels the body as an upright
///   person — chains swapped, axis reading upright (Gravita D1: 3/41 frames,
///   `vis_crit` 0.93 — nothing about it looks uncertain);
/// * a rotated (inverted) pass sees a normal-looking image and reports the
///   correct inverted skeleton.
final class _InvertedPersonDriver implements PoseSourceDriver {
  int uprightCalls = 0;
  int invertedCalls = 0;

  @override
  PoseFrame? detectAs(int tUs, BodyOrientation orientation) {
    if (orientation == BodyOrientation.upright) {
      uprightCalls++;
      return swapArmsAndLegs(_upright(tUs: tUs));
    }
    invertedCalls++;
    return invert(_upright(tUs: tUs));
  }
}

/// A person who is simply standing: the plain pass is right, and a rotated
/// pass would produce the same failure in the opposite direction (UPR-S2).
final class _UprightPersonDriver implements PoseSourceDriver {
  @override
  PoseFrame? detectAs(int tUs, BodyOrientation orientation) {
    if (orientation == BodyOrientation.upright) return _upright(tUs: tUs);
    return swapArmsAndLegs(invert(_upright(tUs: tUs)));
  }
}

void main() {
  group('observedOrientation', () {
    test('reads an ordinary skeleton as upright', () {
      expect(observedOrientation(_upright()), BodyOrientation.upright);
    });

    test('reads a vertically flipped skeleton as inverted', () {
      expect(observedOrientation(invert(_upright())), BodyOrientation.inverted);
    });

    test('refuses a verdict on a horizontal body', () {
      // A plank or a lying stretch has no vertical axis to assert. Returning
      // null here is what keeps the axis check honest for Lissom floor work.
      expect(observedOrientation(flatten(_upright())), isNull);
    });
  });

  group('StructuralValidator phase-axis conformity (G-010)', () {
    test('upright body in an upright phase passes', () {
      final StructuralCheck c = StructuralValidator()
          .check(_upright(), expected: BodyOrientation.upright);
      expect(c.plausible, isTrue);
    });

    test('correctly labeled handstand in an inverted phase passes', () {
      final StructuralCheck c = StructuralValidator()
          .check(invert(_upright()), expected: BodyOrientation.inverted);
      expect(c.plausible, isTrue);
    });

    test('upright-reading skeleton during an inverted hold is a mismatch', () {
      // The direct detector: during a phase the app KNOWS is inverted, an
      // upright-reading torso axis is proof the model relabeled the body —
      // even when limb proportions happen to sit inside tolerance.
      final StructuralCheck c = StructuralValidator()
          .check(_upright(), expected: BodyOrientation.inverted);
      expect(c.plausible, isFalse);
      expect(c.faults, contains(StructuralFault.axisMismatch));
    });

    test('no expectation means no axis verdict (transition phases)', () {
      final StructuralCheck c = StructuralValidator().check(_upright());
      expect(c.faults, isNot(contains(StructuralFault.axisMismatch)));
    });

    test('horizontal body never violates an expectation', () {
      final StructuralValidator v = StructuralValidator();
      final StructuralCheck c =
          v.check(flatten(_upright()), expected: BodyOrientation.inverted);
      expect(c.faults, isNot(contains(StructuralFault.axisMismatch)));
    });
  });

  group('OrientationAwarePoseSource (ADR-001)', () {
    test('an exact inverted expectation runs one rotated pass and succeeds',
        () {
      final _InvertedPersonDriver driver = _InvertedPersonDriver();
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(driver);

      final OrientationResolution r = source.next(
          0, const OrientationExpectation.exactly(BodyOrientation.inverted));

      expect(r.usable, isTrue);
      expect(r.strategy, BodyOrientation.inverted);
      expect(r.dualPass, isFalse);
      expect(driver.uprightCalls, 0,
          reason: 'exact expectation must not pay the dual-pass cost');
    });

    test('the D1 failure is caught, not served to the engine', () {
      // Plain inference on the inverted person returns the confidently wrong
      // upright skeleton. If the phase expects inverted, that frame must
      // become "no verdict" — never a judged rep about the wrong limbs.
      final _InvertedPersonDriver driver = _InvertedPersonDriver();
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(driver);

      final OrientationResolution r = source.next(
          0, const OrientationExpectation.exactly(BodyOrientation.upright));

      expect(r.usable, isFalse,
          reason: 'swapped chains must not reach the engine');
    });

    test('ambiguous phases dual-pass and let anatomy arbitrate', () {
      final _InvertedPersonDriver driver = _InvertedPersonDriver();
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(driver);

      final OrientationResolution r =
          source.next(0, const OrientationExpectation.ambiguous());

      expect(r.dualPass, isTrue);
      expect(driver.uprightCalls, 1);
      expect(driver.invertedCalls, 1);
      expect(r.usable, isTrue);
      expect(r.strategy, BodyOrientation.inverted,
          reason: 'only the rotated pass produced a coherent skeleton');
    });

    test('an upright person never gets the rotated result', () {
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(_UprightPersonDriver());

      final OrientationResolution r =
          source.next(0, const OrientationExpectation.ambiguous());

      expect(r.usable, isTrue);
      expect(r.strategy, BodyOrientation.upright,
          reason: 'always-rotate would reproduce the failure backwards');
    });

    test('settled belief flips only after a consistent streak (hysteresis)',
        () {
      final _InvertedPersonDriver driver = _InvertedPersonDriver();
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(driver, hysteresisFrames: 3);
      expect(source.resolved, BodyOrientation.upright);

      // Two inverted wins: not yet enough to flip.
      source.next(0, const OrientationExpectation.ambiguous());
      source.next(33000, const OrientationExpectation.ambiguous());
      expect(source.resolved, BodyOrientation.upright);

      // Third consistent win: belief flips.
      final OrientationResolution r =
          source.next(66000, const OrientationExpectation.ambiguous());
      expect(r.resolved, BodyOrientation.inverted);
      expect(source.resolved, BodyOrientation.inverted);
    });
  });
}
