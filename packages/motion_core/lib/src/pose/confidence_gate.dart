import 'landmark_index.dart';
import 'pose_frame.dart';

/// Why a frame cannot be trusted for a technical verdict.
enum QualityIssue {
  /// Model confidence on one or more required landmarks is below threshold.
  lowTrackingConfidence,

  /// Required landmarks fall outside the normalized image bounds.
  outOfFrame,

  /// The torso reference itself is unreliable, so nothing can be normalized.
  torsoUnreliable,
}

/// Verdict on whether a frame may be used to judge technique.
final class FrameQuality {
  const FrameQuality({
    required this.judgeable,
    required this.meanVisibility,
    required this.weakLandmarks,
    required this.offFrameLandmarks,
    this.issue,
  });

  /// True when every landmark the technique requires is reliably visible.
  final bool judgeable;

  final double meanVisibility;

  /// Required landmarks whose visibility fell below the threshold.
  final List<int> weakLandmarks;

  /// Required landmarks that left the frame.
  final List<int> offFrameLandmarks;

  final QualityIssue? issue;

  /// Human-readable diagnosis, e.g. `low confidence: right_wrist, right_elbow`.
  String describe() {
    switch (issue) {
      case null:
        return 'ok';
      case QualityIssue.lowTrackingConfidence:
        return 'low confidence: ${weakLandmarks.map(Lm.nameOf).join(', ')}';
      case QualityIssue.outOfFrame:
        return 'out of frame: ${offFrameLandmarks.map(Lm.nameOf).join(', ')}';
      case QualityIssue.torsoUnreliable:
        return 'torso reference unreliable';
    }
  }

  @override
  String toString() => 'FrameQuality(judgeable: $judgeable, ${describe()})';
}

/// Which MediaPipe pose model produced a frame.
///
/// Recorded and carried everywhere because **visibility is not comparable
/// across variants**: the same joint, same footage, different model returns a
/// different number. A threshold calibrated on `full` silently becomes a
/// different threshold when a low-end device falls back to `lite`, and the
/// symptom — an app that gets stricter or laxer on cheaper phones — is very
/// hard to trace back to its cause.
enum PoseModelVariant { lite, full, heavy }

/// Decides whether a frame is good enough to judge.
///
/// This is the mechanical form of the family's hardest rule: **no verdict under
/// low confidence**. The engine must be able to distinguish
///   1. the movement was wrong,
///   2. the camera could not see the movement,
///   3. the movement is not finished yet,
/// and only case 1 may ever produce a correction. Everything else routes to a
/// framing/setup hint instead — telling a user their wrist is wrong when the
/// wrist was never visible destroys trust faster than saying nothing.
final class ConfidenceGate {
  const ConfidenceGate({
    this.landmarkThreshold = 0.5,
    this.torsoThreshold = 0.6,
    this.frameMargin = 0.02,
    this.variant = PoseModelVariant.full,
  });

  /// Thresholds for a specific model variant.
  ///
  /// PROVISIONAL: the per-variant numbers below are placeholders until each is
  /// calibrated against our own recordings. They exist as separate values
  /// rather than one shared constant so that calibrating them is a config
  /// change — and so that nobody can accidentally reuse a `full` threshold on
  /// `lite` output and believe the two mean the same thing.
  factory ConfidenceGate.forVariant(PoseModelVariant variant) {
    switch (variant) {
      case PoseModelVariant.lite:
        return const ConfidenceGate(
          landmarkThreshold: 0.45,
          torsoThreshold: 0.55,
          variant: PoseModelVariant.lite,
        );
      case PoseModelVariant.full:
        return const ConfidenceGate(variant: PoseModelVariant.full);
      case PoseModelVariant.heavy:
        return const ConfidenceGate(
          landmarkThreshold: 0.55,
          torsoThreshold: 0.65,
          variant: PoseModelVariant.heavy,
        );
    }
  }

  /// Model whose visibility scale these thresholds were calibrated for.
  final PoseModelVariant variant;

  /// Minimum per-landmark visibility for a required landmark.
  final double landmarkThreshold;

  /// Torso landmarks carry every normalization decision, so they are held to a
  /// stricter bar than limbs.
  final double torsoThreshold;

  /// How far outside `[0, 1]` a landmark may drift before it counts as having
  /// left the frame. A small margin absorbs jitter at the image border.
  final double frameMargin;

  FrameQuality evaluate(
    PoseFrame frame, {
    List<int> required = LmRegion.fullBody,
  }) {
    final List<int> weak = <int>[];
    final List<int> offFrame = <int>[];
    double sum = 0;

    for (final int i in LmRegion.torso) {
      if (frame.visibility(i) < torsoThreshold) {
        return FrameQuality(
          judgeable: false,
          meanVisibility: frame.visibility(i),
          weakLandmarks: <int>[i],
          offFrameLandmarks: const <int>[],
          issue: QualityIssue.torsoUnreliable,
        );
      }
    }

    for (final int i in required) {
      final PoseLandmark lm = frame[i];
      sum += lm.visibility;
      if (lm.visibility < landmarkThreshold) weak.add(i);
      if (lm.x < -frameMargin ||
          lm.x > 1 + frameMargin ||
          lm.y < -frameMargin ||
          lm.y > 1 + frameMargin) {
        offFrame.add(i);
      }
    }

    final double mean = required.isEmpty ? 0 : sum / required.length;

    // Framing is reported first: it is actionable by the user ("step back"),
    // whereas raw low confidence usually is not.
    if (offFrame.isNotEmpty) {
      return FrameQuality(
        judgeable: false,
        meanVisibility: mean,
        weakLandmarks: weak,
        offFrameLandmarks: offFrame,
        issue: QualityIssue.outOfFrame,
      );
    }
    if (weak.isNotEmpty) {
      return FrameQuality(
        judgeable: false,
        meanVisibility: mean,
        weakLandmarks: weak,
        offFrameLandmarks: const <int>[],
        issue: QualityIssue.lowTrackingConfidence,
      );
    }
    return FrameQuality(
      judgeable: true,
      meanVisibility: mean,
      weakLandmarks: const <int>[],
      offFrameLandmarks: const <int>[],
    );
  }
}
