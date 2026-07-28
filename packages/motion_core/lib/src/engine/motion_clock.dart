/// The single monotonic clock every subsystem stamps against.
///
/// The family's audio-motion contract (catalog §4) is one sentence: pose
/// frames, audio events, coach cues and beat grids all carry timestamps from
/// the **same monotonic source**. Wall-clock time is banned from timing math —
/// it jumps on NTP sync and freezes across device sleep, which produces
/// timing bugs that appear only in the field and never in a fixture.
///
/// Platform integrations obtain one [MotionClock] at session start and thread
/// it everywhere; nothing else in the engine may invent its own zero point.
abstract interface class MotionClock {
  /// Microseconds since the clock's zero point. Strictly non-decreasing.
  int nowUs();
}

/// Production clock: Dart's [Stopwatch], which is monotonic on both platforms.
///
/// The zero point is [start] — construct it once per session, not per
/// subsystem, or the "single clock" contract silently becomes several clocks
/// that happen to tick at the same rate from different zeros.
final class StopwatchMotionClock implements MotionClock {
  StopwatchMotionClock.start() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int nowUs() => _watch.elapsedMicroseconds;
}

/// Test clock: time moves only when the test says so.
final class ManualMotionClock implements MotionClock {
  ManualMotionClock([this._nowUs = 0]);

  int _nowUs;

  @override
  int nowUs() => _nowUs;

  void advanceUs(int deltaUs) {
    assert(deltaUs >= 0, 'a monotonic clock does not run backwards');
    _nowUs += deltaUs;
  }

  set nowUsValue(int value) {
    assert(value >= _nowUs, 'a monotonic clock does not run backwards');
    _nowUs = value;
  }
}
