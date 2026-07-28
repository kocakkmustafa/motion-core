/// Keeps microphone analysis honest while the coach is speaking.
///
/// Several apps run a play-and-record composite session: the coach voice (or
/// a metronome click) plays through the speaker while the microphone listens
/// to the user. The speaker's output leaks straight back into that
/// microphone, and an analysis engine that keeps judging during a cue will
/// grade its own coach voice. The fix is temporal, not spectral: while a cue
/// is sounding — plus a ring-out margin for the room — analysis output is
/// either suppressed or tagged, never trusted silently.
///
/// This class is the pure time-gating logic. The platform layer reports when
/// cues actually start and stop (on the shared [MotionClock] timeline — see
/// `motion_clock.dart`); engines ask it whether a given timestamp is clean.
/// It knows nothing about what is being analysed, which is what lets one
/// implementation serve voice cues, metronome clicks and count-ins alike.
final class CueGate {
  CueGate({this.ringOutUs = 300000});

  /// How long after a cue ends the room is still assumed to be ringing.
  ///
  /// Default 300 ms: generous for a living room, cheap for the engine. Route
  /// matters less than for latency — leakage through the air dominates.
  final int ringOutUs;

  final List<(int, int)> _closedCues = <(int, int)>[];
  int? _openCueStartUs;

  /// A cue began playing at [tUs].
  void cueStarted(int tUs) {
    assert(_openCueStartUs == null, 'previous cue never ended');
    _openCueStartUs = tUs;
  }

  /// The cue that started earlier finished at [tUs].
  void cueEnded(int tUs) {
    final int? start = _openCueStartUs;
    assert(start != null, 'cueEnded without cueStarted');
    if (start == null) return;
    _closedCues.add((start, tUs));
    _openCueStartUs = null;
  }

  bool get cueActive => _openCueStartUs != null;

  /// Whether analysis output at [tUs] may be trusted.
  ///
  /// False during any cue and for [ringOutUs] after it ends. Engines must
  /// treat a false as "no verdict" — the family rule that not judging always
  /// beats judging wrong applies to hearing your own coach too.
  bool isAnalysisClean(int tUs) {
    final int? open = _openCueStartUs;
    if (open != null && tUs >= open) return false;
    for (final (int start, int end) in _closedCues) {
      if (tUs >= start && tUs < end + ringOutUs) return false;
    }
    return true;
  }

  /// Drop closed cues that can no longer affect any timestamp at or after
  /// [horizonUs]. Call periodically from the session loop; a long practice
  /// session records thousands of cues and this list must not grow unbounded.
  void forgetBefore(int horizonUs) {
    _closedCues.removeWhere(((int, int) cue) => cue.$2 + ringOutUs < horizonUs);
  }
}
