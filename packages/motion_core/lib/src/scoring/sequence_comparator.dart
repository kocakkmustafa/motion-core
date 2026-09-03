import 'dart:math' as math;

import '../geometry/joint_angles.dart';
import '../geometry/normalization.dart';
import '../geometry/vec3.dart';
import '../pose/confidence_gate.dart';
import '../pose/pose_frame.dart';
import '../rhythm/audio_timeline.dart';
import '../rhythm/timing.dart';
import 'dtw.dart';
import 'similarity.dart';

/// A moment in the reference performance that carries a timing obligation.
///
/// Not every frame of a step is worth judging for time. What matters is when
/// the weight lands, when the arm hits its extension — the accents a teacher
/// counts out loud. Declaring those explicitly keeps timing feedback tied to
/// something the learner can actually feel, instead of to an arbitrary frame.
final class ScoredMoment {
  const ScoredMoment({
    required this.id,
    required this.referenceIndex,
    this.expectedBeatIndex,
    this.label = '',
  });

  final String id;

  /// Index into the reference frame sequence.
  final int referenceIndex;

  /// Beat this moment should land on, when the material is beat-locked.
  final int? expectedBeatIndex;

  /// Human-facing name, e.g. `step 3`.
  final String label;
}

/// Timing outcome for one [ScoredMoment].
final class MomentTiming {
  const MomentTiming({
    required this.moment,
    required this.judgement,
    required this.learnerIndex,
  });

  final ScoredMoment moment;
  final TimingJudgement judgement;
  final int learnerIndex;
}

/// Aggregate quality of one joint across a whole attempt.
final class JointSummary {
  const JointSummary({
    required this.id,
    required this.meanSimilarity,
    required this.meanDeviation,
    required this.measuredFrames,
    required this.totalFrames,
  });

  final String id;
  final double meanSimilarity;
  final double meanDeviation;
  final int measuredFrames;
  final int totalFrames;

  double get coverage => totalFrames == 0 ? 0 : measuredFrames / totalFrames;

  /// Whether this joint was observed enough to be worth talking about.
  ///
  /// A joint seen in a tenth of the frames may show a terrible mean score
  /// purely because those were the frames where tracking was failing. Naming it
  /// as the user's main fault would be blaming them for our own blind spot.
  bool get isActionable => coverage >= 0.5 && measuredFrames >= 5;
}

/// Everything learned from one attempt at a reference sequence.
final class AttemptEvaluation {
  const AttemptEvaluation({
    required this.shapeScore,
    required this.coverage,
    required this.alignment,
    required this.jointSummaries,
    required this.momentTimings,
    required this.timingSummary,
    required this.reliable,
    required this.unreliableReason,
  });

  /// How closely the movement matched, once time is warped out, in `[0, 1]`.
  final double shapeScore;

  final double coverage;
  final DtwResult alignment;
  final List<JointSummary> jointSummaries;
  final List<MomentTiming> momentTimings;
  final TimingSummary? timingSummary;

  /// False when the attempt must not be scored at all.
  final bool reliable;

  final String unreliableReason;

  /// The worst *actionable* joint — the seed of the single spoken correction.
  JointSummary? get worstJoint {
    JointSummary? out;
    for (final JointSummary j in jointSummaries) {
      if (!j.isActionable) continue;
      if (out == null || j.meanSimilarity < out.meanSimilarity) out = j;
    }
    return out;
  }

  /// Composite score, only meaningful when [reliable].
  ///
  /// Timing is weighted heavily because in dance it is the thing that reads as
  /// "dancing" at all: an imperfect shape on the beat looks like dancing, a
  /// perfect shape off the beat does not.
  double compositeScore({double shapeWeight = 0.55, double timingWeight = 0.45}) {
    final TimingSummary? t = timingSummary;
    if (t == null || t.count == 0) return shapeScore;
    final double sum = shapeWeight + timingWeight;
    return (shapeScore * shapeWeight + t.onBeatRatio * timingWeight) / sum;
  }
}

