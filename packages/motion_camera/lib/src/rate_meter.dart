import 'dart:collection';

import 'frame_envelope.dart';

/// Measured delivery rate over a sliding window of timestamps.
///
/// Returns null until two events span a measurable interval — there is no
/// declared or assumed fps anywhere in this package (sayılar dayanağını
/// taşır). The window is sized in TIME, not event count, so the reading
/// stays honest when the rate itself collapses: a count-window over 60
/// events would happily average yesterday's fast frames into today's stall.
final class RateMeter {
  RateMeter({this.windowUs = 2 * 1000 * 1000})
      : assert(windowUs > 0, 'window must be positive');

  final int windowUs;
  final Queue<int> _times = Queue<int>();

  void record(int tUs) {
    _times.addLast(tUs);
    while (_times.isNotEmpty && tUs - _times.first > windowUs) {
      _times.removeFirst();
    }
  }

  /// Events per second across the current window, or null when fewer than
  /// two events remain in it (rate unmeasurable — not zero).
  double? get perSecond {
    if (_times.length < 2) return null;
    final int span = _times.last - _times.first;
    if (span <= 0) return null;
    return (_times.length - 1) * 1e6 / span;
  }

  void reset() => _times.clear();
}

final class _Sample {
  const _Sample(this.tUs, this.dropped, this.inferenceUs);
  final int tUs;
  final int dropped;
  final int inferenceUs;
}

/// The two-speed picture of a live session, all measured: what the camera
/// produced vs what inference kept up with.
///
/// Every windowed reading (`judgedPerSecond`, `capturedPerSecond`,
/// `judgedRatio`, `meanInferenceUs`) is computed over the SAME sliding time
/// window — mixing a windowed rate with lifetime drop counts would let an
/// early stall poison the "now" reading for the rest of the session. The
/// session-total counters carry the lifetime story separately, under
/// session-prefixed names.
final class ThroughputMonitor {
  ThroughputMonitor({this.windowUs = 2 * 1000 * 1000})
      : assert(windowUs > 0, 'window must be positive');

  final int windowUs;
  final Queue<_Sample> _window = Queue<_Sample>();

  int _sessionJudged = 0;
  int _sessionDropped = 0;

  void record(CameraFrameEnvelope envelope) {
    _window.addLast(
        _Sample(envelope.tUs, envelope.dropped, envelope.inferenceUs));
    while (_window.isNotEmpty &&
        envelope.tUs - _window.first.tUs > windowUs) {
      _window.removeFirst();
    }
    _sessionJudged += 1;
    _sessionDropped += envelope.dropped;
  }

  /// Envelopes (inference-completed frames) per second in the window, or
  /// null when unmeasurable.
  double? get judgedPerSecond {
    if (_window.length < 2) return null;
    final int span = _window.last.tUs - _window.first.tUs;
    if (span <= 0) return null;
    return (_window.length - 1) * 1e6 / span;
  }

  /// Camera frames per second in the window, including the ones inference
  /// discarded under latest-wins, or null when unmeasurable.
  double? get capturedPerSecond {
    final double? judged = judgedPerSecond;
    if (judged == null) return null;
    final int droppedInWindow =
        _window.fold(0, (int sum, _Sample s) => sum + s.dropped);
    return judged * (_window.length + droppedInWindow) / _window.length;
  }

  /// Fraction of captured frames in the window that received a verdict, in
  /// `[0, 1]`, or null when the window is empty. 1.0 means inference kept up.
  double? get judgedRatio {
    if (_window.isEmpty) return null;
    final int droppedInWindow =
        _window.fold(0, (int sum, _Sample s) => sum + s.dropped);
    return _window.length / (_window.length + droppedInWindow);
  }

  /// Mean measured inference latency per judged frame in the window, µs, or
  /// null when the window is empty.
  double? get meanInferenceUs {
    if (_window.isEmpty) return null;
    final int total =
        _window.fold(0, (int sum, _Sample s) => sum + s.inferenceUs);
    return total / _window.length;
  }

  /// Lifetime totals — the session report's raw material.
  int get sessionJudgedCount => _sessionJudged;
  int get sessionDroppedCount => _sessionDropped;

  void reset() {
    _window.clear();
    _sessionJudged = 0;
    _sessionDropped = 0;
  }
}
