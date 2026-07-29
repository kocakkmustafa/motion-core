import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// L-139 / 0.8.0 — CLI cycle segmentation.
///
/// The defect this guards against: whole-video DTW on takes with different
/// rep counts bends cycle boundaries to make the lengths meet (4 reps warped
/// onto 9) and reports the bending as 34-43° of instructor "disagreement".
/// The acceptance criterion is Lissom's: two rep-segments cut from the same
/// source must agree to ~zero.

/// Tiles a one-rep phrase into [reps] repetitions with a short return-to-home
/// gap between them — periodic material with a known ground-truth period.
SyntheticSequence tiled(SyntheticSequence seq, int reps,
    {int restUs = 500000}) {
  final int span = seq.endUs - seq.startUs + restUs;
  return SyntheticSequence(<SyntheticKeyframe>[
    for (int k = 0; k < reps; k++)
      for (final SyntheticKeyframe kf in seq.keyframes)
        SyntheticKeyframe(k * span + (kf.tUs - seq.startUs), kf.pose),
  ]);
}

List<JointAngleVector> jitteredSeries(SyntheticSequence seq,
        {required int seed, double tempoRatio = 1.0}) =>
    angleSeries(SyntheticNoise.jitter(
        seq.sample(fps: 30, tempoRatio: tempoRatio),
        seed: seed,
        sigma: 0.004));

