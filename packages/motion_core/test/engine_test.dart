import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The side step with a short hold on the closing position.
///
/// The settle matters and is not padding. Smoothing deliberately lags — that is
/// what buys us jitter rejection — so a take that ends the instant the movement
/// does never quite returns to its resting value, and a "recovered" threshold
/// set from the ideal pose will never fire. Real dancers hold the close; real
/// fixtures must too, and rule thresholds have to be authored against the
/// filtered signal rather than the geometry on paper.
SyntheticSequence sideStepWithSettle() => SyntheticSequence(<SyntheticKeyframe>[
      ...basicSideStep().keyframes,
      const SyntheticKeyframe(1400000, SyntheticPose.neutral),
    ]);

/// A three-phase side step, expressed the way a rule set would express it:
/// thresholds on one trunk-relative orientation angle.
List<PhaseDefinition> sideStepPhases({int? readyTimeoutUs}) => <PhaseDefinition>[
      PhaseDefinition(
        id: 'ready',
        enter: (PhaseContext c) => (c.angle('left_thigh') ?? 0) > 3.0,
        requiredLandmarks: LmRegion.leftLeg,
        timeoutUs: readyTimeoutUs,
      ),
      PhaseDefinition(
        id: 'step_out',
        enter: (PhaseContext c) => (c.angle('left_thigh') ?? 9) < 2.95,
        requiredLandmarks: LmRegion.leftLeg,
        timeoutUs: 2000000,
      ),
      PhaseDefinition(
        id: 'recovered',
        enter: (PhaseContext c) => (c.angle('left_thigh') ?? 0) > 3.0,
        requiredLandmarks: LmRegion.leftLeg,
        isTerminal: true,
      ),
    ];

AttemptRun? runMachine(PhaseStateMachine m, List<PoseFrame> frames) {
  final PosePipeline pipeline = PosePipeline();
  for (final PoseFrame f in frames) {
    final ProcessedFrame p = pipeline.process(f);
    final AttemptRun? run = m.update(p.raw, p.angles);
    if (run != null) return run;
  }
  return m.flush();
}

