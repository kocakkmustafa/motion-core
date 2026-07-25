import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConstantTempoBeatGrid', () {
    const ConstantTempoBeatGrid grid =
        ConstantTempoBeatGrid(bpm: 120, firstBeatUs: 0);

    test('maps beats to time and back', () {
      expect(grid.beatIntervalUs, 500000);
      expect(grid.timeOfBeatUs(4), 2000000);
      expect(grid.beatPositionAt(750000), closeTo(1.5, 1e-9));
      expect(grid.beatIndexAt(750000), 1);
      expect(grid.phaseAt(750000), closeTo(0.5, 1e-9));
    });

    test('honours a downbeat that is not at time zero', () {
      const ConstantTempoBeatGrid offset =
          ConstantTempoBeatGrid(bpm: 120, firstBeatUs: 320000);
      expect(offset.timeOfBeatUs(0), 320000);
      expect(offset.nearestBeatIndexAt(820000), 1);
      expect(offset.offsetToNearestBeatUs(840000), 20000);
    });

    test('reports bar position for 8-count material', () {
      final (int bar, int beat) = grid.barPositionAt(2600000);
      expect(bar, 1);
      expect(beat, 1);
      expect(grid.phraseStartBeatAt(2600000), 0);
      expect(grid.phraseStartBeatAt(4600000), 8);
    });

    test('re-tempos for slow practice without moving the downbeat', () {
      final ConstantTempoBeatGrid half = grid.atTempoRatio(0.5);
      expect(half.bpm, 60);
      expect(half.timeOfBeatUs(0), grid.timeOfBeatUs(0));
    });
  });

  group('ExplicitBeatGrid', () {
    test('derives tempo from the median gap, resisting a bad beat', () {
      // A single mis-detected beat must not drag the tempo estimate: with a
      // mean it would, and every tempo-scaled tolerance would inherit the error.
      final ExplicitBeatGrid g = ExplicitBeatGrid(beatTimesUs: <int>[
        0, 500000, 1000000, 1500000, 1520000, 2000000, 2500000,
      ]);
      expect(g.bpm, closeTo(120, 1));
    });

    test('interpolates between annotated beats', () {
      final ExplicitBeatGrid g =
          ExplicitBeatGrid(beatTimesUs: <int>[0, 500000, 1010000]);
      expect(g.beatPositionAt(250000), closeTo(0.5, 1e-9));
      expect(g.beatPositionAt(755000), closeTo(1.5, 1e-9));
      expect(g.timeOfBeatUs(2), 1010000);
    });

    test('extrapolates outside the annotated range', () {
      final ExplicitBeatGrid g =
          ExplicitBeatGrid(beatTimesUs: <int>[1000000, 1500000]);
      expect(g.timeOfBeatUs(-1), 500000);
      expect(g.timeOfBeatUs(3), 2500000);
    });
  });

  group('PerceivedBeatTimeline', () {
    const ConstantTempoBeatGrid grid = ConstantTempoBeatGrid(bpm: 120);

    test('shifts beats by the output latency', () {
      // Platform-reported latency is unreliable on wireless routes, so the
      // measured user offset is what makes this honest.
      const PerceivedBeatTimeline t = PerceivedBeatTimeline(
        grid: grid,
        latency: AudioLatencyProfile(
          outputLatencyUs: 60000,
          userOffsetUs: 140000,
          route: AudioRoute.bluetooth,
        ),
      );
      expect(t.latency.totalUs, 200000);
      expect(t.perceivedTimeOfBeatUs(1), 700000);
      expect(t.offsetFromNearestBeatUs(700000), 0);
      expect(t.latency.isCalibrated, isTrue);
    });

    test('an uncompensated route makes an on-time dancer look late', () {
      const PerceivedBeatTimeline uncompensated =
          PerceivedBeatTimeline(grid: grid);
      const PerceivedBeatTimeline compensated = PerceivedBeatTimeline(
        grid: grid,
        latency: AudioLatencyProfile(userOffsetUs: 200000),
      );
      // The dancer moves 200 ms after the scheduled beat because that is when
      // they actually heard it.
      expect(uncompensated.offsetFromNearestBeatUs(700000), 200000);
      expect(compensated.offsetFromNearestBeatUs(700000), 0);
    });
  });

  group('TimingWindows', () {
    test('floor protects fast tempos, ceiling protects slow ones', () {
      const TimingWindows w = TimingWindows.beginner;
      // 160 BPM: 15% of a beat would be 56 ms — tighter than we can measure.
      expect(w.onBeatUs(375000), 80000);
      // 120 BPM: still on the floor.
      expect(w.onBeatUs(500000), 80000);
      // 60 BPM: relative band applies.
      expect(w.onBeatUs(1000000), 150000);
      // 40 BPM: ceiling stops the band becoming meaningless.
      expect(w.onBeatUs(1500000), 200000);
    });

    test('tightens with level', () {
      const int interval = 1000000;
      expect(TimingWindows.advanced.onBeatUs(interval),
          lessThan(TimingWindows.intermediate.onBeatUs(interval)));
      expect(TimingWindows.intermediate.onBeatUs(interval),
          lessThan(TimingWindows.beginner.onBeatUs(interval)));
    });
  });

  group('TimingJudge', () {
    const PerceivedBeatTimeline timeline =
        PerceivedBeatTimeline(grid: ConstantTempoBeatGrid(bpm: 120));
    const TimingJudge judge = TimingJudge();

    test('grades offsets into bands', () {
      expect(judge.judge(500000, timeline).verdict, TimingVerdict.onBeat);
      expect(judge.judge(560000, timeline).verdict, TimingVerdict.onBeat);
      expect(judge.judge(600000, timeline).verdict, TimingVerdict.slightlyLate);
      expect(judge.judge(400000, timeline).verdict, TimingVerdict.slightlyEarly);
      expect(judge.judge(680000, timeline).verdict, TimingVerdict.late);
      expect(judge.judge(320000, timeline).verdict, TimingVerdict.early);
    });

    test('reports offsets in beats as well as milliseconds', () {
      final TimingJudgement j = judge.judge(625000, timeline);
      expect(j.offsetMs, closeTo(125, 1e-9));
      expect(j.offsetInBeats, closeTo(0.25, 1e-9));
    });
  });

  group('TimingSummary', () {
    const PerceivedBeatTimeline timeline =
        PerceivedBeatTimeline(grid: ConstantTempoBeatGrid(bpm: 120));
    const TimingJudge judge = TimingJudge();

    List<TimingJudgement> series(List<int> offsetsUs) => <TimingJudgement>[
          for (int i = 0; i < offsetsUs.length; i++)
            judge.judge(500000 * (i + 1) + offsetsUs[i], timeline),
        ];

    test('separates systematic bias from spread', () {
      final TimingSummary s = TimingSummary.from(
        series(<int>[148000, 152000, 150000, 149000, 151000,
            150000, 153000, 147000, 150000, 150000]),
        beatIntervalUs: 500000,
      );
      expect(s.meanOffsetMs, closeTo(150, 1));
      expect(s.stdDevMs, lessThan(5));
      expect(s.suggestsCalibrationIssue, isTrue,
          reason: 'a large, tight bias is the signature of uncalibrated audio, '
              'not of a dancer who cannot keep time');
    });

    test('does not blame calibration for genuine imprecision', () {
      final TimingSummary s = TimingSummary.from(
        series(<int>[-160000, 140000, -90000, 175000, -130000,
            120000, -170000, 95000, -110000, 155000]),
        beatIntervalUs: 500000,
      );
      expect(s.meanOffsetUs.abs(), lessThan(60000));
      expect(s.stdDevMs, greaterThan(80));
      expect(s.suggestsCalibrationIssue, isFalse);
    });

    test('is empty-safe', () {
      final TimingSummary s =
          TimingSummary.from(const <TimingJudgement>[], beatIntervalUs: 500000);
      expect(s.count, 0);
      expect(s.onBeatRatio, 0);
      expect(s.suggestsCalibrationIssue, isFalse);
    });
  });
}
