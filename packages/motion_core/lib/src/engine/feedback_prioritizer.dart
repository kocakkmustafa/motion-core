/// How urgent a piece of feedback is.
///
/// Ordering matters: this is the tie-break that decides what the single spoken
/// cue will be when several things are wrong at once.
enum FeedbackSeverity {
  /// Risk of injury — always wins, always allowed to interrupt.
  safety,

  /// The movement is fundamentally not the movement being taught.
  critical,

  /// A real technical fault worth naming.
  major,

  /// Refinement, only worth saying when nothing bigger is pending.
  minor,

  /// Confirmation that something the learner was told is now fixed.
  positive,

  /// Setup/framing guidance ("step back", "I can't see your feet").
  info,
}

/// One thing the engine *could* say.
final class FeedbackCandidate {
  const FeedbackCandidate({
    required this.code,
    required this.severity,
    required this.tUs,
    this.confidence = 1.0,
    this.jointId,
    this.evidence = const <String, Object?>{},
  });

  /// Stable machine code (`STEP_LATE`, `WEIGHT_NOT_TRANSFERRED`).
  ///
  /// Never a user-facing string: the spoken wording lives in localized content,
  /// so that changing what the coach says is a content edit, and the same fault
  /// keeps one identity across languages and analytics.
  final String code;

  final FeedbackSeverity severity;
  final int tUs;

  /// How sure the engine is. Low-confidence findings are not spoken at all.
  final double confidence;

  final String? jointId;

  /// Numbers behind the finding, for logs and for the end-of-session detail.
  final Map<String, Object?> evidence;
}

/// What the prioritizer decided, and why.
final class FeedbackDecision {
  const FeedbackDecision.speak(this.candidate, {this.repeatCount = 0})
      : suppressedReason = null;

  const FeedbackDecision.silent(this.suppressedReason)
      : candidate = null,
        repeatCount = 0;

  final FeedbackCandidate? candidate;
  final String? suppressedReason;

  /// How many times this same code has already been spoken this session.
  ///
  /// Content uses it to vary phrasing and to escalate from a hint to an
  /// explicit instruction — hearing the identical sentence six times is how a
  /// coach stops being listened to.
  final int repeatCount;

  bool get willSpeak => candidate != null;
}

/// Chooses at most one thing to say, and decides when to say nothing.
///
/// The hard part of a voice coach is not generating feedback, it is refusing
/// to. The phone is across the room and the learner is moving: two cues at once
/// are worse than none, and a cue that arrives mid-phrase competes with the
/// count the learner is trying to hold. Everything here exists to protect that
/// silence.
final class FeedbackPrioritizer {
  FeedbackPrioritizer({
    this.minConfidence = 0.6,
    this.globalCooldownUs = 2500000,
    this.perCodeCooldownUs = 8000000,
    this.safetyBypassesCooldown = true,
  });

  /// Findings below this confidence are never spoken.
  final double minConfidence;

  /// Minimum gap between any two spoken cues.
  final int globalCooldownUs;

  /// Minimum gap before repeating the *same* cue.
  final int perCodeCooldownUs;

  final bool safetyBypassesCooldown;

  int? _lastSpokenUs;
  final Map<String, int> _lastByCode = <String, int>{};
  final Map<String, int> _countByCode = <String, int>{};
  final Set<String> _outstanding = <String>{};
  int _quietUntilUs = 0;

  /// Suppresses all non-safety speech until [untilUs].
  ///
  /// Used to stay quiet through a counted phrase ("5-6-7-8") and during the
  /// reference demonstration, where the coach talking over the count is
  /// actively harmful to learning.
  void requestQuietUntil(int untilUs) {
    if (untilUs > _quietUntilUs) _quietUntilUs = untilUs;
  }

  void reset() {
    _lastSpokenUs = null;
    _lastByCode.clear();
    _countByCode.clear();
    _outstanding.clear();
    _quietUntilUs = 0;
  }

  /// Codes that were spoken and have not yet been confirmed as fixed.
  Set<String> get outstandingCodes => Set<String>.unmodifiable(_outstanding);

  /// Marks a previously-raised issue as resolved and returns a confirmation
  /// candidate if one is warranted.
  ///
  /// Closing the loop is not decoration: telling someone what was wrong and
  /// never telling them it is now right leaves them with no way to know their
  /// correction worked.
  FeedbackCandidate? resolve(String code, int tUs) {
    if (!_outstanding.remove(code)) return null;
    return FeedbackCandidate(
      code: '${code}_RESOLVED',
      severity: FeedbackSeverity.positive,
      tUs: tUs,
      evidence: <String, Object?>{'resolves': code},
    );
  }

  FeedbackDecision consider(List<FeedbackCandidate> candidates, int tUs) {
    if (candidates.isEmpty) return const FeedbackDecision.silent('nothing to say');

    final List<FeedbackCandidate> eligible = candidates
        .where((FeedbackCandidate c) =>
            c.severity == FeedbackSeverity.safety || c.confidence >= minConfidence)
        .toList();
    if (eligible.isEmpty) {
      return const FeedbackDecision.silent('all candidates below confidence floor');
    }

    eligible.sort((FeedbackCandidate a, FeedbackCandidate b) {
      final int bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      return b.confidence.compareTo(a.confidence);
    });

    for (final FeedbackCandidate c in eligible) {
      final bool isSafety = c.severity == FeedbackSeverity.safety;
      final bool bypass = isSafety && safetyBypassesCooldown;

      if (!bypass && tUs < _quietUntilUs) continue;

      final int? lastAny = _lastSpokenUs;
      if (!bypass && lastAny != null && tUs - lastAny < globalCooldownUs) {
        continue;
      }
      final int? lastSame = _lastByCode[c.code];
      if (!bypass && lastSame != null && tUs - lastSame < perCodeCooldownUs) {
        continue;
      }

      final int count = _countByCode.update(
        c.code,
        (int v) => v + 1,
        ifAbsent: () => 1,
      );
      _lastSpokenUs = tUs;
      _lastByCode[c.code] = tUs;
      if (c.severity != FeedbackSeverity.positive &&
          c.severity != FeedbackSeverity.info) {
        _outstanding.add(c.code);
      }
      return FeedbackDecision.speak(c, repeatCount: count - 1);
    }

    return const FeedbackDecision.silent('cooldown or quiet window');
  }
}