/// Compares a learner's attempt against a reference sequence.
///
/// The pipeline is deliberately split into shape and time, and never collapsed
/// into a single number internally: DTW warps time away so shape can be judged
/// fairly, and the warp path is then read back to judge the time it removed.
/// One score cannot tell a learner whether to fix their arms or their count.
final class SequenceComparator {
  SequenceComparator({
    this.normalizerMode = NormalizationMode.translateScale,
    this.extractor = const JointAngleExtractor(),
    this.similarity = const AngularSimilarity(),
    this.dtw = const Dtw(),
    this.gate = const ConfidenceGate(),
    this.timingJudge = const TimingJudge(),
    this.minCoverage = 0.6,
  });

  final NormalizationMode normalizerMode;
  final JointAngleExtractor extractor;
  final AngularSimilarity similarity;
  final Dtw dtw;
  final ConfidenceGate gate;
  final TimingJudge timingJudge;

  /// Minimum share of measurable joint-frames before a score may be shown.
  final double minCoverage;

  /// Weight floor for reference frames that sit at the movement's rest pose.
  ///
  /// Without this, a plain per-frame average is easy to game and easy to
  /// mislead: most frames of most steps hover near a neutral standing shape, so
  /// a learner performing an entirely different movement still collects credit
  /// on all of them and the handful of frames that actually distinguish the two
  /// get averaged into insignificance. Weighting each reference frame by how
  /// far it departs from that sequence's own rest pose puts the score where the
  /// movement lives.
  static const double _restFrameWeight = 0.2;

  List<JointAngleVector> _featurize(List<PoseFrame> frames) {
    final PoseNormalizer normalizer = PoseNormalizer(mode: normalizerMode);
    return frames.map((PoseFrame f) {
      final JointAngleVector raw = extractor.extract(normalizer.normalize(f));
      return extractor.gate(
        raw,
        f.landmarks.map((PoseLandmark l) => l.visibility).toList(growable: false),
        minVisibility: gate.landmarkThreshold,
      );
    }).toList(growable: false);
  }

  /// How distinctive each reference frame is, relative to that sequence's own
  /// average pose. Returns weights in `[_restFrameWeight, 1]`.
  ///
  /// Uses a circular mean so that orientation angles near the +/-pi wrap do not
  /// average to a pose nobody ever struck.
  static List<double> frameSaliency(List<JointAngleVector> reference) {
    if (reference.isEmpty) return const <double>[];
    final int joints = reference.first.length;
    final List<double> sumSin = List<double>.filled(joints, 0);
    final List<double> sumCos = List<double>.filled(joints, 0);
    final List<int> counts = List<int>.filled(joints, 0);

    for (final JointAngleVector v in reference) {
      for (int k = 0; k < joints; k++) {
        final double a = v[k];
        if (a.isNaN) continue;
        sumSin[k] += math.sin(a);
        sumCos[k] += math.cos(a);
        counts[k] += 1;
      }
    }
    final List<double> mean = List<double>.generate(
      joints,
      (int k) => counts[k] == 0 ? double.nan : math.atan2(sumSin[k], sumCos[k]),
      growable: false,
    );

    final List<double> raw = reference.map((JointAngleVector v) {
      double sum = 0;
      int n = 0;
      for (int k = 0; k < joints; k++) {
        if (v[k].isNaN || mean[k].isNaN) continue;
        sum += angleDelta(v[k], mean[k]);
        n++;
      }
      return n == 0 ? 0.0 : sum / n;
    }).toList(growable: false);

    final double peak = raw.fold<double>(0, math.max);
    if (peak < 1e-9) {
      // A held pose — every frame matters equally.
      return List<double>.filled(reference.length, 1.0);
    }
    return raw
        .map((double r) =>
            _restFrameWeight + (1 - _restFrameWeight) * (r / peak))
        .toList(growable: false);
  }

