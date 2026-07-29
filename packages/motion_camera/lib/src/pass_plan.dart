import 'package:motion_core/motion_core.dart';

/// Which orientation passes the native layer should run per camera frame.
///
/// The plan is pushed DOWN to native (one message when it changes) instead of
/// the engine pulling passes per frame over the channel: at 30 fps a
/// per-frame round-trip would put the platform channel inside the inference
/// loop. Dual is the 2× cost path — the skill state machine only asks for it
/// in ambiguous transition phases (ADR-001 consequence #2).
enum PassPlan {
  uprightOnly,
  invertedOnly,
  dual;

  /// The plan that satisfies [expectation] for the coming frames.
  ///
  /// Ambiguous expectation → both passes; settled expectation → exactly that
  /// pass. There is deliberately no "let native decide" value: orientation
  /// strategy lives in `OrientationAwarePoseSource`, and the native layer
  /// stays a dumb, testable pipe.
  static PassPlan forExpectation(OrientationExpectation expectation) {
    if (expectation.isAmbiguous) return PassPlan.dual;
    return expectation.orientation == BodyOrientation.upright
        ? PassPlan.uprightOnly
        : PassPlan.invertedOnly;
  }

  /// Whether an envelope produced under this plan can answer a
  /// `detectAs` call for [orientation].
  bool covers(BodyOrientation orientation) => switch (this) {
        PassPlan.uprightOnly => orientation == BodyOrientation.upright,
        PassPlan.invertedOnly => orientation == BodyOrientation.inverted,
        PassPlan.dual => true,
      };

  String get wireName => switch (this) {
        PassPlan.uprightOnly => 'upright',
        PassPlan.invertedOnly => 'inverted',
        PassPlan.dual => 'dual',
      };
}
