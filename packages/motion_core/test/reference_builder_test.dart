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
      // Same input, but merged blind. Before the agreement gate (M-F-47) the
      // damage showed as visibly worse agreement; now the gate catches the
      // mirrored takes as named outliers instead — the blind reference loses
      // TWO SOURCES it should have had, and says so. Resolving the mirror is
      // what keeps all six teachers in the consensus.
      final List<ReferenceTake> takes = instructorTakes(flipCount: 2);
      final CanonicalReference resolved =
          const ReferenceBuilder().build(takes);
      final CanonicalReference blind =
          const ReferenceBuilder(mirrorMargin: 1e9).build(takes);

      expect(blind.mirroredTakeIds, isEmpty);
      expect(blind.excludedOutlierIds, hasLength(2),
          reason: 'unresolved mirrored takes read as outliers and are '
              'excluded by name, never silently averaged in');
      expect(blind.contributingTakes, takes.length - 2);

      expect(resolved.excludedOutlierIds, isEmpty);
      expect(resolved.contributingTakes, takes.length,
          reason: 'resolving the mirror keeps every teacher in the consensus');
    });

    test('assignment is order-independent — a consensus that depends on file '
        'order is not a consensus (M-F-48)', () {
      final List<ReferenceTake> takes = instructorTakes(flipCount: 2);
      final CanonicalReference a = const ReferenceBuilder().build(takes);
      final CanonicalReference b = const ReferenceBuilder()
          .build(takes.reversed.toList(growable: false));
      expect(a.mirroredTakeIds.toSet(), b.mirroredTakeIds.toSet(),
          reason: 'same takes, any order, same resolution');
      expect(a.contributingTakes, b.contributingTakes);
    });

    test('too few agreeing sources refuse to become a reference (M-F-47)', () {
      // Two coherent takes + two whose BODY-WIDE posture is something else
      // entirely (large offsets on arms and legs both sides — a different
      // movement, not a styling choice). The count gate (>=3) is satisfied;
      // the agreement gate must not be — 23 and 112 are not both "in".
      final SyntheticSequence seq = fourCountPhrase();
      ReferenceTake different(String id, double offset, int seed) {
        final SyntheticSequence other = SyntheticSequence(
          seq.keyframes
              .map((SyntheticKeyframe k) => SyntheticKeyframe(
                    k.tUs,
                    k.pose.copyWith(
                      leftUpperArm: k.pose.leftUpperArm + offset,
                      rightUpperArm: k.pose.rightUpperArm - offset,
                      leftForearm: k.pose.leftForearm + offset,
                      rightForearm: k.pose.rightForearm - offset,
                      leftThigh: k.pose.leftThigh + offset * 0.7,
                      rightThigh: k.pose.rightThigh - offset * 0.7,
                      leftShin: k.pose.leftShin + offset * 0.7,
                      rightShin: k.pose.rightShin - offset * 0.7,
                    ),
                  ))
              .toList(growable: false),
        );
        return takeOf(id, other, jitterSeed: seed);
      }

      final List<ReferenceTake> base = instructorTakes();
      final List<ReferenceTake> takes = <ReferenceTake>[
        base[0],
        base[1],
        different('weird1', 0.9, 7),
        different('weird2', -0.8, 8),
      ];
      expect(
        () => const ReferenceBuilder().build(takes),
        throwsA(isA<ReferenceAgreementError>()),
      );
    });

    test('twelve takes from one teacher are not a consensus (M-F-38)', () {
      // Passes the take gate with room to spare — and must still refuse:
      // tolerance is distilled from INTER-instructor variance, and repetition
      // by one person measures habit, not technique.
      final List<ReferenceTake> oneTeacher = instructorTakes()
          .map((ReferenceTake t) => ReferenceTake(
              id: t.id, source: 'synthetic:one-teacher', frames: t.frames))
          .toList(growable: false);

      expect(
        () => const ReferenceBuilder().build(oneTeacher),
        throwsArgumentError,
      );
      // The escape hatch is explicit, never accidental: a declared
      // single-teacher prototype may build, owning that its tolerance
      // reads as style.
      final CanonicalReference proto =
          const ReferenceBuilder(minSources: 1).build(oneTeacher);
      expect(proto.contributingTakes, oneTeacher.length);
    });

    test('an agreement gate that drops a person drops the reference too', () {
      // Raw input spans three sources, so the raw source gate passes. The
      // only take from the third source is a different movement — the
      // cluster keeps three TAKES (count gate satisfied) but only two
      // PEOPLE. The take count cannot see this; the source gate must.
      final SyntheticSequence seq = fourCountPhrase();
      final SyntheticSequence other = SyntheticSequence(
        seq.keyframes
            .map((SyntheticKeyframe k) => SyntheticKeyframe(
                  k.tUs,
                  k.pose.copyWith(
                    leftUpperArm: k.pose.leftUpperArm + 0.9,
                    rightUpperArm: k.pose.rightUpperArm - 0.9,
                    leftThigh: k.pose.leftThigh - 0.6,
                    rightThigh: k.pose.rightThigh + 0.6,
                  ),
                ))
            .toList(growable: false),
      );
      final List<ReferenceTake> base = instructorTakes();
      ReferenceTake as(ReferenceTake t, String source) =>
          ReferenceTake(id: t.id, source: source, frames: t.frames);
      final List<ReferenceTake> takes = <ReferenceTake>[
        as(base[0], 'synthetic:teacherA'),
        as(base[1], 'synthetic:teacherA'),
        as(base[2], 'synthetic:teacherB'),
        takeOf('teacherC', other, jitterSeed: 11),
      ];

      expect(
        () => const ReferenceBuilder().build(takes),
        throwsA(isA<ReferenceAgreementError>()),
      );
      // Sanity: with the source bar lowered the same input builds, proving
      // the refusal above came from source diversity, not take agreement.
      final CanonicalReference loose =
          const ReferenceBuilder(minSources: 2).build(takes);
      expect(loose.excludedOutlierIds, contains('teacherC'));
      expect(loose.contributingTakes, 3);
    });

    test('an unmeasured mirror gap must not read as confidence (M-O-25)', () {
      // 19 takes — one past exhaustive reach, onto the heuristic fallback.
      // The old code encoded the UNKNOWN runner-up gap as 2×margin, which
      // made `confident` unconditionally true exactly where it was
      // unknowable; two real instrument pools returned the identical round
      // 0.04000 before anyone noticed. The flag now carries its basis.
      final SyntheticSequence seq = fourCountPhrase();
      final List<ReferenceTake> takes =
          List<ReferenceTake>.generate(19, (int i) {
        return takeOf('t$i', seq,
            tempoRatio: 0.9 + (i % 7) * 0.03,
            flip: i < 4,
            jitterSeed: 500 + i);
      });

      final MirrorResolution r =
          const ReferenceBuilder().resolveMirroring(takes);
      expect(r.gapMeasured, isFalse);
      expect(r.runnerUpGap.isNaN, isTrue,
          reason: 'an unknown must read as unknown — the sentinel-above-'
              'margin encoding is the defect itself');
      expect(r.confident, isFalse,
          reason: 'no measurement, no prior → no confidence claim');
      expect(r.flippedIds.toSet(), <String>{'t0', 't1', 't2', 't3'},
          reason: 'withholding the confidence claim must not stop the '
              'per-take-margin flips from being applied');

      // A direct measurement (prior) may still ground confidence out there.
      final Map<String, bool> prior = <String, bool>{
        for (final ReferenceTake t in takes) t.id: false,
      };
      for (int i = 0; i < 4; i++) {
        prior['t$i'] = true;
      }
      final MirrorResolution withPrior =
          const ReferenceBuilder().resolveMirroring(takes, prior: prior);
      expect(withPrior.confident, isTrue);
      expect(withPrior.gapMeasured, isFalse,
          reason: 'the basis still says the gap itself was never measured');
    });

    test('pools up to 18 takes get a real measured gap (M-O-26)', () {
      // The family quality target (>=12 accepted takes per pool) sat exactly
      // on the old exhaustive switch point — every pool that met the bar
      // lost its measured gap. 13..18 must now stay on the measured path.
      final List<ReferenceTake> takes =
          List<ReferenceTake>.generate(13, (int i) {
        return takeOf('t$i', fourCountPhrase(),
            tempoRatio: 0.92 + (i % 5) * 0.04,
            flip: i < 3,
            jitterSeed: 700 + i);
      });
      final MirrorResolution r =
          const ReferenceBuilder().resolveMirroring(takes);
      expect(r.gapMeasured, isTrue);
      expect(r.runnerUpGap.isNaN, isFalse);
      expect(r.flippedIds.toSet(), <String>{'t0', 't1', 't2'});
    });

    test('a lead-side prior outranks consensus and disagreement is reported '
        '(M-J-06)', () {
      final List<ReferenceTake> takes = instructorTakes();
      // Measured prior says takes[1] was mirrored — consensus disagrees.
      final Map<String, bool> prior = <String, bool>{
        for (final ReferenceTake t in takes) t.id: false,
      }..[takes[1].id] = true;

      final MirrorResolution r =
          const ReferenceBuilder().resolveMirroring(takes, prior: prior);
      expect(r.flippedIds, <String>[takes[1].id],
          reason: 'the prior is a direct measurement; it wins');
      expect(r.priorDisagreements, contains(takes[1].id),
          reason: 'the contradiction is reported, never hidden — at small n '
              'it is the only symptom of a consensus that resolves wrongly');
    });

    test('a floor-bound tolerance says so instead of posing as measured '
        'disagreement (G-050)', () {
      // Gravita's real reference: survivors of the agreement gate agree so
      // tightly that every joint's dispersion sits under the 8° floor — the
      // published tolerance is the floor, and claiming it was derived from
      // instructor variance would be false. The styled-arm scenario below
      // is the contrast: genuine disagreement must read as `variance`.
      final CanonicalReference tight =
          const ReferenceBuilder().build(instructorTakes());
      final Map<String, double> share = tight.floorBoundShare();
      expect(share['left_thigh'], greaterThan(0.9),
          reason: 'near-identical takes must be floor-bound almost '
              'everywhere — if this fails the fixture stopped being tight');
      expect(
          tight.toleranceSourceAt(
              tight.length ~/ 2, 0, freeFloorDeg: 8),
          anyOf(ToleranceSource.floor, ToleranceSource.variance));

      final SyntheticSequence seq = fourCountPhrase();
      final math.Random rng = math.Random(41);
      final List<ReferenceTake> styled =
          List<ReferenceTake>.generate(6, (int i) {
        final double armStyle = (rng.nextDouble() - 0.5) * 1.6;
        final SyntheticSequence s = SyntheticSequence(
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
        return takeOf('s$i', s, jitterSeed: 300 + i);
      });
      final CanonicalReference loose = const ReferenceBuilder()
          .build(styled, clusterToleranceDeg: 40);
      final List<JointSpec> specs = loose.frames.first.specs;
      final int armIdx =
          specs.indexWhere((JointSpec s) => s.id == 'left_upper_arm');
      expect(loose.toleranceSourceAt(loose.length ~/ 2, armIdx),
          ToleranceSource.variance,
          reason: 'real disagreement above the floor must be labelled as '
              'measured, not clamped silently');
      expect(loose.floorBoundShare()['left_upper_arm'], lessThan(0.5));
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

  group('mirror flags carry their basis (M-J-09)', () {
    test('a prior makes confident true but cannot make the SEARCH decisive',
        () {
      // Near-symmetric material: mirroring barely changes anything, so the
      // assignment search ends in a near-tie. JabLab measured the trap on
      // real stance data: with a prior, `confident` read true while the
      // search gap sat at 0.0038 << margin — a consumer had no way to see
      // that the DATA had not resolved anything.
      final List<ReferenceTake> takes = <ReferenceTake>[
        for (int i = 0; i < 3; i++)
          takeOf('s$i', armsOverhead(), jitterSeed: 70 + i),
      ];
      const ReferenceBuilder b = ReferenceBuilder();

      final MirrorResolution noPrior = b.resolveMirroring(takes);
      expect(noPrior.searchDecisive, isFalse);

      final MirrorResolution withPrior = b.resolveMirroring(takes,
          prior: <String, bool>{for (final ReferenceTake t in takes) t.id: false});
      expect(withPrior.confident, isTrue,
          reason: 'the prior is a direct measurement — trusting it is right');
      expect(withPrior.searchDecisive, isFalse,
          reason: 'but the search itself stayed a near-tie, and the flag '
              'must say so independently of the prior');
      expect(withPrior.runnerUpGap, noPrior.runnerUpGap,
          reason: 'the prior must not change what the search measured');
      expect(withPrior.priorDisagreements, isEmpty,
          reason: 'a near-tie bestMask is a discarded coin flip — a conflict '
              'against it is not a disagreement, the prior filled a void '
              '(J-063: an all-false prior here showed 11 "disagreements" '
              'while agreeing with everything the builder actually did)');
    });

    test('asymmetric material makes the search decisive on its own', () {
      final SyntheticSequence seq = fourCountPhrase();
      final MirrorResolution r = const ReferenceBuilder()
          .resolveMirroring(<ReferenceTake>[
        takeOf('a', seq, jitterSeed: 80),
        takeOf('b', seq, jitterSeed: 81, flip: true),
        takeOf('c', seq, jitterSeed: 82),
      ]);
      expect(r.searchDecisive, isTrue);
      expect(r.confident, isTrue);
    });
  });

  group('refusal surfaces (L-143 review)', () {
    test('an infinite deviation prints as a structural gap, not a number',
        () {
      final ReferenceAgreementError e = ReferenceAgreementError(
          <String, double>{'x': double.infinity}, 14);
      expect('$e', contains('no measurable overlap'));
      expect('$e', isNot(contains('Infinity')));
    });

    test('RangeError is an ArgumentError — the premise the tool handler '
        'ordering stands on', () {
      // tool/build_reference.dart catches RangeError BEFORE ArgumentError so
      // a code defect cannot print as a policy refusal. That only works
      // while this subtype relation holds in the SDK.
      expect(RangeError.index(0, const <int>[]), isA<ArgumentError>());
    });

    test('an empty pool and a single take are refused with the real reason',
        () {
      expect(
        () => const ReferenceBuilder().build(<ReferenceTake>[]),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}', 'message',
            contains('zero takes'))),
      );
      expect(
        () => const ReferenceBuilder(minTakes: 1, minSources: 1)
            .build(<ReferenceTake>[takeOf('solo', fourCountPhrase())]),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}', 'message',
            contains('no peers'))),
        reason: 'n=1 used to die at the agreement gate as "no measurable '
            'overlap with peers" — a structural impossibility wearing a '
            'measurement finding\'s clothes (review HIGH-3)',
      );
    });
  });

  group('frameless takes (L-143)', () {
    test('a take with zero frames is refused by name before any counting',
        () {
      final SyntheticSequence seq = fourCountPhrase();
      expect(
        () => const ReferenceBuilder().build(<ReferenceTake>[
          takeOf('a', seq, jitterSeed: 1),
          const ReferenceTake(
              id: 'harvest-empty',
              source: 's-empty',
              frames: <JointAngleVector>[]),
          takeOf('c', seq, jitterSeed: 3),
        ]),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}',
            'message',
            allOf(contains('harvest-empty'),
                contains('zero measurable frames')))),
      );
    });
  });

  group('declared gate joint set (M-O-56 fourth class)', () {
    // The measured Ostinato scenario in miniature: one structural joint the
    // product scores (trunk agrees to fractions of a degree) and one free
    // joint it has already measured into coached_only (arms differ wildly).
    const JointSpec trunk = JointSpec(
        id: 'trunk_tilt', kind: AngleKind.trunkTilt, a: 11, b: 23);
    const JointSpec arm = JointSpec(
        id: 'left_elbow', kind: AngleKind.flexion, a: 11, b: 13, c: 15);

    ReferenceTake postureTake(String id, double armRad) => ReferenceTake(
          id: id,
          source: 'synthetic:$id',
          frames: <JointAngleVector>[
            for (int f = 0; f < 8; f++)
              JointAngleVector(
                tUs: f * 33333,
                values: <double>[0.10, armRad],
                specs: const <JointSpec>[trunk, arm],
              ),
          ],
        );

    List<ReferenceTake> mixedPool() => <ReferenceTake>[
          postureTake('a', 0.2),
          postureTake('b', 1.2), // arms legitimately all over the place
          postureTake('c', 2.4),
        ];

    test('a full-joint gate rejects takes that agree on the scored metric',
        () {
      // Documents the fourth class itself: with two joints the median is the
      // ARM deviation, so a pool whose trunk agrees exactly is refused.
      expect(
        () => const ReferenceBuilder().build(mixedPool()),
        throwsA(isA<ReferenceAgreementError>()),
      );
    });

    test('a declared gate set admits the pool the product actually scores',
        () {
      final CanonicalReference ref = const ReferenceBuilder().build(
        mixedPool(),
        gateJoints: const <String>['trunk_tilt'],
        gateBasis: 'arms are coached_only per measured M-O-47; trunk defines '
            'the posture identity',
      );
      expect(ref.contributingTakes, 3);
      expect(ref.gateJoints, const <String>['trunk_tilt']);
      expect(ref.gateBasis, contains('M-O-47'));
    });

    test('narrowing without a declared basis is refused by name', () {
      expect(
        () => const ReferenceBuilder()
            .build(mixedPool(), gateJoints: const <String>['trunk_tilt']),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
            'message', contains('gateBasis'))),
      );
    });

    test('an empty gate set is refused — it would wave everything through',
        () {
      expect(
        () => const ReferenceBuilder().build(mixedPool(),
            gateJoints: const <String>[], gateBasis: 'x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('gate joints absent from the build are refused by name', () {
      expect(
        () => const ReferenceBuilder().build(mixedPool(),
            gateJoints: const <String>['right_knee'], gateBasis: 'x'),
        throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
            'message', contains('right_knee'))),
      );
    });

    test('a stretched single-frame take is EXPOSED by takeEvidence '
        '(M-F-68 HIGH-1, report-first)', () {
      // One take carries a single frame that agrees with everyone's posture
      // — the M-F-47 gate cannot see it (its one sample deviates little),
      // and DTW's slope-normalized corridor stretches it across the whole
      // medoid timeline. The artifact must SAY that its contribution is one
      // sample replicated, not measured variance.
      final ReferenceTake thin = ReferenceTake(
        id: 'thin',
        source: 'synthetic:thin',
        frames: <JointAngleVector>[
          JointAngleVector(
            tUs: 0,
            values: const <double>[0.10, 0.20],
            specs: const <JointSpec>[trunk, arm],
          ),
        ],
      );
      final CanonicalReference ref = const ReferenceBuilder().build(
        <ReferenceTake>[
          postureTake('a', 0.20),
          postureTake('b', 0.21),
          thin,
        ],
      );
      expect(ref.contributingTakes, 3);
      final TakeEvidence thinEv = ref.takeEvidence['thin']!;
      expect(thinEv.frames, 1);
      expect(thinEv.durationUs, 0,
          reason: 'a span nobody measured is not declared');
      expect(thinEv.alignedDistinctShare, closeTo(1 / 8, 1e-9),
          reason: 'one sample answered an 8-frame timeline');
      // Healthy takes answer with their own material.
      expect(ref.takeEvidence['a']!.alignedDistinctShare, 1.0);
      expect(ref.takeEvidence['b']!.alignedDistinctShare,
          greaterThan(0.9));
    });

    test('the default remains the full-joint gate, unchanged', () {
      // Same pool with agreeing arms passes with NO gate declaration — the
      // legacy path is untouched.
      final CanonicalReference ref = const ReferenceBuilder().build(
        <ReferenceTake>[
          postureTake('a', 0.20),
          postureTake('b', 0.21),
          postureTake('c', 0.22),
        ],
      );
      expect(ref.contributingTakes, 3);
      expect(ref.gateJoints, isNull);
    });
  });
}