void main() {
  group('PhaseStateMachine', () {
    test('walks a step through its phases and completes', () {
      final PhaseStateMachine m = PhaseStateMachine(
        techniqueId: 'side_step',
        phases: sideStepPhases(),
      );
      final AttemptRun? run =
          runMachine(m, sideStepWithSettle().sample(fps: 60));

      expect(run, isNotNull);
      expect(run!.outcome, AttemptOutcome.completed);
      expect(
        run.transitions.map((PhaseTransition t) => t.toPhase),
        <String>['ready', 'step_out', 'recovered'],
      );
      expect(run.timeOfPhaseUs('step_out'), isNotNull);
      expect(run.phaseDurationUs('step_out'), greaterThan(0));
    });

    test('phase timestamps are where timing metrics come from', () {
      // Rule D2: never derive speed from inter-frame pixel motion. The phase
      // boundary survives motion blur because it is defined by posture.
      final PhaseStateMachine m = PhaseStateMachine(
        techniqueId: 'side_step',
        phases: sideStepPhases(),
      );
      final AttemptRun run =
          runMachine(m, sideStepWithSettle().sample(fps: 60))!;
      final int? outAt = run.timeOfPhaseUs('step_out');
      expect(outAt, isNotNull);
      // The step reaches its extreme around the halfway keyframe (500 ms).
      expect(outAt!, inInclusiveRange(200000, 700000));
    });

    test('times out rather than parking forever on a missed exit', () {
      final PhaseStateMachine m = PhaseStateMachine(
        techniqueId: 'stuck',
        phases: <PhaseDefinition>[
          PhaseDefinition(
            id: 'ready',
            enter: (PhaseContext c) => true,
            requiredLandmarks: LmRegion.leftLeg,
            timeoutUs: 100000,
          ),
          PhaseDefinition(
            id: 'never',
            enter: (PhaseContext c) => false,
            requiredLandmarks: LmRegion.leftLeg,
          ),
        ],
      );
      final AttemptRun? run =
          runMachine(m, sideStepWithSettle().sample(fps: 60));
      expect(run!.outcome, AttemptOutcome.timedOut);
    });

    test('abandons an attempt it stopped being able to see', () {
      final List<PoseFrame> frames = sideStepWithSettle().sample(fps: 60);
      // Occlude the tracked leg for well past the grace period.
      final List<PoseFrame> blinded = SyntheticNoise.occlude(
        frames,
        LmRegion.leftLeg,
        fromIndex: 5,
      );
      final PhaseStateMachine m = PhaseStateMachine(
        techniqueId: 'side_step',
        phases: sideStepPhases(),
        lostTrackingGraceUs: 200000,
      );
      final AttemptRun? run = runMachine(m, blinded);
      expect(run!.outcome, AttemptOutcome.lostTracking);
    });

    test('tolerates a brief tracking blackout', () {
      final List<PoseFrame> frames = sideStepWithSettle().sample(fps: 60);
      final List<PoseFrame> blinked = SyntheticNoise.occlude(
        frames,
        LmRegion.leftLeg,
        fromIndex: 2,
        toIndex: 5,
      );
      final PhaseStateMachine m = PhaseStateMachine(
        techniqueId: 'side_step',
        phases: sideStepPhases(),
        lostTrackingGraceUs: 500000,
      );
      final AttemptRun? run = runMachine(m, blinked);
      expect(run!.outcome, AttemptOutcome.completed);
    });
  });

  group('FeedbackPrioritizer', () {
    FeedbackCandidate c(
      String code,
      FeedbackSeverity s,
      int tUs, {
      double confidence = 1.0,
    }) =>
        FeedbackCandidate(
          code: code,
          severity: s,
          tUs: tUs,
          confidence: confidence,
        );

    test('says exactly one thing at a time, worst first', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer();
      final FeedbackDecision d = p.consider(<FeedbackCandidate>[
        c('ARM_STYLING', FeedbackSeverity.minor, 0),
        c('STEP_ORDER_WRONG', FeedbackSeverity.critical, 0),
        c('WEIGHT_NOT_TRANSFERRED', FeedbackSeverity.major, 0),
      ], 0);

      expect(d.willSpeak, isTrue);
      expect(d.candidate!.code, 'STEP_ORDER_WRONG');
    });

    test('never speaks a low-confidence finding', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer();
      final FeedbackDecision d = p.consider(<FeedbackCandidate>[
        c('MAYBE_LATE', FeedbackSeverity.major, 0, confidence: 0.3),
      ], 0);
      expect(d.willSpeak, isFalse);
    });

    test('holds a global cooldown between cues', () {
      final FeedbackPrioritizer p =
          FeedbackPrioritizer(globalCooldownUs: 2000000);
      expect(p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 0)], 0)
          .willSpeak, isTrue);
      expect(
          p.consider(
              <FeedbackCandidate>[c('B', FeedbackSeverity.major, 500000)], 500000)
              .willSpeak,
          isFalse);
      expect(
          p.consider(
              <FeedbackCandidate>[c('B', FeedbackSeverity.major, 2500000)], 2500000)
              .willSpeak,
          isTrue);
    });

    test('repeats the same cue only after a longer wait, and counts repeats', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer(
        globalCooldownUs: 100000,
        perCodeCooldownUs: 5000000,
      );
      p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 0)], 0);
      expect(
          p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 1000000)],
              1000000).willSpeak,
          isFalse);
      final FeedbackDecision later = p.consider(
          <FeedbackCandidate>[c('A', FeedbackSeverity.major, 6000000)], 6000000);
      expect(later.willSpeak, isTrue);
      expect(later.repeatCount, 1,
          reason: 'content varies its wording when a cue has to be repeated');
    });

    test('stays silent through a counted phrase', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer();
      p.requestQuietUntil(4000000);
      expect(
          p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 1000000)],
              1000000).willSpeak,
          isFalse);
      expect(
          p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 5000000)],
              5000000).willSpeak,
          isTrue);
    });

    test('safety interrupts anything', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer();
      p.requestQuietUntil(9000000);
      p.consider(<FeedbackCandidate>[c('A', FeedbackSeverity.major, 0)], 0);
      final FeedbackDecision d = p.consider(
        <FeedbackCandidate>[c('SPACE_UNSAFE', FeedbackSeverity.safety, 100000)],
        100000,
      );
      expect(d.willSpeak, isTrue);
      expect(d.candidate!.code, 'SPACE_UNSAFE');
    });

    test('closes the loop when a named fault is fixed', () {
      final FeedbackPrioritizer p = FeedbackPrioritizer();
      p.consider(<FeedbackCandidate>[c('STEP_LATE', FeedbackSeverity.major, 0)], 0);
      expect(p.outstandingCodes, contains('STEP_LATE'));

      final FeedbackCandidate? ok = p.resolve('STEP_LATE', 3000000);
      expect(ok, isNotNull);
      expect(ok!.severity, FeedbackSeverity.positive);
      expect(p.outstandingCodes, isEmpty);
      expect(p.resolve('STEP_LATE', 4000000), isNull,
          reason: 'a fault is only confirmed fixed once');
    });
  });
}
