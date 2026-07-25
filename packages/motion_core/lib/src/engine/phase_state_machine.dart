import '../geometry/joint_angles.dart';
import '../pose/confidence_gate.dart';
import '../pose/landmark_index.dart';
import '../pose/pose_frame.dart';

/// Everything a condition may look at when deciding a transition.
final class PhaseContext {
  const PhaseContext({
    required this.frame,
    required this.angles,
    required this.quality,
    required this.tUs,
    required this.timeInPhaseUs,
    required this.previousAngles,
  });

  final PoseFrame frame;
  final JointAngleVector angles;
  final FrameQuality quality;
  final int tUs;

  /// How long the machine has been in the current phase.
  final int timeInPhaseUs;

  /// Previous frame's angles, or null on the first frame. Rate-of-change
  /// conditions ("the knee is still bending") read this rather than keeping
  /// their own state, so that a condition stays a pure function.
  final JointAngleVector? previousAngles;

  double? angle(String jointId) => angles.byId(jointId);

  double? angleDegrees(String jointId) => angles.degreesById(jointId);

  /// Signed change in a joint angle since the previous frame, in radians.
  double? delta(String jointId) {
    final double? now = angles.byId(jointId);
    final double? before = previousAngles?.byId(jointId);
    if (now == null || before == null) return null;
    return now - before;
  }
}

typedef PhaseCondition = bool Function(PhaseContext ctx);

/// One phase of a technique.
///
/// Phases are the family's unit of *timing*. A punch, a step, a hold and a bow
/// stroke all decompose the same way — enter, progress, complete or abort — and
/// the timestamps of those transitions are what every timing metric in the
/// family is derived from. Measuring speed from inter-frame pixel motion was
/// rejected family-wide (rule D2): at 30 fps a fast movement occupies one or
/// two motion-blurred frames, and pixel velocity there is noise. Phase
/// boundaries survive blur because they are defined by posture, not by speed.
final class PhaseDefinition {
  const PhaseDefinition({
    required this.id,
    required this.enter,
    this.exit,
    this.abort,
    this.timeoutUs,
    this.minDurationUs = 0,
    this.requiredLandmarks = const <int>[],
    this.isTerminal = false,
  });

  final String id;

  /// Condition to move *into* this phase from the previous one.
  final PhaseCondition enter;

  /// Condition to leave for the next phase. When null, the machine advances as
  /// soon as the next phase's [enter] fires.
  final PhaseCondition? exit;

  /// Condition that cancels the whole attempt from this phase.
  final PhaseCondition? abort;

  /// Maximum time the machine may sit in this phase before aborting.
  ///
  /// Without a timeout a state machine that misses an exit condition parks
  /// forever and silently stops producing feedback — a failure mode that looks
  /// exactly like "the user stopped moving".
  final int? timeoutUs;

  /// Debounce: how long the phase must hold before it may be left.
  final int minDurationUs;

  final List<int> requiredLandmarks;

  final bool isTerminal;
}

/// Why an attempt ended.
enum AttemptOutcome { completed, timedOut, aborted, lostTracking }

/// One phase boundary crossing.
final class PhaseTransition {
  const PhaseTransition({
    required this.fromPhase,
    required this.toPhase,
    required this.tUs,
    required this.phaseIndex,
  });

  final String? fromPhase;
  final String toPhase;
  final int tUs;
  final int phaseIndex;

  @override
  String toString() =>
      'PhaseTransition(${fromPhase ?? "-"} -> $toPhase @ ${tUs / 1e6}s)';
}

/// The result of running one attempt through the machine.
final class AttemptRun {
  const AttemptRun({
    required this.techniqueId,
    required this.transitions,
    required this.outcome,
    required this.startedAtUs,
    required this.endedAtUs,
  });

  final String techniqueId;
  final List<PhaseTransition> transitions;
  final AttemptOutcome outcome;
  final int startedAtUs;
  final int endedAtUs;

  int get durationUs => endedAtUs - startedAtUs;

  /// Duration of a named phase, or null if it was never entered/left.
  int? phaseDurationUs(String phaseId) {
    for (int i = 0; i < transitions.length; i++) {
      if (transitions[i].toPhase != phaseId) continue;
      final int start = transitions[i].tUs;
      if (i + 1 < transitions.length) return transitions[i + 1].tUs - start;
      return endedAtUs - start;
    }
    return null;
  }

  int? timeOfPhaseUs(String phaseId) {
    for (final PhaseTransition t in transitions) {
      if (t.toPhase == phaseId) return t.tUs;
    }
    return null;
  }
}

/// Runs a technique's phases over a stream of frames.
///
/// Domain-independent by construction: it knows about phases, timeouts and
/// tracking loss, and nothing about what is being performed. Apps supply the
/// conditions; the conditions come from versioned rule config, not from code
/// scattered across the UI.
final class PhaseStateMachine {
  PhaseStateMachine({
    required this.techniqueId,
    required this.phases,
    this.gate = const ConfidenceGate(),
    this.lostTrackingGraceUs = 500000,
  }) : assert(phases.isNotEmpty, 'a technique needs at least one phase');

