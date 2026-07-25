import 'dart:math' as math;

import 'audio_timeline.dart';

/// How far off the beat a movement landed.
enum TimingVerdict {
  onBeat,
  slightlyEarly,
  slightlyLate,
  early,
  late,

  /// Beyond any useful window — the movement was not on this beat at all.
  offBeat,

  /// No verdict possible (tracking failure, or no beat reference).
  unjudgeable,
}

extension TimingVerdictInfo on TimingVerdict {
  bool get isAcceptable =>
      this == TimingVerdict.onBeat ||
      this == TimingVerdict.slightlyEarly ||
      this == TimingVerdict.slightlyLate;

  bool get isRushing =>
      this == TimingVerdict.early || this == TimingVerdict.slightlyEarly;

  bool get isDragging =>
      this == TimingVerdict.late || this == TimingVerdict.slightlyLate;
}

/// Tolerance windows: a share of the beat interval, clamped between a floor and
/// a ceiling in absolute time.
///
/// Hybrid on purpose, and clamped at both ends. A purely relative window
/// demands superhuman precision at fast tempos (10% of a beat at 160 BPM is
/// 37 ms — near what a 30 fps camera can resolve at all). A purely absolute one
/// lets a learner sit a fifth of a beat off at 60 BPM and still be told they
/// are on time. The floor protects against the first failure, the ceiling
/// against the second.
///
/// Sources for the magnitudes: rhythm-game judgement windows (osu! OD scale,
/// roughly ±20–150 ms; DDR/StepMania, roughly 17–225 ms) and sensorimotor
/// synchronisation variability in trained versus untrained tappers. Those
/// figures come from finger tapping; whole-body dance variability is larger and
/// has **not** been verified for us, which is why beginner windows sit at the
/// generous end and why measuring our own is a G1 gate item.
final class TimingWindows {
  const TimingWindows({
    required this.onBeatRelative,
    required this.onBeatFloorUs,
    required this.onBeatCeilingUs,
    required this.closeMultiplier,
  });

  /// Share of one beat that counts as on time.
  final double onBeatRelative;

  /// Never demand tighter than this, however fast the music.
  final int onBeatFloorUs;

  /// Never allow looser than this, however slow the music.
  final int onBeatCeilingUs;

  /// The "close" band is this multiple of the on-beat band.
  final double closeMultiplier;

  /// Generous band for learners meeting a step for the first time.
  static const TimingWindows beginner = TimingWindows(
    onBeatRelative: 0.15,
    onBeatFloorUs: 80000,
    onBeatCeilingUs: 200000,
    closeMultiplier: 1.8,
  );

  static const TimingWindows intermediate = TimingWindows(
    onBeatRelative: 0.12,
    onBeatFloorUs: 60000,
    onBeatCeilingUs: 130000,
    closeMultiplier: 1.7,
  );

  static const TimingWindows advanced = TimingWindows(
    onBeatRelative: 0.10,
    onBeatFloorUs: 40000,
    onBeatCeilingUs: 80000,
    closeMultiplier: 1.6,
  );

  int onBeatUs(int beatIntervalUs) => (onBeatRelative * beatIntervalUs)
      .round()
      .clamp(onBeatFloorUs, onBeatCeilingUs);

  int closeUs(int beatIntervalUs) =>
      (onBeatUs(beatIntervalUs) * closeMultiplier).round();

  /// Beyond this the movement belongs to a different beat entirely.
  int offBeatUs(int beatIntervalUs) => (beatIntervalUs * 0.5).round();
}

/// Constants taken from published research, kept separate from the defaults so
/// that adopting one is always a visible decision.
abstract final class SyncConstants {
  /// Negative mean asynchrony reported in sensorimotor synchronisation
  /// studies: people place a movement roughly this far *before* the beat they
  /// are synchronising to, and perceive that as being exactly on it.
  ///
  /// Deliberately **not** applied by default. The published range comes from
  /// finger tapping, and using it unverified would put a systematic bias into
  /// every timing score in the product on the strength of a borrowed number.
  /// Measuring our own value is a V0 gate item; until then this is available to
  /// opt into and to test against, and nothing more.
  static const int literatureNegativeMeanAsynchronyUs = 25000;
}

/// A single timing measurement.
final class TimingJudgement {
  const TimingJudgement({
    required this.verdict,
    required this.offsetUs,
    required this.beatIndex,
    required this.beatIntervalUs,
  });

  const TimingJudgement.unjudgeable()
      : verdict = TimingVerdict.unjudgeable,
        offsetUs = 0,
        beatIndex = -1,
        beatIntervalUs = 0;

