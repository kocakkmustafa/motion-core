import 'dart:math' as math;

import '../geometry/vec3.dart';
import 'landmark_index.dart';
import 'orientation.dart';
import 'pose_frame.dart';

/// A way the reported skeleton is not anatomically possible.
enum StructuralFault {
  /// Left and right versions of the same bone differ implausibly in length.
  bilateralAsymmetry,

  /// A bone changed length between frames — bones do not do that.
  boneLengthInstability,

  /// Arm and leg proportions are inverted or otherwise out of human range.
  ///
  /// This is the signature of the failure that motivated this whole class: on
  /// an inverted body the pose model can decide the person is upright and swap
  /// the arm and leg chains, reporting the result with **high confidence**.
  /// Confidence gating cannot catch it, because nothing is uncertain — the
  /// model is confidently describing a different person.
  limbProportionImplausible,

  /// The skeleton jumped further between frames than a body can move.
  temporalDiscontinuity,

  /// The skeleton's torso axis contradicts the orientation the current skill
  /// phase expects (Gravita G-010; pairs with ADR-001).
  ///
  /// This is the most direct axis-swap detector: a swapped chain reads as an
  /// upright skeleton, so during a phase the app *knows* is inverted, an
  /// upright-reading torso axis is proof of relabeling. It covers the cases
  /// the limb-proportion invariant is weak on — limbs out of frame, or a
  /// build whose arm/leg ratio sits near the threshold.
  axisMismatch,
}

/// Verdict on whether a frame is anatomically coherent.
final class StructuralCheck {
  const StructuralCheck({
    required this.plausible,
    required this.faults,
    required this.detail,
  });

  const StructuralCheck.ok()
      : plausible = true,
        faults = const <StructuralFault>[],
        detail = '';

  final bool plausible;
  final List<StructuralFault> faults;
  final String detail;

  @override
  String toString() =>
      plausible ? 'StructuralCheck(ok)' : 'StructuralCheck(${faults.map((StructuralFault f) => f.name).join(", ")}: $detail)';
}

/// Checks that a reported skeleton could belong to an actual human body.
///
/// The family's confidence gate answers "did the model see this clearly?".
/// It cannot answer "is what the model saw a body?" — and those come apart in
/// practice. A pose model presented with a body it was not trained for can
/// return a confidently wrong topology, at which point every downstream angle
/// is precise, stable, and about the wrong limb.
///
/// This validator is the second gate: cheap geometric invariants that hold for
/// every human regardless of build, pose or camera. Failing one of them means
/// the frame is unusable no matter how confident the model was.
final class StructuralValidator {
  StructuralValidator({
    this.bilateralTolerance = 0.55,
    this.boneStabilityTolerance = 0.30,
    this.maxJumpPerSecond = 6.0,
  });

  /// Allowed relative difference between a left bone and its right twin.
  ///
  /// Generous by measurement, not by guess. The original 0.35 default was
  /// rejecting 32% of *correct* frames on Gravita's D1 footage (G-018, n=66):
  /// the asymmetry came from 2D perspective foreshortening, not from the
  /// model being wrong. 0.55–0.60 brings the false-reject rate to ~6–11%
  /// while still catching the confidently-swapped chain (#21) — verified by
  /// regression test against the real D1 frames. The goal is to catch a
  /// swapped chain, not to audit posture; posture belongs to the rules.
  final double bilateralTolerance;

  /// Allowed relative change in a bone's length between consecutive frames.
  final double boneStabilityTolerance;

  /// Maximum hip-midpoint travel, in torso lengths per second.
  final double maxJumpPerSecond;

  Map<String, double>? _previousBones;
  Vec3? _previousHip;
  int? _previousTUs;

  void reset() {
    _previousBones = null;
    _previousHip = null;
    _previousTUs = null;
  }

  static const List<(String, int, int)> _bones = <(String, int, int)>[
    ('upperArm.l', Lm.leftShoulder, Lm.leftElbow),
    ('upperArm.r', Lm.rightShoulder, Lm.rightElbow),
    ('forearm.l', Lm.leftElbow, Lm.leftWrist),
    ('forearm.r', Lm.rightElbow, Lm.rightWrist),
    ('thigh.l', Lm.leftHip, Lm.leftKnee),
    ('thigh.r', Lm.rightHip, Lm.rightKnee),
    ('shin.l', Lm.leftKnee, Lm.leftAnkle),
    ('shin.r', Lm.rightKnee, Lm.rightAnkle),
  ];

