import 'landmark_index.dart';
import 'orientation.dart';
import 'pose_frame.dart';
import 'structural_validator.dart';

/// The platform side of orientation-aware inference.
///
/// The native layer implements this by optionally rotating the camera image
/// 180° before inference and rotating the landmarks back afterwards
/// (`x→1-x, y→1-y`; an in-plane rotation is not a reflection, so no index
/// swap). The core never sees images — it only chooses which pass to run and
/// which result to trust, so the decision logic stays testable and identical
/// across platforms.
abstract interface class PoseSourceDriver {
  /// Run inference for the frame at [tUs] as if the body were [orientation].
  ///
  /// For [BodyOrientation.upright] this is a plain pass; for
  /// [BodyOrientation.inverted] the driver pre-rotates the input and maps the
  /// landmarks back to the original frame of reference. Returns null when the
  /// model detects no person at all.
  PoseFrame? detectAs(int tUs, BodyOrientation orientation);
}

/// One candidate result of an orientation pass, with everything the selection
/// logic needs to judge it.
final class OrientationCandidate {
  const OrientationCandidate({
    required this.orientation,
    required this.frame,
    required this.structural,
    required this.confidence,
  });

  /// The pass that produced this candidate (not the observed axis).
  final BodyOrientation orientation;
  final PoseFrame frame;
  final StructuralCheck structural;

  /// Mean visibility over the gate's critical points.
  final double confidence;

  bool get usable => structural.plausible;
}

/// What [OrientationAwarePoseSource.next] hands to the engine.
final class OrientationResolution {
  const OrientationResolution({
    required this.tUs,
    required this.frame,
    required this.strategy,
    required this.structural,
    required this.dualPass,
    required this.resolved,
  });

  final int tUs;

  /// The accepted frame, or null when no pass produced a usable skeleton
  /// ("no verdict" — the engine must coach visibility, not guess).
  final PoseFrame? frame;

  /// Which pass the accepted frame came from — recorded with every attempt
  /// (provenance, ADR-005 / family rule M-F-07) so a strategy change can never
  /// silently reinterpret history.
  final BodyOrientation? strategy;

  final StructuralCheck? structural;

  /// Whether both orientations were inferred for this frame (2× cost — the
  /// planner only does this in ambiguous phases; ADR-001 consequence #2).
  final bool dualPass;

  /// The source's current settled belief about body orientation. Changes only
  /// after [OrientationAwarePoseSource.hysteresisFrames] consistent frames, so
  /// a single flickering frame cannot flip the engine's world upside down.
  final BodyOrientation resolved;

  bool get usable => frame != null;
}

/// ADR-001: a single orientation-aware abstraction in front of the pose model.
///
/// The expectation comes from the skill state machine (the user picked the
/// skill, so the app already knows a handstand hold should be inverted); the
/// previous frames provide hysteresis; ambiguous transition phases run both
/// orientations and let the structural validator arbitrate. The strategy is
/// "pick the right orientation", **not** "always rotate" — rotated inference
/// on an actually-upright body reproduces the same axis-swap failure in the
/// opposite direction (measured: 1/24 on UPR-S2).
final class OrientationAwarePoseSource {
  OrientationAwarePoseSource(
    this._driver, {
    StructuralValidator Function()? validatorFactory,
    this.hysteresisFrames = 5,
    this.hysteresisMs,
    List<int>? confidencePoints,
  })  : assert(hysteresisMs == null || hysteresisMs > 0,
            'hysteresisMs must be positive when given'),
        _validatorFactory = validatorFactory ?? StructuralValidator.new,
        _confidencePoints = confidencePoints ?? LmRegion.fullBody {
    _validators = <BodyOrientation, StructuralValidator>{
      for (final BodyOrientation o in BodyOrientation.values)
        o: _validatorFactory(),
    };
  }

  final PoseSourceDriver _driver;
  final StructuralValidator Function() _validatorFactory;
  final List<int> _confidencePoints;

  /// Consecutive frames a *different* orientation must win before the
  /// source's settled belief flips. Ignored when [hysteresisMs] is set.
  final int hysteresisFrames;

  /// Time-based hysteresis (M-F-72): the challenger must keep winning for at
  /// least this many milliseconds of frame-timestamp time, with a floor of
  /// two winning frames, before the settled belief flips.
  ///
  /// Frame-COUNT hysteresis means variable TIME on a live camera: 5 frames
  /// is 500 ms at 10 fps (sluggish) and 83 ms at 60 fps (jittery) — the same
  /// config would behave differently on every device. Time is what the
  /// design actually means, and the frames carry their own timestamps, so it
  /// is measured directly rather than converted through an assumed fps.
  ///
  /// Null (the default) keeps the legacy frame-count behavior; flipping the
  /// family default is a separate, deliberate decision.
  final int? hysteresisMs;