  final TimingVerdict verdict;

  /// Signed microseconds from the perceived beat. Positive = late.
  final int offsetUs;

  final int beatIndex;
  final int beatIntervalUs;

  double get offsetMs => offsetUs / 1000.0;

  /// Offset as a fraction of one beat — the tempo-independent view.
  double get offsetInBeats =>
      beatIntervalUs == 0 ? 0 : offsetUs / beatIntervalUs;

  @override
  String toString() => 'TimingJudgement(${verdict.name}, '
      '${offsetMs.toStringAsFixed(0)}ms, beat $beatIndex)';
}

/// Turns a movement timestamp into a timing verdict.
final class TimingJudge {
  const TimingJudge({this.windows = TimingWindows.beginner});

  final TimingWindows windows;

  /// [tUs] is the moment the *scored phase* of the movement occurred — a step
  /// landing, a weight transfer — not the moment the movement started.
  TimingJudgement judge(int tUs, PerceivedBeatTimeline timeline) {
    final int interval = timeline.beatIntervalUs;
    if (interval <= 0) return const TimingJudgement.unjudgeable();

    final int beat = timeline.nearestPerceivedBeatIndexAt(tUs);
    final int offset = tUs - timeline.perceivedTimeOfBeatUs(beat);
    final int abs = offset.abs();

    final TimingVerdict verdict;
    if (abs <= windows.onBeatUs(interval)) {
      verdict = TimingVerdict.onBeat;
    } else if (abs <= windows.closeUs(interval)) {
      verdict = offset < 0
          ? TimingVerdict.slightlyEarly
          : TimingVerdict.slightlyLate;
    } else if (abs <= windows.offBeatUs(interval)) {
      verdict = offset < 0 ? TimingVerdict.early : TimingVerdict.late;
    } else {
      verdict = TimingVerdict.offBeat;
    }

    return TimingJudgement(
      verdict: verdict,
      offsetUs: offset,
      beatIndex: beat,
      beatIntervalUs: interval,
    );
  }
}

/// Aggregate timing over a whole attempt.
final class TimingSummary {
  const TimingSummary({
    required this.count,
    required this.meanOffsetUs,
    required this.stdDevUs,
    required this.onBeatRatio,
    required this.beatIntervalUs,
  });

  final int count;

  /// Systematic bias — a dancer who is *consistently* 120 ms early has a
  /// habit (or an uncalibrated audio route), not a precision problem.
  final int meanOffsetUs;

  /// Spread — this is the actual precision skill, and the number that should
  /// improve with practice.
  final int stdDevUs;

  final double onBeatRatio;
  final int beatIntervalUs;

  double get meanOffsetMs => meanOffsetUs / 1000.0;
  double get stdDevMs => stdDevUs / 1000.0;

  /// True when the error looks like a constant offset rather than a skill gap.
  ///
  /// Separating these two is a correctness obligation, not a nicety: a large
  /// bias with tight spread is the exact signature of uncompensated audio
  /// latency. Coaching a user to "stop rushing" when the real fault is an
  /// uncalibrated Bluetooth route teaches them to dance wrong, and the app
  /// would be confidently, repeatably at fault.
  bool get suggestsCalibrationIssue =>
      count >= 8 &&
      meanOffsetUs.abs() > 2 * stdDevUs &&
      meanOffsetUs.abs() > (0.10 * beatIntervalUs);

  static TimingSummary from(
    List<TimingJudgement> judgements, {
    required int beatIntervalUs,
  }) {
    final List<TimingJudgement> usable = judgements
        .where((TimingJudgement j) => j.verdict != TimingVerdict.unjudgeable)
        .toList(growable: false);
    if (usable.isEmpty) {
      return TimingSummary(
        count: 0,
        meanOffsetUs: 0,
        stdDevUs: 0,
        onBeatRatio: 0,
        beatIntervalUs: beatIntervalUs,
      );
    }
    final double mean = usable
            .map((TimingJudgement j) => j.offsetUs)
            .reduce((int a, int b) => a + b) /
        usable.length;
    double variance = 0;
    for (final TimingJudgement j in usable) {
      final double d = j.offsetUs - mean;
      variance += d * d;
    }
    variance /= usable.length;
    final int onBeat = usable
        .where((TimingJudgement j) => j.verdict.isAcceptable)
        .length;
    return TimingSummary(
      count: usable.length,
      meanOffsetUs: mean.round(),
      stdDevUs: math.sqrt(variance).round(),
      onBeatRatio: onBeat / usable.length,
      beatIntervalUs: beatIntervalUs,
    );
  }
}
