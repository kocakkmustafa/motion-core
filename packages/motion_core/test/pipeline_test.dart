import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('ConfidenceGate', () {
    test('accepts a cleanly tracked frame', () {
      final PoseFrame f =
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0);
      final FrameQuality q = const ConfidenceGate().evaluate(f);
      expect(q.judgeable, isTrue);
      expect(q.describe(), 'ok');
    });

    test('names the landmarks it could not see', () {
      final PoseFrame f = SyntheticNoise.occlude(
        <PoseFrame>[
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0)
        ],
        <int>[Lm.rightWrist, Lm.rightElbow],
      ).first;

      final FrameQuality q = const ConfidenceGate().evaluate(f);
      expect(q.judgeable, isFalse);
      expect(q.issue, QualityIssue.lowTrackingConfidence);
      expect(q.describe(), contains('right_wrist'));
    });

    test('detects a dancer who stepped out of frame', () {
      final PoseFrame f = const SyntheticPoseBuilder()
          .build(SyntheticPose.neutral.copyWith(rootX: 1.4), tUs: 0);
      final FrameQuality q = const ConfidenceGate().evaluate(f);
      expect(q.judgeable, isFalse);
      expect(q.issue, QualityIssue.outOfFrame);
    });

    test('an unreliable torso short-circuits everything', () {
      // Nothing can be normalized without the torso, so there is no honest way
      // to judge any limb either.
      final PoseFrame f = SyntheticNoise.occlude(
        <PoseFrame>[
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0)
        ],
        <int>[Lm.leftHip],
      ).first;
      final FrameQuality q = const ConfidenceGate().evaluate(f);
      expect(q.issue, QualityIssue.torsoUnreliable);
    });
  });

  group('PoseSmoother', () {
    test('suppresses jitter on a held pose', () {
      final List<PoseFrame> still = List<PoseFrame>.generate(
        60,
        (int i) => const SyntheticPoseBuilder()
            .build(SyntheticPose.neutral, tUs: i * 16667),
        growable: false,
      );
      final List<PoseFrame> noisy =
          SyntheticNoise.jitter(still, seed: 7, sigma: 0.006);

      final PoseSmoother smoother = PoseSmoother();
      final List<PoseFrame> cleaned =
          noisy.map(smoother.smooth).toList(growable: false);

      double spread(List<PoseFrame> fs) {
        final List<double> xs = fs
            .skip(20)
            .map((PoseFrame f) => f[Lm.leftWrist].x)
            .toList(growable: false);
        final double mean = xs.reduce((double a, double b) => a + b) / xs.length;
        double v = 0;
        for (final double x in xs) {
          v += (x - mean) * (x - mean);
        }
        return v / xs.length;
      }

      expect(spread(cleaned), lessThan(spread(noisy) * 0.5));
    });

    test('leaves visibility untouched', () {
      // Smoothing visibility would let a confident past frame prop up a lost
      // present one, turning "I cannot see it" into a delayed false verdict.
      final PoseFrame f = SyntheticNoise.occlude(
        <PoseFrame>[
          const SyntheticPoseBuilder().build(SyntheticPose.neutral, tUs: 0)
        ],
        <int>[Lm.leftWrist],
      ).first;
      final PoseFrame out = PoseSmoother().smooth(f);
      expect(out[Lm.leftWrist].visibility, f[Lm.leftWrist].visibility);
    });
  });

  group('Fixture', () {
    Fixture sample() => Fixture(
          app: 'choreia',
          technique: 'side_step',
          modelVersion: 'blazepose-ghum-full-1.0',
          recordingMeta: const RecordingMeta(
            device: 'iPhone 17 Pro',
            fps: 30,
            lighting: 'dim',
            bodyProfile: 'tall-slim',
            cameraSetup: 'phone-on-floor-2m',
          ),
          frames: basicSideStep().sample(fps: 30),
          labels: const <FixtureLabel>[
            FixtureLabel(
              tStartUs: 400000,
              tEndUs: 600000,
              phase: 'step_out',
              annotator: 'session',
              beatIndex: 1,
            ),
            FixtureLabel(
              tStartUs: 700000,
              tEndUs: 900000,
              errorCode: 'WEIGHT_NOT_TRANSFERRED',
              confidence: 0.8,
              annotator: 'session',
            ),
          ],
          beatTimesUs: const <int>[0, 500000, 1000000],
          bpm: 120,
        );

    test('round-trips through JSON without loss', () {
      final Fixture original = sample();
      final Fixture restored = Fixture.decode(original.encode());

      expect(restored.app, original.app);
      expect(restored.technique, original.technique);
      expect(restored.frames.length, original.frames.length);
      expect(restored.modelVersion, original.modelVersion);
      expect(restored.recordingMeta.lighting, 'dim');
      expect(restored.beatTimesUs, original.beatTimesUs);
      expect(restored.bpm, 120);
      expect(restored.frames.first[Lm.leftWrist].x,
          closeTo(original.frames.first[Lm.leftWrist].x, 1e-12));
      // The model version travels with every frame, so a future model upgrade
      // can never silently reinterpret an old recording.
      expect(restored.frames.first.modelVersion, 'blazepose-ghum-full-1.0');
    });

    test('separates phase labels from error labels', () {
      final Fixture f = sample();
      expect(f.phaseLabels.length, 1);
      expect(f.errorLabels.length, 1);
      expect(f.errorLabels.first.errorCode, 'WEIGHT_NOT_TRANSFERRED');
    });

    test('reports its own frame rate', () {
      expect(sample().measuredFps, closeTo(30, 0.6));
    });

    test('refuses a fixture from a newer schema', () {
      final Map<String, dynamic> json = sample().toJson();
      json['schemaVersion'] = Fixture.currentSchemaVersion + 1;
      expect(() => Fixture.fromJson(json), throwsFormatException);
    });
  });

  group('ReplayHarness', () {
    test('reports how much of a recording was actually judgeable', () {
      final Fixture clean = Fixture(
        app: 'choreia',
        technique: 'side_step',
        frames: basicSideStep().sample(fps: 30),
      );
      expect(ReplayHarness().replay(clean).judgeableRatio, 1.0);

      final Fixture degraded = Fixture(
        app: 'choreia',
        technique: 'side_step',
        frames: SyntheticNoise.occlude(
          basicSideStep().sample(fps: 30),
          <int>[Lm.rightAnkle],
          fromIndex: 10,
        ),
      );
      final ReplayReport report = ReplayHarness().replay(degraded);
      expect(report.judgeableRatio, lessThan(0.5),
          reason: 'a technique that "passes" on mostly-unjudgeable frames has '
              'not been tested, it has been skipped');
    });

    test('slices frames by label for assertions', () {
      final Fixture f = Fixture(
        app: 'choreia',
        technique: 'side_step',
        frames: basicSideStep().sample(fps: 30),
        labels: const <FixtureLabel>[
          FixtureLabel(tStartUs: 400000, tEndUs: 600000, phase: 'step_out'),
        ],
      );
      final ReplayReport r = ReplayHarness().replay(f);
      final List<ProcessedFrame> window = r.forLabel(f.labels.first);
      expect(window, isNotEmpty);
      expect(window.first.tUs, greaterThanOrEqualTo(400000));
      expect(window.last.tUs, lessThanOrEqualTo(600000));
    });
  });
}