  static Map<String, double> measureBones(PoseFrame f) {
    final Map<String, double> out = <String, double>{};
    for (final (String name, int a, int b) in _bones) {
      out[name] = (f.point(a) - f.point(b)).length2D;
    }
    return out;
  }

  static double _relDiff(double a, double b) {
    final double m = math.max(a.abs(), b.abs());
    return m < 1e-9 ? 0 : (a - b).abs() / m;
  }

  /// Check one frame's anatomical coherence.
  ///
  /// Pass [expected] when the active skill phase pins the body orientation
  /// (a handstand hold is inverted; a guard stance is upright): the torso
  /// axis is then compared against the expectation and a contradiction is an
  /// [StructuralFault.axisMismatch]. Leave it null during transition phases —
  /// an ambiguous phase has no expectation to violate, and a horizontal body
  /// yields no axis verdict either way.
  StructuralCheck check(PoseFrame frame, {BodyOrientation? expected}) {
    final List<StructuralFault> faults = <StructuralFault>[];
    final List<String> detail = <String>[];

    final Map<String, double> bones = measureBones(frame);
    final Vec3 hipMid =
        midpoint(frame.point(Lm.leftHip), frame.point(Lm.rightHip));
    final Vec3 shoulderMid =
        midpoint(frame.point(Lm.leftShoulder), frame.point(Lm.rightShoulder));
    final double torso = (shoulderMid - hipMid).length2D;

    // --- phase-axis conformity ----------------------------------------------
    if (expected != null) {
      final BodyOrientation? observed = observedOrientation(frame);
      if (observed != null && observed != expected) {
        faults.add(StructuralFault.axisMismatch);
        detail.add('axis reads ${observed.name}, phase expects '
            '${expected.name}');
      }
    }

    // --- bilateral symmetry -------------------------------------------------
    for (final String base in <String>['upperArm', 'forearm', 'thigh', 'shin']) {
      final double l = bones['$base.l']!;
      final double r = bones['$base.r']!;
      if (_relDiff(l, r) > bilateralTolerance) {
        faults.add(StructuralFault.bilateralAsymmetry);
        detail.add('$base l/r ${l.toStringAsFixed(3)}/${r.toStringAsFixed(3)}');
        break;
      }
    }

    // --- limb proportions ---------------------------------------------------
    // Human legs are longer than arms. When a model swaps the chains on an
    // inverted body, the "arm" it reports is really a leg and this inequality
    // flips. Compared against the torso so the test is scale-free.
    if (torso > 1e-6) {
      final double arm =
          (bones['upperArm.l']! + bones['upperArm.r']!) / 2 +
              (bones['forearm.l']! + bones['forearm.r']!) / 2;
      final double leg = (bones['thigh.l']! + bones['thigh.r']!) / 2 +
          (bones['shin.l']! + bones['shin.r']!) / 2;
      final double ratio = leg < 1e-9 ? 0 : arm / leg;
      // Adult arm-to-leg span sits well under 1. Allowing up to 1.15 leaves
      // room for foreshortening and unusual builds while still catching a swap.
      if (ratio > 1.15 || ratio < 0.35) {
        faults.add(StructuralFault.limbProportionImplausible);
        detail.add('arm/leg ${ratio.toStringAsFixed(2)}');
      }
    }

    // --- temporal continuity ------------------------------------------------
    final Map<String, double>? prevBones = _previousBones;
    final Vec3? prevHip = _previousHip;
    final int? prevT = _previousTUs;

    if (prevBones != null && prevT != null && frame.tUs > prevT) {
      final double dt = (frame.tUs - prevT) / 1e6;
      for (final MapEntry<String, double> e in bones.entries) {
        final double before = prevBones[e.key]!;
        if (_relDiff(before, e.value) > boneStabilityTolerance) {
          faults.add(StructuralFault.boneLengthInstability);
          detail.add('${e.key} ${before.toStringAsFixed(3)}→'
              '${e.value.toStringAsFixed(3)}');
          break;
        }
      }
      if (prevHip != null && torso > 1e-6) {
        final double travelled = (hipMid - prevHip).length2D / torso;
        if (travelled / dt > maxJumpPerSecond) {
          faults.add(StructuralFault.temporalDiscontinuity);
          detail.add('hip moved ${(travelled / dt).toStringAsFixed(1)} '
              'torso/s');
        }
      }
    }

    _previousBones = bones;
    _previousHip = hipMid;
    _previousTUs = frame.tUs;

    if (faults.isEmpty) return const StructuralCheck.ok();
    return StructuralCheck(
      plausible: false,
      faults: faults,
      detail: detail.join('; '),
    );
  }
}
