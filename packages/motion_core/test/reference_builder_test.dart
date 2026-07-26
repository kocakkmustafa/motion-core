import 'dart:math' as math;

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Turns a synthetic sequence into a take, optionally horizontally flipped —
/// which is what an instructor filming themselves mirrored for the viewer
/// produces.
ReferenceTake takeOf(
  String id,
  SyntheticSequence seq, {
  SyntheticBody body = SyntheticBody.average,
  double tempoRatio = 1.0,
  bool flip = false,
  int? jitterSeed,
}) {
  List<PoseFrame> frames =
      seq.sample(fps: 30, body: body, tempoRatio: tempoRatio);
  if (jitterSeed != null) {
    frames = SyntheticNoise.jitter(frames, seed: jitterSeed, sigma: 0.004);
  }
  if (flip) {
    frames = frames.map((PoseFrame f) => f.mirrored()).toList(growable: false);
  }
  return ReferenceTake(id: id, source: 'synthetic:$id', frames: angleSeries(frames));
}

void main() {
  group('circularStats', () {
    test('averages across the +/-pi wrap correctly', () {
      // The arithmetic mean of these is 0 — a pose nobody struck.
      final ({double mean, double dispersion, int count}) s =
          circularStats(<double>[math.pi - 0.02, -math.pi + 0.02]);
      expect(s.mean.abs(), closeTo(math.pi, 0.05));
      expect(s.count, 2);
    });

    test('dispersion grows with disagreement', () {
      final double tight =
          circularStats(<double>[1.00, 1.02, 0.98, 1.01]).dispersion;
      final double loose =
          circularStats(<double>[0.2, 1.4, -0.7, 2.1]).dispersion;
      expect(tight, lessThan(loose));
      expect(tight, lessThan(0.1));
    });

    test('ignores unmeasurable angles instead of poisoning the mean', () {
      final ({double mean, double dispersion, int count}) s =
          circularStats(<double>[0.5, double.nan, 0.52]);
      expect(s.count, 2);
      expect(s.mean, closeTo(0.51, 0.01));
    });
  });

  group('mirroring angle vectors', () {
    test('swaps sides and negates directions', () {
      final JointAngleVector v = anglesOf(
        SyntheticPose.neutral.copyWith(leftUpperArm: 0.2, rightUpperArm: 2.6),
      );
      final JointAngleVector m = v.mirrored();

      expect(m.byId('left_upper_arm')!,
          closeTo(-v.byId('right_upper_arm')!, 1e-9));
      expect(m.byId('right_elbow')!, closeTo(v.byId('left_elbow')!, 1e-9));
    });

    test('mirroring twice is the identity', () {
      final JointAngleVector v = anglesOf(
        SyntheticPose.neutral.copyWith(leftThigh: 1.1, rightUpperArm: 2.2),
      );
      final JointAngleVector back = v.mirrored().mirrored();
      for (int i = 0; i < v.length; i++) {
        expect(angleDelta(back[i], v[i]), lessThan(1e-9));
      }
    });
  });

  group('ReferenceBuilder', () {
    List<ReferenceTake> instructorTakes({int flipCount = 0}) {
      final SyntheticSequence seq = fourCountPhrase();
      final List<SyntheticBody> bodies = <SyntheticBody>[
        SyntheticBody.average,
        SyntheticBody.tallSlim,
        SyntheticBody.shortBroad,
        SyntheticBody.average.scaled(0.9),
        SyntheticBody.tallSlim.scaled(1.1),
        SyntheticBody.average,
      ];
      final List<double> tempos = <double>[1.0, 1.08, 0.94, 1.02, 0.97, 1.05];
      return List<ReferenceTake>.generate(6, (int i) {
        return takeOf(
          'teacher$i',
          seq,
          body: bodies[i],
          tempoRatio: tempos[i],
          flip: i < flipCount,
          jitterSeed: 100 + i,
        );
      });
    }

    test('refuses to build a reference from too few takes', () {
      expect(
        () => const ReferenceBuilder()
            .build(instructorTakes().take(2).toList(growable: false)),
        throwsArgumentError,
      );
    });

    test('merges independent takes into a coherent reference', () {
      final CanonicalReference ref =
          const ReferenceBuilder().build(instructorTakes());

      expect(ref.contributingTakes, 6);
      expect(ref.length, greaterThan(30));
      expect(ref.sources.every((String s) => s.startsWith('synthetic:')), isTrue);

      // Teachers performing the same phrase should agree closely.
      final double meanAgreement = List<double>.generate(
        ref.length,
        ref.agreementAt,
      ).reduce((double a, double b) => a + b) / ref.length;
      expect(meanAgreement, greaterThan(0.8));
    });

    test('recovers handedness by consensus, with no outside knowledge', () {
      // Two of six teachers filmed themselves mirrored for the viewer. Nothing
      // in the landmarks says which — only the group can tell.
      final List<ReferenceTake> takes = instructorTakes(flipCount: 2);
      final CanonicalReference ref = const ReferenceBuilder().build(takes);

      expect(ref.mirroredTakeIds.length, 2,
          reason: 'exactly the two flipped takes should have been corrected');
      expect(ref.mirroredTakeIds, containsAll(<String>['teacher0', 'teacher1']));
    });

    test('an unresolved mirror would wreck the reference — this is the guard', () {
      // Same input, but merged blind. Agreement must be visibly worse, which is
      // what justifies the consensus step existing at all.
      final List<ReferenceTake> takes = instructorTakes(flipCount: 2);
      final CanonicalReference resolved =
          const ReferenceBuilder().build(takes);
      final CanonicalReference blind =
          const ReferenceBuilder(mirrorMargin: 1e9).build(takes);

      double mean(CanonicalReference r) =>
          List<double>.generate(r.length, r.agreementAt)
              .reduce((double a, double b) => a + b) /
          r.length;

      expect(blind.mirroredTakeIds, isEmpty);
      expect(mean(resolved), greaterThan(mean(blind) + 0.05));
    });

    test('teacher disagreement becomes the tolerance', () {
      // Every teacher performs the footwork identically but styles the arms
      // differently. The reference must end up strict on the feet and lenient
      // on the arms — a single recording could never tell us this.
      final SyntheticSequence seq = fourCountPhrase();
      final math.Random rng = math.Random(9);
      final List<ReferenceTake> takes = List<ReferenceTake>.generate(6, (int i) {
        final double armStyle = (rng.nextDouble() - 0.5) * 1.6;
        final SyntheticSequence styled = SyntheticSequence(
          seq.keyframes
              .map((SyntheticKeyframe k) => SyntheticKeyframe(
                    k.tUs,
                    k.pose.copyWith(
                      leftUpperArm: k.pose.leftUpperArm + armStyle,
                      leftForearm: k.pose.leftForearm + armStyle,
                    ),
                  ))
              .toList(growable: false),
        );
        return takeOf('t$i', styled, jitterSeed: 200 + i);
      });

      final CanonicalReference ref = const ReferenceBuilder().build(takes);
      final List<JointSpec> specs = ref.frames.first.specs;
      final int armIdx =
          specs.indexWhere((JointSpec s) => s.id == 'left_upper_arm');
      final int legIdx = specs.indexWhere((JointSpec s) => s.id == 'left_thigh');
      final int mid = ref.length ~/ 2;

      expect(ref.toleranceAt(mid, armIdx).free,
          greaterThan(ref.toleranceAt(mid, legIdx).free),
          reason: 'the joint teachers disagree on must be scored more loosely');
      expect(ref.dispersion[mid][armIdx],
          greaterThan(ref.dispersion[mid][legIdx] * 3));

      // The product default for "too contested to score" stays where it is;
      // this scenario's spread is passed explicitly rather than tuning a
      // shipped threshold to make a test go green.
      final List<String> contested = ref.unreliableJoints(sdThresholdDeg: 18);
      expect(contested, contains('left_upper_arm'));
      expect(contested, isNot(contains('left_thigh')));
    });
  });
}