  final String techniqueId;
  final List<PhaseDefinition> phases;
  final ConfidenceGate gate;

  /// How long tracking may be unreliable before the attempt is abandoned.
  ///
  /// A short blackout is normal (a hand crosses the torso); abandoning
  /// instantly would make the engine unusable, while never abandoning would let
  /// it "complete" an attempt it did not see.
  final int lostTrackingGraceUs;

  int _index = -1;
  int _phaseStartUs = 0;
  int _startedAtUs = 0;
  int? _lostSinceUs;
  final List<PhaseTransition> _transitions = <PhaseTransition>[];
  JointAngleVector? _previousAngles;
  AttemptOutcome? _outcome;
  int _lastTUs = 0;

  bool get isRunning => _index >= 0 && _outcome == null;

  String? get currentPhase => _index >= 0 ? phases[_index].id : null;

  void reset() {
    _index = -1;
    _phaseStartUs = 0;
    _startedAtUs = 0;
    _lostSinceUs = null;
    _transitions.clear();
    _previousAngles = null;
    _outcome = null;
  }

  /// Feeds one frame. Returns a completed [AttemptRun] on the frame where the
  /// attempt finishes, otherwise null.
  AttemptRun? update(PoseFrame frame, JointAngleVector angles) {
    _lastTUs = frame.tUs;
    final PhaseDefinition? active = _index >= 0 ? phases[_index] : null;
    // Gate on whatever the phase we are in (or about to enter) actually needs.
    // Falling back to the full body when nothing is declared keeps an
    // under-specified rule set strict rather than accidentally ungated.
    final List<int> declared = active?.requiredLandmarks.isNotEmpty ?? false
        ? active!.requiredLandmarks
        : phases.first.requiredLandmarks;
    final FrameQuality quality = gate.evaluate(
      frame,
      required: declared.isNotEmpty ? declared : LmRegion.fullBody,
    );

    final PhaseContext ctx = PhaseContext(
      frame: frame,
      angles: angles,
      quality: quality,
      tUs: frame.tUs,
      timeInPhaseUs: _index >= 0 ? frame.tUs - _phaseStartUs : 0,
      previousAngles: _previousAngles,
    );
    _previousAngles = angles;

    // Tracking-loss handling comes before any technical judgement.
    if (!quality.judgeable && _index >= 0) {
      final int lostSince = _lostSinceUs ?? frame.tUs;
      _lostSinceUs = lostSince;
      if (frame.tUs - lostSince > lostTrackingGraceUs) {
        return _finish(AttemptOutcome.lostTracking, frame.tUs);
      }
      return null;
    }
    _lostSinceUs = null;

    if (_index < 0) {
      if (phases.first.enter(ctx)) {
        _index = 0;
        _startedAtUs = frame.tUs;
        _phaseStartUs = frame.tUs;
        _transitions.add(PhaseTransition(
          fromPhase: null,
          toPhase: phases.first.id,
          tUs: frame.tUs,
          phaseIndex: 0,
        ));
        if (phases.first.isTerminal) {
          return _finish(AttemptOutcome.completed, frame.tUs);
        }
      }
      return null;
    }

    final PhaseDefinition phase = phases[_index];

    if (phase.abort?.call(ctx) ?? false) {
      return _finish(AttemptOutcome.aborted, frame.tUs);
    }
    final int? timeout = phase.timeoutUs;
    if (timeout != null && ctx.timeInPhaseUs > timeout) {
      return _finish(AttemptOutcome.timedOut, frame.tUs);
    }
    if (ctx.timeInPhaseUs < phase.minDurationUs) return null;

    final bool mayLeave = phase.exit?.call(ctx) ?? true;
    if (!mayLeave) return null;

    final int next = _index + 1;
    if (next >= phases.length) return _finish(AttemptOutcome.completed, frame.tUs);

    if (phases[next].enter(ctx)) {
      _index = next;
      _phaseStartUs = frame.tUs;
      _transitions.add(PhaseTransition(
        fromPhase: phase.id,
        toPhase: phases[next].id,
        tUs: frame.tUs,
        phaseIndex: next,
      ));
      if (phases[next].isTerminal) {
        return _finish(AttemptOutcome.completed, frame.tUs);
      }
    }
    return null;
  }

  AttemptRun _finish(AttemptOutcome outcome, int tUs) {
    _outcome = outcome;
    final AttemptRun run = AttemptRun(
      techniqueId: techniqueId,
      transitions: List<PhaseTransition>.unmodifiable(_transitions),
      outcome: outcome,
      startedAtUs: _startedAtUs,
      endedAtUs: tUs,
    );
    reset();
    return run;
  }

  /// Force-closes an in-flight attempt (end of take, user stopped).
  AttemptRun? flush() {
    if (_index < 0) return null;
    return _finish(AttemptOutcome.timedOut, _lastTUs);
  }
}
