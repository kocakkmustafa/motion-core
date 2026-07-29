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

  group('time-based hysteresis (M-F-72: 133 ms + ≥2 frame floor)', () {
    OrientationAwarePoseSource timeSource() => OrientationAwarePoseSource(
        _InvertedPersonDriver(),
        hysteresisMs: 133,
        // Would flip after 2 frames if frame-count mode were still active —
        // every test below would fail fast if hysteresisMs were ignored.
        hysteresisFrames: 2);

    void winAt(OrientationAwarePoseSource s, int tUs) =>
        s.next(tUs, const OrientationExpectation.ambiguous());

    test('30 fps: flips once the window is spanned, not before', () {
      final OrientationAwarePoseSource s = timeSource();
      for (int i = 0; i < 4; i++) {
        winAt(s, i * 33333); // 0..100 ms: inside the window
        expect(s.resolved, BodyOrientation.upright,
            reason: '${i * 33333} µs elapsed < 133 ms');
      }
      winAt(s, 4 * 33333); // 133.3 ms spanned
      expect(s.resolved, BodyOrientation.inverted);
    });

    test('60 fps: frame COUNT that would satisfy the old mode is not enough',
        () {
      final OrientationAwarePoseSource s = timeSource();
      // 5 frames at 60 fps = 66 ms — the legacy default (5 frames) would
      // have flipped here; time-based hysteresis must not.
      for (int i = 0; i < 5; i++) {
        winAt(s, i * 16667);
      }
      expect(s.resolved, BodyOrientation.upright,
          reason: '66 ms of evidence is 66 ms regardless of frame rate');
      winAt(s, 8 * 16667); // 133.3 ms
      expect(s.resolved, BodyOrientation.inverted);
    });

    test('a single frame never flips, no matter how much time surrounds it',
        () {
      final OrientationAwarePoseSource s = timeSource();
      winAt(s, 0);
      // One win, then nothing usable for a second — floor of two frames.
      expect(s.resolved, BodyOrientation.upright);
    });

    test('evidence older than the window cannot seed a flip (stale gap)', () {
      final OrientationAwarePoseSource s = timeSource();
      winAt(s, 0);
      // The second win arrives 500 ms later — the first is stale by the
      // window's own clock, so the streak restarts here instead of
      // spanning 0→500 ms and flipping on two isolated frames.
      winAt(s, 500000);
      expect(s.resolved, BodyOrientation.upright);
      // A genuine sustained run from the restart point still flips.
      winAt(s, 500000 + 70000);
      winAt(s, 500000 + 140000);
      expect(s.resolved, BodyOrientation.inverted);
    });

    test('an unusable frame neither resets nor advances the window', () {
      final OrientationAwarePoseSource s = timeSource();
      winAt(s, 0);
      winAt(s, 70000);
      // A "no verdict" frame in the middle: an exact-upright pass on the
      // inverted person yields a structurally broken skeleton → unusable.
      // Evidence of nothing must not erase the challenger's window.
      s.next(100000,
          const OrientationExpectation.exactly(BodyOrientation.upright));
      expect(s.resolved, BodyOrientation.upright);
      winAt(s, 140000); // 140 ms spanned since the first win
      expect(s.resolved, BodyOrientation.inverted,
          reason: 'the unusable frame was not contrary evidence — the '
              'window from t=0 must still count');
    });
  });
}
