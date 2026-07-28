import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

AttemptProvenance _base({
  PoseModelVariant variant = PoseModelVariant.heavy,
  String sha = 'aaaa',
  String ruleset = 'boxing@1.0.0',
  String metrics = 'metrics@3',
  String calibration = 'cal-1',
}) =>
    AttemptProvenance(
      modelVariant: variant,
      modelVersion: 'pose_landmarker_${variant.name}/float16/1',
      modelSha256: sha,
      rulesetVersion: ruleset,
      metricConfigVersion: metrics,
      calibrationProfileId: calibration,
    );

void main() {
  group('AttemptProvenance (M-F-07)', () {
    test('identical instruments are longitudinally comparable', () {
      expect(_base().isLongitudinallyComparableWith(_base()), isTrue);
    });

    test('a variant change breaks comparability with a named reason', () {
      // M-020: visibility is not comparable across variants, so neither are
      // the scores gated by it.
      final List<String> issues = _base()
          .comparabilityIssues(_base(variant: PoseModelVariant.full));
      expect(issues, hasLength(1));
      expect(issues.single, contains('variant'));
    });

    test('silently different weights under the same name are caught', () {
      // M-L-01: /latest/ served different bytes at an unchanged size. Only
      // the hash notices.
      expect(
        _base().isLongitudinallyComparableWith(_base(sha: 'bbbb')),
        isFalse,
      );
    });

    test('every divergence is reported, not just the first', () {
      final List<String> issues = _base().comparabilityIssues(
          _base(ruleset: 'boxing@2.0.0', metrics: 'metrics@4', calibration: 'cal-2'));
      expect(issues, hasLength(3));
    });

    test('round-trips through JSON', () {
      final AttemptProvenance p = _base();
      final AttemptProvenance back =
          AttemptProvenance.fromJson(p.toJson());
      expect(back.isLongitudinallyComparableWith(p), isTrue);
      expect(back.modelVersion, p.modelVersion);
    });
  });

  group('MotionClock', () {
    test('manual clock refuses to run backwards', () {
      final ManualMotionClock clock = ManualMotionClock(1000);
      clock.advanceUs(500);
      expect(clock.nowUs(), 1500);
      expect(() => clock.advanceUs(-1), throwsA(isA<AssertionError>()));
    });

    test('stopwatch clock is non-decreasing', () {
      final StopwatchMotionClock clock = StopwatchMotionClock.start();
      final int a = clock.nowUs();
      final int b = clock.nowUs();
      expect(b, greaterThanOrEqualTo(a));
    });
  });

  group('CueGate', () {
    test('analysis is dirty during a cue and its ring-out, clean after', () {
      final CueGate gate = CueGate(ringOutUs: 300000);
      expect(gate.isAnalysisClean(0), isTrue);

      gate.cueStarted(1000000);
      expect(gate.isAnalysisClean(1200000), isFalse, reason: 'cue playing');
      gate.cueEnded(2000000);
      expect(gate.isAnalysisClean(2100000), isFalse, reason: 'room ringing');
      expect(gate.isAnalysisClean(2300001), isTrue, reason: 'ring-out over');
      expect(gate.isAnalysisClean(500000), isTrue,
          reason: 'before the cue was always clean');
    });

    test('forgetting old cues does not change verdicts after the horizon',
        () {
      final CueGate gate = CueGate(ringOutUs: 100000);
      gate.cueStarted(0);
      gate.cueEnded(500000);
      gate.cueStarted(10000000);
      gate.cueEnded(10500000);

      gate.forgetBefore(5000000);
      expect(gate.isAnalysisClean(10400000), isFalse,
          reason: 'recent cue must survive the cleanup');
      expect(gate.isAnalysisClean(11000000), isTrue);
    });
  });

  group('TapTestCalibrator (M-F-08)', () {
    const TapTestCalibrator cal = TapTestCalibrator();
    final List<int> clicks =
        List<int>.generate(12, (int i) => 1000000 + i * 500000);

    test('a consistent tapper yields the constant offset', () {
      // User hears everything 180 ms late (bluetooth) and taps what they hear.
      final List<int> taps =
          clicks.map((int c) => c + 180000).toList();
      final TapTestResult r =
          cal.evaluate(scheduledClickUs: clicks, tapUs: taps);
      expect(r.accepted, isTrue);
      expect(r.offsetUs, 180000);
      expect(r.spreadUs, 0);
    });

    test('one wild tap cannot move the estimate', () {
      final List<int> taps = clicks.map((int c) => c + 180000).toList();
      taps[4] += 340000; // distracted tap, still inside the match window
      final TapTestResult r =
          cal.evaluate(scheduledClickUs: clicks, tapUs: taps);
      expect(r.accepted, isTrue);
      expect(r.offsetUs, 180000, reason: 'median + MAD rejection holds');
    });

    test('random flailing is rejected, not averaged into a number', () {
      // Alternating early/late by 300 ms is not a latency — refusing to store
      // it is the honest outcome (a stored garbage offset would bias every
      // timing judgement afterwards).
      final List<int> taps = <int>[
        for (int i = 0; i < clicks.length; i++)
          clicks[i] + (i.isEven ? -300000 : 300000),
      ];
      final TapTestResult r =
          cal.evaluate(scheduledClickUs: clicks, tapUs: taps);
      expect(r.accepted, isFalse);
    });

    test('too few taps is an explicit failure', () {
      final TapTestResult r = cal.evaluate(
        scheduledClickUs: clicks,
        tapUs: <int>[clicks[0] + 100000, clicks[1] + 110000],
      );
      expect(r.accepted, isFalse);
      expect(r.reason, contains('usable taps'));
    });

    test('accepted result folds into a per-route profile', () {
      final List<int> taps = clicks.map((int c) => c + 180000).toList();
      final TapTestResult r =
          cal.evaluate(scheduledClickUs: clicks, tapUs: taps);
      final AudioLatencyProfile p = cal.profileFrom(
        r,
        route: AudioRoute.bluetooth,
        platformReportedLatencyUs: 120000,
      );
      expect(p.totalUs, 180000,
          reason: 'platform estimate + residual = measured end-to-end');
      expect(p.route, AudioRoute.bluetooth);
    });
  });

  group('LatencyCalibrationStore (M-F-08)', () {
    test('profiles are per route and route changes demand recalibration', () {
      final LatencyCalibrationStore store = LatencyCalibrationStore();
      expect(store.needsCalibration(AudioRoute.speaker), isTrue);

      store.store(const AudioLatencyProfile(
        outputLatencyUs: 20000,
        userOffsetUs: 15000,
        route: AudioRoute.speaker,
      ));
      expect(store.needsCalibration(AudioRoute.speaker), isFalse);
      expect(store.needsCalibration(AudioRoute.bluetooth), isTrue,
          reason: 'a speaker calibration says nothing about bluetooth');
    });

    test('round-trips through JSON', () {
      final LatencyCalibrationStore store = LatencyCalibrationStore();
      store.store(const AudioLatencyProfile(
        outputLatencyUs: 100000,
        userOffsetUs: 80000,
        route: AudioRoute.bluetooth,
      ));
      final LatencyCalibrationStore back =
          LatencyCalibrationStore.fromJson(store.toJson());
      expect(back.profileFor(AudioRoute.bluetooth)!.totalUs, 180000);
      expect(back.needsCalibration(AudioRoute.speaker), isTrue);
    });
  });
}
