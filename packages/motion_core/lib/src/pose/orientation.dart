import 'landmark_index.dart';
import 'pose_frame.dart';

/// Gross body orientation relative to gravity, as far as a camera can tell.
///
/// This is deliberately coarse. The family's pose model (BlazePose GHUM) was
/// trained overwhelmingly on upright people; presented with an inverted body
/// it can confidently relabel the limb chains as if the person were standing
/// (Gravita D1, family ledger M-019). Everything in this file exists to manage
/// that single failure mode, so two states are all that is needed.
enum BodyOrientation {
  upright,
  inverted;

  BodyOrientation get flipped =>
      this == BodyOrientation.upright ? inverted : upright;
}

/// What the skill currently being performed says the body should be doing.
///
/// Apps never touch inference. A skill state machine only *declares* what it
/// expects — "a handstand hold is inverted", "the entry phase could be either"
/// — and the orientation-aware source does the rest (ADR-001).
final class OrientationExpectation {
  const OrientationExpectation.exactly(BodyOrientation this.orientation);

  /// Transition phases (kick-up, bail) where either orientation is plausible.
  const OrientationExpectation.ambiguous() : orientation = null;

  /// The single expected orientation, or null when the phase is ambiguous.
  final BodyOrientation? orientation;

  bool get isAmbiguous => orientation == null;

  @override
  String toString() => isAmbiguous
      ? 'OrientationExpectation(ambiguous)'
      : 'OrientationExpectation(${orientation!.name})';
}

/// Which orientation the *reported* skeleton claims to have, from the torso
/// axis alone.
///
/// Image coordinates grow downward, so an upright skeleton has its shoulder
/// midpoint above (smaller y than) its hip midpoint. Returns null when the
/// torso axis is closer to horizontal than [minAxisRatio] — a lying or
/// horizontal body has no vertical orientation to assert, and inventing one
/// would violate the family's "no verdict on unclear input" rule.
BodyOrientation? observedOrientation(
  PoseFrame frame, {
  double minAxisRatio = 0.45,
}) {
  final double shoulderY =
      (frame.point(Lm.leftShoulder).y + frame.point(Lm.rightShoulder).y) / 2;
  final double hipY =
      (frame.point(Lm.leftHip).y + frame.point(Lm.rightHip).y) / 2;
  final double torso =
      (frame.point(Lm.leftShoulder) - frame.point(Lm.leftHip)).length2D;
  if (torso < 1e-9) return null;
  final double dy = hipY - shoulderY; // positive when shoulders are higher
  if (dy.abs() / torso < minAxisRatio) return null;
  return dy > 0 ? BodyOrientation.upright : BodyOrientation.inverted;
}
