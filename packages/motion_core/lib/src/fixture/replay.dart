import '../geometry/joint_angles.dart';
import '../geometry/normalization.dart';
import '../pose/confidence_gate.dart';
import '../pose/pose_frame.dart';
import '../pose/smoothing.dart';
import '../pose/structural_validator.dart';
import 'fixture.dart';

/// One frame, fully processed.
final class ProcessedFrame {
  const ProcessedFrame({
    required this.raw,
    required this.smoothed,
    required this.normalized,
    required this.angles,
    required this.quality,
    required this.structure,
  });

  final PoseFrame raw;
  final PoseFrame smoothed;
  final NormalizedPose normalized;
  final JointAngleVector angles;
  final FrameQuality quality;

  /// Anatomical plausibility of the reported skeleton.
  final StructuralCheck structure;

  int get tUs => raw.tUs;

  /// A frame may only produce a technical verdict when the model saw it
  /// clearly **and** what it reported is a possible body.
  ///
  /// Two independent gates because they fail independently: confidence catches
  /// "I could not see", structure catches "I saw it wrong and was sure".
  bool get judgeable => quality.judgeable && structure.plausible;
}

/// The perception pipeline, in one object.
///
/// Assembled here rather than wired up per app so that every app — and the
/// native ports — process frames in the identical order. Order is not
/// cosmetic: smoothing before normalization filters raw jitter, whereas
/// smoothing after it would also smooth the scale estimate and blur real
/// movement into it.
final class PosePipeline {
  PosePipeline({
    PoseSmoother? smoother,
    PoseNormalizer? normalizer,
    StructuralValidator? validator,
    this.extractor = const JointAngleExtractor(),
    this.gate = const ConfidenceGate(),
    this.requiredLandmarks = const <int>[],
  })  : _smoother = smoother ?? PoseSmoother(),
        _normalizer = normalizer ?? PoseNormalizer(),
        _validator = validator ?? StructuralValidator();

  final PoseSmoother _smoother;
  final PoseNormalizer _normalizer;
  final StructuralValidator _validator;
  final JointAngleExtractor extractor;
  final ConfidenceGate gate;
  final List<int> requiredLandmarks;

  void reset() {
    _smoother.reset();
    _normalizer.reset();
    _validator.reset();
  }

  ProcessedFrame process(PoseFrame frame) {
    final PoseFrame smoothed = _smoother.smooth(frame);
    final NormalizedPose normalized = _normalizer.normalize(smoothed);
    final JointAngleVector raw = extractor.extract(normalized);
    final JointAngleVector angles = extractor.gate(
      raw,
      frame.landmarks.map((PoseLandmark l) => l.visibility).toList(growable: false),
      minVisibility: gate.landmarkThreshold,
    );
    final FrameQuality quality = requiredLandmarks.isEmpty
        ? gate.evaluate(frame)
        : gate.evaluate(frame, required: requiredLandmarks);
    // Structure is checked on the raw frame: smoothing would blend an
    // implausible skeleton toward its plausible neighbours and hide exactly
    // the artefact we are looking for.
    return ProcessedFrame(
      raw: frame,
      smoothed: smoothed,
      normalized: normalized,
      angles: angles,
      quality: quality,
      structure: _validator.check(frame),
    );
  }

  List<ProcessedFrame> processAll(List<PoseFrame> frames) {
    reset();
    return frames.map(process).toList(growable: false);
  }
}

/// Outcome of replaying a fixture.
final class ReplayReport {
  const ReplayReport({
    required this.fixture,
    required this.frames,
    required this.judgeableRatio,
  });

  final Fixture fixture;
  final List<ProcessedFrame> frames;

  /// Share of frames the confidence gate accepted.
  ///
  /// Reported on every replay because it is the honest denominator for every
  /// other number: a technique that "passes" on a fixture where two thirds of
  /// frames were unjudgeable has not been tested, it has been skipped.
  final double judgeableRatio;

  List<ProcessedFrame> between(int startUs, int endUs) => frames
      .where((ProcessedFrame f) => f.tUs >= startUs && f.tUs <= endUs)
      .toList(growable: false);

  /// Frames covered by a label.
  List<ProcessedFrame> forLabel(FixtureLabel label) =>
      between(label.tStartUs, label.tEndUs);
}

/// Replays fixtures through a [PosePipeline].
///
/// The family's rule is that no technique ships without fixture coverage: at
/// least one correct execution and at least two faulty ones. This harness is
/// what makes that rule cheap enough to actually keep.
final class ReplayHarness {
  ReplayHarness({PosePipeline? pipeline})
      : pipeline = pipeline ?? PosePipeline();

  final PosePipeline pipeline;

  ReplayReport replay(Fixture fixture) {
    final List<ProcessedFrame> processed = pipeline.processAll(fixture.frames);
    final int judgeable =
        processed.where((ProcessedFrame f) => f.judgeable).length;
    return ReplayReport(
      fixture: fixture,
      frames: processed,
      judgeableRatio:
          processed.isEmpty ? 0 : judgeable / processed.length,
    );
  }
}