  AttemptEvaluation evaluate({
    required List<PoseFrame> reference,
    required List<PoseFrame> learner,
    List<ScoredMoment> moments = const <ScoredMoment>[],
    PerceivedBeatTimeline? beats,
  }) {
    if (reference.isEmpty || learner.isEmpty) {
      return AttemptEvaluation(
        shapeScore: 0,
        coverage: 0,
        alignment: dtw.align(0, 0, (int i, int j) => 1),
        jointSummaries: const <JointSummary>[],
        momentTimings: const <MomentTiming>[],
        timingSummary: null,
        reliable: false,
        unreliableReason: 'empty sequence',
      );
    }

    // Refuse before pose normalization or feature allocation. Dtw.align also
    // enforces this boundary, but the comparator translates it into its public
    // named, non-scoring result instead of surfacing an exception to capture
    // callers.
    final DtwCapacity capacity = dtw.capacityFor(
      reference.length,
      learner.length,
    );
    if (!capacity.allowed) {
      return AttemptEvaluation(
        shapeScore: 0,
        coverage: 0,
        alignment: dtw.align(0, 0, (int i, int j) => 1),
        jointSummaries: const <JointSummary>[],
        momentTimings: const <MomentTiming>[],
        timingSummary: null,
        reliable: false,
        unreliableReason: capacity.reason!.code,
      );
    }

    final List<JointAngleVector> ref = _featurize(reference);
    final List<JointAngleVector> lea = _featurize(learner);

    final DtwResult alignment = dtw.align(
      ref.length,
      lea.length,
      (int i, int j) => similarity.distance(ref[i], lea[j]),
    );

    // Per-joint accumulation along the warping path.
    final List<JointSpec> specs = ref.first.specs;
    final List<double> simSum = List<double>.filled(specs.length, 0);
    final List<double> devSum = List<double>.filled(specs.length, 0);
    final List<int> measured = List<int>.filled(specs.length, 0);
    final List<double> jointWeight = List<double>.filled(specs.length, 0);
    final List<double> saliency = frameSaliency(ref);
    double weightedScore = 0;
    double weightSum = 0;
    double totalCoverage = 0;

    for (int i = 0; i < ref.length; i++) {
      final PoseSimilarityResult r =
          similarity.compare(ref[i], lea[alignment.refToLearner[i]]);
      final double w = saliency[i];
      weightedScore += r.score * w;
      weightSum += w;
      totalCoverage += r.coverage;
      for (int k = 0; k < r.joints.length; k++) {
        final JointScore js = r.joints[k];
        if (!js.measured) continue;
        // Joint summaries are saliency-weighted too, so the joint we name as
        // "the thing to fix" is the one that was wrong where it mattered — not
        // one that drifted while the dancer was standing still.
        simSum[k] += js.similarity * w;
        devSum[k] += js.deviation * w;
        measured[k] += 1;
        jointWeight[k] += w;
      }
    }

    final List<JointSummary> summaries = List<JointSummary>.generate(
      specs.length,
      (int k) => JointSummary(
        id: specs[k].id,
        meanSimilarity: jointWeight[k] == 0 ? 0 : simSum[k] / jointWeight[k],
        meanDeviation:
            jointWeight[k] == 0 ? double.nan : devSum[k] / jointWeight[k],
        measuredFrames: measured[k],
        totalFrames: ref.length,
      ),
      growable: false,
    );

    final double shapeScore = weightSum == 0 ? 0 : weightedScore / weightSum;
    final double coverage = totalCoverage / ref.length;

    // Timing.
    final List<MomentTiming> timings = <MomentTiming>[];
    if (beats != null) {
      for (final ScoredMoment m in moments) {
        if (m.referenceIndex < 0 || m.referenceIndex >= ref.length) continue;
        final int learnerIndex = alignment.refToLearner[m.referenceIndex];
        final int tUs = learner[learnerIndex].tUs;
        timings.add(MomentTiming(
          moment: m,
          judgement: timingJudge.judge(tUs, beats),
          learnerIndex: learnerIndex,
        ));
      }
    }
    final TimingSummary? timingSummary = beats == null || timings.isEmpty
        ? null
        : TimingSummary.from(
            timings.map((MomentTiming t) => t.judgement).toList(growable: false),
            beatIntervalUs: beats.beatIntervalUs,
          );

    // Reliability gate — applied before any number reaches the user.
    String reason = '';
    bool reliable = true;
    if (coverage < minCoverage) {
      reliable = false;
      reason = 'insufficient landmark coverage '
          '(${(coverage * 100).toStringAsFixed(0)}% < '
          '${(minCoverage * 100).toStringAsFixed(0)}%)';
    } else if (alignment.bandSaturated) {
      reliable = false;
      reason = 'timing drifted beyond the alignment window — '
          'the attempt could not be matched to the reference';
    }

    return AttemptEvaluation(
      shapeScore: shapeScore,
      coverage: coverage,
      alignment: alignment,
      jointSummaries: summaries,
      momentTimings: timings,
      timingSummary: timingSummary,
      reliable: reliable,
      unreliableReason: reason,
    );
  }
}
