import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const int beatUs = 500000;

  /// The reference performance: a side step, on the beat, average build.
  List<PoseFrame> reference() => basicSideStep(beatIntervalUs: beatUs).sample(fps: 30);

  /// The scored accent: the moment the weight lands, which is what a teacher
  /// counts. Frame 15 of a 31-frame, one-second take is the 500 ms keyframe.
  const List<ScoredMoment> moments = <ScoredMoment>[
    ScoredMoment(id: 'step_land', referenceIndex: 15, expectedBeatIndex: 1, label: 'step'),
  ];

  const PerceivedBeatTimeline onTimeline =
      PerceivedBeatTimeline(grid: ConstantTempoBeatGrid(bpm: 120));

  group('SequenceComparator — shape', () {
    test('a different body performing the same step scores as correct', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs)
            .sample(fps: 30, body: SyntheticBody.shortBroad),
      );

      expect(e.reliable, isTrue, reason: e.unreliableReason);
      expect(e.shapeScore, greaterThan(0.97));
      expect(e.coverage, 1.0);
    });

    test('a different movement scores materially lower, and blames the arms', () {
      // NOTE ON THE THRESHOLD: what number a *user* should see for a given
      // attempt is a calibration question that needs real recordings and human
      // judgement — it is a G4 gate item, not something a synthetic fixture can
      // settle. What this test locks down is the mechanism: a wrong movement
      // must separate clearly from a right one, and the fault must be pinned on
      // the limb that was actually wrong. Here the legs happen to be similar in
      // both takes (a side step and an overhead reach are both performed
      // standing), so the residual score is not expected to collapse to zero.
      final AttemptEvaluation right = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
      );
      final AttemptEvaluation wrong = SequenceComparator().evaluate(
        reference: reference(),
        learner: armsOverhead(beatIntervalUs: beatUs).sample(fps: 30),
      );

      expect(wrong.shapeScore, lessThan(0.85));
      expect(right.shapeScore - wrong.shapeScore, greaterThan(0.15),
          reason: 'right and wrong must be far apart, whatever the absolute '
              'numbers turn out to be after calibration');
      expect(wrong.worstJoint, isNotNull);
      expect(
        wrong.worstJoint!.id,
        anyOf('left_upper_arm', 'right_upper_arm', 'left_forearm',
            'right_forearm', 'left_shoulder', 'right_shoulder'),
        reason: 'the fault should be attributed to the arms, which is where it '
            'actually is',
      );
    });

    test('survives realistic tracker noise', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: SyntheticNoise.jitter(
          basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
          seed: 42,
          sigma: 0.004,
        ),
      );
      expect(e.reliable, isTrue, reason: e.unreliableReason);
      expect(e.shapeScore, greaterThan(0.90),
          reason: 'landmark jitter must not read as a technique error');
    });

    test('refuses to score an attempt it could barely see', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: SyntheticNoise.occlude(
          basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
          LmRegion.fullBody,
        ),
      );
      expect(e.reliable, isFalse);
      expect(e.unreliableReason, contains('coverage'));
    });

    test('a briefly occluded limb is excluded, not blamed', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: SyntheticNoise.occlude(
          basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
          <int>[Lm.rightWrist],
          fromIndex: 4,
          toIndex: 9,
        ),
      );
      expect(e.reliable, isTrue, reason: e.unreliableReason);
      final JointSummary forearm = e.jointSummaries
          .firstWhere((JointSummary j) => j.id == 'right_forearm');
      expect(forearm.coverage, lessThan(1.0));
      expect(e.worstJoint?.id, isNot('right_forearm'),
          reason: 'a joint we could not see must not become the correction');
    });
  });

  group('SequenceComparator — timing', () {
    test('a step performed on the beat is graded on the beat', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
        moments: moments,
        beats: onTimeline,
      );

      expect(e.momentTimings, hasLength(1));
      expect(e.momentTimings.first.judgement.verdict, TimingVerdict.onBeat);
      expect(e.timingSummary!.onBeatRatio, 1.0);
    });

    test('a late step is caught as timing, not as a shape fault', () {
      // The single most important behaviour of the whole engine: the movement
      // was right, the moment was wrong, and the two must not be confused.
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs)
            .sample(fps: 30, timeShiftUs: 200000),
        moments: moments,
        beats: onTimeline,
      );

      expect(e.shapeScore, greaterThan(0.97),
          reason: 'the step itself was performed correctly');
      expect(e.momentTimings.first.judgement.verdict, TimingVerdict.late);
      expect(e.momentTimings.first.judgement.offsetMs, closeTo(200, 1));
    });

    test('audio latency compensation rescues an unfairly-late verdict', () {
      // Same performance, but now the engine knows the user heard the beat
      // 200 ms after it was scheduled. They were on time all along.
      const PerceivedBeatTimeline compensated = PerceivedBeatTimeline(
        grid: ConstantTempoBeatGrid(bpm: 120),
        latency: AudioLatencyProfile(
          outputLatencyUs: 0,
          userOffsetUs: 200000,
          route: AudioRoute.bluetooth,
        ),
      );

      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs)
            .sample(fps: 30, timeShiftUs: 200000),
        moments: moments,
        beats: compensated,
      );

      expect(e.momentTimings.first.judgement.verdict, TimingVerdict.onBeat);
      expect(e.momentTimings.first.judgement.offsetMs, closeTo(0, 1));
    });

    test('composite score weights timing alongside shape', () {
      final AttemptEvaluation onTime = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs).sample(fps: 30),
        moments: moments,
        beats: onTimeline,
      );
      final AttemptEvaluation late = SequenceComparator().evaluate(
        reference: reference(),
        learner: basicSideStep(beatIntervalUs: beatUs)
            .sample(fps: 30, timeShiftUs: 200000),
        moments: moments,
        beats: onTimeline,
      );

      expect(onTime.shapeScore, closeTo(late.shapeScore, 0.01));
      expect(late.compositeScore(), lessThan(onTime.compositeScore()),
          reason: 'a perfect shape off the beat does not read as dancing');
    });
  });

  group('SequenceComparator — degenerate input', () {
    test('an empty attempt is unreliable, not a zero score', () {
      final AttemptEvaluation e = SequenceComparator().evaluate(
        reference: reference(),
        learner: const <PoseFrame>[],
      );
      expect(e.reliable, isFalse);
      expect(e.unreliableReason, 'empty sequence');
    });

    test('sequence limits return a named unreliable result before scoring', () {
      final List<PoseFrame> frames = reference();
      final AttemptEvaluation e = SequenceComparator(
        dtw: const Dtw(maxSequenceLength: 4),
      ).evaluate(reference: frames, learner: frames);

      expect(e.reliable, isFalse);
      expect(e.unreliableReason, DtwLimitReason.sequenceLengthExceeded.code);
      expect(e.alignment.pathRef, isEmpty);
      expect(e.jointSummaries, isEmpty);
    });

    test('cell limits return a distinct named unreliable result', () {
      final List<PoseFrame> frames = reference().take(5).toList(growable: false);
      final AttemptEvaluation e = SequenceComparator(
        dtw: const Dtw(
          bandRadius: 4,
          bandRadiusS: null,
          minBandRadius: 4,
          maxSequenceLength: 5,
          maxStoredCells: 20,
        ),
      ).evaluate(reference: frames, learner: frames);

      expect(e.reliable, isFalse);
      expect(e.unreliableReason, DtwLimitReason.storedCellLimitExceeded.code);
      expect(e.alignment.pathRef, isEmpty);
    });
  });
}