void main() {
  group('CyclePeriodEstimator (M-C-25 in Dart)', () {
    test('recovers the ground-truth period of tiled repetitions', () {
      // Phrase spans 2.0 s + 0.5 s rest → period 2.5 s = 75 frames at 30 fps.
      final List<JointAngleVector> series =
          jitteredSeries(tiled(fourCountPhrase(), 6), seed: 7);
      final CyclePeriodEstimate p =
          const CyclePeriodEstimator().estimate(series);
      expect(p.measured, isTrue, reason: p.reason);
      expect(p.periodFrames, closeTo(75, 3));
      expect(p.periodicity, greaterThan(0.5));
    });

    test('a held pose stays unmeasured — centring kills the static signal',
        () {
      final SyntheticSequence hold = SyntheticSequence(<SyntheticKeyframe>[
        const SyntheticKeyframe(0, SyntheticPose.neutral),
        const SyntheticKeyframe(6000000, SyntheticPose.neutral),
      ]);
      final CyclePeriodEstimate p = const CyclePeriodEstimator()
          .estimate(jitteredSeries(hold, seed: 3));
      expect(p.measured, isFalse);
    });

    test('moving-but-not-repeating is rejected — the M-C-25 negative', () {
      // One slow 10 s raise: continuous motion, zero repetition. A global-max
      // ACF would report the search floor as a "period" here.
      final SyntheticSequence drift = SyntheticSequence(<SyntheticKeyframe>[
        const SyntheticKeyframe(0, SyntheticPose.neutral),
        SyntheticKeyframe(
            10000000, SyntheticPose.neutral.copyWith(leftUpperArm: -1.2)),
      ]);
      final CyclePeriodEstimate p = const CyclePeriodEstimator()
          .estimate(jitteredSeries(drift, seed: 5));
      // Rejection can land on either honest layer — no prominent peak, or a
      // peak too weak to assert (measured on this material: periodicity
      // 0.16, from the smoothstep easing's inflection). What must never
      // happen is a period being reported.
      expect(p.measured, isFalse);
      expect(p.periodicity, lessThan(0.5));
    });
  });

  group('cycle segmentation acceptance (L-139)', () {
    test('two rep-segments cut from the same source agree to ~zero', () {
      // Noise-free on purpose: with jitter the comparison measures the
      // jitter floor (~3° — short limb segments amplify coordinate noise),
      // not the alignment. Clean material isolates the claim under test:
      // segments cut at the measured period are phase-aligned. A period
      // wrong by even 3 frames would read ~11° at this phrase's peak
      // angular velocity (~2 rad/s).
      final List<JointAngleVector> series =
          angleSeries(tiled(fourCountPhrase(), 6).sample(fps: 30));
      final CyclePeriodEstimate p =
          const CyclePeriodEstimator().estimate(series);
      expect(p.measured, isTrue, reason: p.reason);
      final int period = p.periodFrames;

      final List<JointAngleVector> a = series.sublist(0, period);
      final List<JointAngleVector> b = series.sublist(period, 2 * period);
      double mean = 0;
      for (int f = 0; f < period; f++) {
        mean += meanAngleDeviationDegrees(a[f], b[f]);
      }
      mean /= period;
      // "~zero" versus the 34-43° of phantom disagreement whole-video DTW
      // manufactured on real harvest takes (L-139).
      expect(mean, lessThan(0.5));
    });

    test(
        'takes with different rep counts build a reference without phantom '
        'disagreement', () {
      Fixture fx(String id, int reps,
              {double tempo = 1.0, required int seed}) =>
          Fixture(
            app: 'lissom',
            technique: 'deep_squat',
            frames: SyntheticNoise.jitter(
                tiled(fourCountPhrase(), reps)
                    .sample(fps: 30, tempoRatio: tempo),
                seed: seed,
                sigma: 0.004),
            provenance: ProvenanceInfo(channel: 'ch-$id'),
          );
      final Map<String, Fixture> fixtures = <String, Fixture>{
        'a': fx('a', 3, seed: 1),
        'b': fx('b', 4, tempo: 0.97, seed: 2),
        'c': fx('c', 6, tempo: 1.05, seed: 3),
        'd': fx('d', 5, seed: 4),
      };
      final Map<String, dynamic> artifact = const ReferenceCli()
          .buildArtifact(technique: 'deep_squat', fixturesById: fixtures);

      final Map<String, dynamic> seg =
          artifact['cycleSegmentation'] as Map<String, dynamic>;
      expect(seg['state'], 'applied');
      expect(seg['excludedUnalignable'], isEmpty);

      final Map<String, dynamic> r = artifact['result'] as Map<String, dynamic>;
      expect(r['contributingTakes'], 4);
      // The defect this exists to prevent: rep-count differences read as
      // instructor disagreement and takes get excluded as outliers.
      expect(r['excludedOutlierIds'], isEmpty);
      // The reference is one cycle now, not a whole video.
      expect(r['length'], lessThan(120));

      for (final dynamic t in artifact['takes'] as List<dynamic>) {
        final Map<String, dynamic> rep = t as Map<String, dynamic>;
        expect(rep['cycleCount'], isNotNull,
            reason: 'cycle counts are measured now — null was the honest '
                'value only while nothing measured them');
        expect(rep['cycleCount'] as int, greaterThanOrEqualTo(2));
        expect(rep['periodFrames'], isNotNull);
      }
    });

    test('static material declares notApplied and still builds', () {
      final SyntheticSequence hold = SyntheticSequence(<SyntheticKeyframe>[
        const SyntheticKeyframe(0, SyntheticPose.neutral),
        const SyntheticKeyframe(4000000, SyntheticPose.neutral),
      ]);
      Fixture fx(String id, int seed) => Fixture(
            app: 'jablab',
            technique: 'stance',
            frames: SyntheticNoise.jitter(hold.sample(fps: 30),
                seed: seed, sigma: 0.004),
            provenance: ProvenanceInfo(channel: 'ch-$id'),
          );
      final Map<String, dynamic> artifact =
          const ReferenceCli().buildArtifact(
        technique: 'stance',
        fixturesById: <String, Fixture>{
          'a': fx('a', 21),
          'b': fx('b', 22),
          'c': fx('c', 23),
        },
      );
      final Map<String, dynamic> seg =
          artifact['cycleSegmentation'] as Map<String, dynamic>;
      expect(seg['state'], 'notApplied');
      expect((artifact['result'] as Map<String, dynamic>)['contributingTakes'],
          3);
      // Honest null survives: nothing measured a cycle count here.
      for (final dynamic t in artifact['takes'] as List<dynamic>) {
        expect((t as Map<String, dynamic>)['cycleCount'], isNull);
      }
    });

    test('an aperiodic take inside a periodic pool is excluded by name', () {
      Fixture rep(String id, int reps, int seed) => Fixture(
            app: 'lissom',
            technique: 'deep_squat',
            frames: SyntheticNoise.jitter(
                tiled(fourCountPhrase(), reps).sample(fps: 30),
                seed: seed,
                sigma: 0.004),
            provenance: ProvenanceInfo(channel: 'ch-$id'),
          );
      final SyntheticSequence hold = SyntheticSequence(<SyntheticKeyframe>[
        const SyntheticKeyframe(0, SyntheticPose.neutral),
        const SyntheticKeyframe(8000000, SyntheticPose.neutral),
      ]);
      final Map<String, Fixture> fixtures = <String, Fixture>{
        'a': rep('a', 3, 31),
        'b': rep('b', 4, 32),
        'c': rep('c', 5, 33),
        'still': Fixture(
          app: 'lissom',
          technique: 'deep_squat',
          frames: SyntheticNoise.jitter(hold.sample(fps: 30),
              seed: 34, sigma: 0.004),
          provenance: ProvenanceInfo(channel: 'ch-still'),
        ),
      };
      final Map<String, dynamic> artifact = const ReferenceCli()
          .buildArtifact(technique: 'deep_squat', fixturesById: fixtures);
      final Map<String, dynamic> seg =
          artifact['cycleSegmentation'] as Map<String, dynamic>;
      expect(seg['state'], 'applied');
      expect((seg['excludedUnalignable'] as Map<String, String>).keys,
          <String>['still']);
      expect((artifact['result'] as Map<String, dynamic>)['contributingTakes'],
          3);
    });

    test(
        'a near-frameless take in a periodic pool is excluded by name — '
        'not stretched into fake variance (review HIGH-1)', () {
      // Measured by the 0.7.3 review: a 1-frame take warped across a moving
      // reference flipped five joints' tolerance source floor→variance —
      // the artifact CLAIMED instructor disagreement that was actually a
      // degenerate take. On periodic material the period gate closes this:
      // 1 frame cannot demonstrate a period, so it is named, not averaged.
      Fixture rep(String id, int reps, int seed) => Fixture(
            app: 'lissom',
            technique: 'deep_squat',
            frames: SyntheticNoise.jitter(
                tiled(fourCountPhrase(), reps).sample(fps: 30),
                seed: seed,
                sigma: 0.004),
            provenance: ProvenanceInfo(channel: 'ch-$id'),
          );
      final Fixture oneFrame = Fixture(
        app: 'lissom',
        technique: 'deep_squat',
        frames: fourCountPhrase().sample(fps: 30).sublist(0, 1),
        provenance: ProvenanceInfo(channel: 'ch-frozen'),
      );
      final Map<String, dynamic> artifact =
          const ReferenceCli().buildArtifact(
        technique: 'deep_squat',
        fixturesById: <String, Fixture>{
          'a': rep('a', 3, 41),
          'b': rep('b', 4, 42),
          'c': rep('c', 5, 43),
          'frozen': oneFrame,
        },
      );
      final Map<String, dynamic> seg =
          artifact['cycleSegmentation'] as Map<String, dynamic>;
      expect((seg['excludedUnalignable'] as Map<String, String>).keys,
          contains('frozen'));
      expect(
          (artifact['result'] as Map<String, dynamic>)['contributingTakes'],
          3);
    });
  });
}