  /// One validator per orientation stream: temporal checks (bone stability,
  /// jump limits) must each see a consistent history, and in a dual-pass
  /// frame the two candidates are two different histories.
  late final Map<BodyOrientation, StructuralValidator> _validators;

  BodyOrientation _resolved = BodyOrientation.upright;
  BodyOrientation? _challenger;
  int _challengerStreak = 0;
  int _challengerFirstTUs = 0;
  int _challengerLastTUs = 0;

  /// The source's current settled belief.
  BodyOrientation get resolved => _resolved;

  void reset({BodyOrientation to = BodyOrientation.upright}) {
    _resolved = to;
    _challenger = null;
    _challengerStreak = 0;
    _challengerFirstTUs = 0;
    _challengerLastTUs = 0;
    for (final StructuralValidator v in _validators.values) {
      v.reset();
    }
  }

  double _confidence(PoseFrame frame) {
    double sum = 0;
    for (final int i in _confidencePoints) {
      sum += frame.visibility(i);
    }
    return _confidencePoints.isEmpty ? 0 : sum / _confidencePoints.length;
  }

  OrientationCandidate? _run(int tUs, BodyOrientation orientation) {
    final PoseFrame? frame = _driver.detectAs(tUs, orientation);
    if (frame == null) return null;
    final StructuralCheck structural = _validators[orientation]!.check(
      frame,
      expected: orientation,
    );
    return OrientationCandidate(
      orientation: orientation,
      frame: frame,
      structural: structural,
      confidence: _confidence(frame),
    );
  }

  /// Process the frame at [tUs] under the skill's current [expectation].
  OrientationResolution next(int tUs, OrientationExpectation expectation) {
    final bool dualPass = expectation.isAmbiguous;
    OrientationCandidate? accepted;

    if (!dualPass) {
      // The skill knows what it expects; trust it and run one pass. If that
      // pass yields a structurally broken skeleton we report "no verdict"
      // rather than silently trying the other orientation: outside transition
      // phases a mismatch means occlusion or a failed rep, and guessing is
      // exactly what this class exists to prevent.
      accepted = _run(tUs, expectation.orientation!);
    } else {
      final OrientationCandidate? a = _run(tUs, _resolved);
      final OrientationCandidate? b = _run(tUs, _resolved.flipped);
      accepted = _select(a, b);
    }

    final bool usable = accepted != null && accepted.usable;
    _updateHysteresis(usable ? accepted.orientation : null, tUs);

    return OrientationResolution(
      tUs: tUs,
      frame: usable ? accepted.frame : null,
      strategy: usable ? accepted.orientation : null,
      structural: accepted?.structural,
      dualPass: dualPass,
      resolved: _resolved,
    );
  }

  OrientationCandidate? _select(
    OrientationCandidate? a,
    OrientationCandidate? b,
  ) {
    final List<OrientationCandidate> usable = <OrientationCandidate>[
      if (a != null && a.usable) a,
      if (b != null && b.usable) b,
    ];
    if (usable.isEmpty) return a ?? b;
    if (usable.length == 1) return usable.single;
    // Both passes produced anatomically coherent skeletons — prefer the one
    // the model saw more clearly; on a tie, stay with the settled belief.
    usable.sort((OrientationCandidate x, OrientationCandidate y) {
      final int byConfidence = y.confidence.compareTo(x.confidence);
      if (byConfidence != 0) return byConfidence;
      return x.orientation == _resolved ? -1 : 1;
    });
    return usable.first;
  }

  void _updateHysteresis(BodyOrientation? winner, int tUs) {
    if (winner == null) return; // an unusable frame is evidence of nothing
    if (winner == _resolved) {
      _challenger = null;
      _challengerStreak = 0;
      return;
    }
    final int? windowUs =
        hysteresisMs == null ? null : hysteresisMs! * 1000;
    final bool stale = windowUs != null &&
        _challenger == winner &&
        tUs - _challengerLastTUs > windowUs;
    if (_challenger == winner && !stale) {
      _challengerStreak += 1;
    } else {
      // A new challenger — or the same one whose last win is older than the
      // hysteresis window itself: evidence too old to count toward the
      // window cannot seed a flip (no extra constant invented; the window
      // is its own continuity bound).
      _challenger = winner;
      _challengerStreak = 1;
      _challengerFirstTUs = tUs;
    }
    _challengerLastTUs = tUs;

    final bool flip = windowUs == null
        ? _challengerStreak >= hysteresisFrames
        // M-F-72: sustained time AND at least two winning frames — a single
        // frame is never enough to turn the engine's world upside down, no
        // matter how much silence surrounds it.
        : _challengerStreak >= 2 && tUs - _challengerFirstTUs >= windowUs;
    if (flip) {
      _resolved = winner;
      _challenger = null;
      _challengerStreak = 0;
    }
  }
}
