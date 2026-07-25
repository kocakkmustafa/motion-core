import 'dart:math' as math;

import 'package:motion_core/motion_core.dart';

/// Builds a frame, normalizes it and extracts joint angles — the path every
/// scoring test shares.
JointAngleVector anglesOf(
  SyntheticPose pose, {
  SyntheticBody body = SyntheticBody.average,
  NormalizationMode mode = NormalizationMode.translateScale,
  int tUs = 0,
}) {
  final PoseFrame f = SyntheticPoseBuilder(body: body).build(pose, tUs: tUs);
  return const JointAngleExtractor()
      .extract(PoseNormalizer(mode: mode).normalize(f));
}

/// A two-beat weight-transfer step: the shape of nearly every basic social
/// dance step, and enough structure to exercise alignment and timing.
///
/// Step out to the dancer's left on beat 1, close on beat 2 — expressed as
/// keyframes so the same movement can be re-sampled at any tempo, frame rate
/// or body type.
///
/// The excursions are deliberately life-sized (roughly 30-45 degrees at the hip
/// and shoulder). An earlier, daintier version of this fixture moved joints by
/// about 15 degrees, which sits inside the scorer's own free tolerance band —
/// every frame then matched every other frame, and alignment tests passed
/// without exercising anything. A fixture must be bigger than the tolerance it
/// is used to test.
SyntheticSequence basicSideStep({int beatIntervalUs = 500000}) {
  const SyntheticPose home = SyntheticPose.neutral;
  final SyntheticPose out = SyntheticPose.neutral.copyWith(
    leftThigh: math.pi / 2 - 0.60,
    leftShin: math.pi / 2 - 0.25,
    rightThigh: math.pi / 2 + 0.12,
    leftUpperArm: math.pi / 2 - 0.80,
    leftForearm: math.pi / 2 - 0.55,
    rightUpperArm: math.pi / 2 + 0.45,
    rootX: 0.55,
  );
  return SyntheticSequence(<SyntheticKeyframe>[
    const SyntheticKeyframe(0, home),
    SyntheticKeyframe(beatIntervalUs, out),
    SyntheticKeyframe(beatIntervalUs * 2, home),
  ]);
}

/// A four-count phrase whose every count is a distinct position.
///
/// The side step above returns through the poses it came from, which makes a
/// mis-timed take cheap to align — the aligner can always find *some* moment
/// that looks right. Real combinations do not do that, and neither does this:
/// each count is somewhere the body has not been, so an attempt performed at
/// the wrong moment has nowhere to hide.
SyntheticSequence fourCountPhrase({int beatIntervalUs = 500000}) {
  const SyntheticPose home = SyntheticPose.neutral;
  final SyntheticPose count1 = SyntheticPose.neutral.copyWith(
    leftThigh: math.pi / 2 - 0.65,
    leftShin: math.pi / 2 - 0.30,
    leftUpperArm: math.pi / 2 - 0.95,
    leftForearm: math.pi / 2 - 0.70,
    rootX: 0.56,
  );
  final SyntheticPose count2 = SyntheticPose.neutral.copyWith(
    leftUpperArm: math.pi / 2 + 0.85,
    leftForearm: math.pi / 2 + 1.05,
    rightUpperArm: math.pi / 2 - 0.85,
    rightForearm: math.pi / 2 - 1.05,
    trunkAngle: -math.pi / 2 - 0.18,
  );
  final SyntheticPose count3 = SyntheticPose.neutral.copyWith(
    rightThigh: math.pi / 2 + 0.70,
    rightShin: math.pi / 2 + 0.35,
    rightUpperArm: -math.pi / 2.4,
    rightForearm: -math.pi / 2.1,
    rootX: 0.44,
  );
  final SyntheticPose count4 = SyntheticPose.neutral.copyWith(
    leftUpperArm: 0.05,
    leftForearm: 0.05,
    rightUpperArm: math.pi - 0.05,
    rightForearm: math.pi - 0.05,
    trunkAngle: -math.pi / 2 + 0.22,
  );
  return SyntheticSequence(<SyntheticKeyframe>[
    const SyntheticKeyframe(0, home),
    SyntheticKeyframe(beatIntervalUs, count1),
    SyntheticKeyframe(beatIntervalUs * 2, count2),
    SyntheticKeyframe(beatIntervalUs * 3, count3),
    SyntheticKeyframe(beatIntervalUs * 4, count4),
  ]);
}

/// A visibly different movement: arms overhead, no weight transfer. Used as the
/// negative case — the engine must score this far below the step above.
SyntheticSequence armsOverhead({int beatIntervalUs = 500000}) {
  const SyntheticPose home = SyntheticPose.neutral;
  const SyntheticPose up = SyntheticPose(
    leftUpperArm: -math.pi / 2.2,
    leftForearm: -math.pi / 2,
    rightUpperArm: -math.pi / 1.8,
    rightForearm: -math.pi / 2,
  );
  return SyntheticSequence(<SyntheticKeyframe>[
    const SyntheticKeyframe(0, home),
    SyntheticKeyframe(beatIntervalUs, up),
    SyntheticKeyframe(beatIntervalUs * 2, home),
  ]);
}

/// Shifts a take's *content* later by [frames] while keeping its length and
/// timestamps — the learner holds the rest pose, then performs everything a
/// fixed number of frames behind the reference.
///
/// Distinct from `timeShiftUs`, which moves the clock but leaves the content on
/// the same indices. This one forces the aligner to work.
List<PoseFrame> delayedByFrames(List<PoseFrame> f, int frames) {
  final List<PoseFrame> out = <PoseFrame>[];
  for (int i = 0; i < f.length; i++) {
    final PoseFrame source = i < frames ? f.first : f[i - frames];
    out.add(PoseFrame(
      tUs: f[i].tUs,
      landmarks: source.landmarks,
      modelVersion: source.modelVersion,
    ));
  }
  return out;
}

/// Runs frames through normalization and angle extraction.
List<JointAngleVector> angleSeries(List<PoseFrame> frames) => frames
    .map((PoseFrame f) =>
        const JointAngleExtractor().extract(PoseNormalizer().normalize(f)))
    .toList(growable: false);

/// Mean absolute angular deviation between two angle vectors, in degrees,
/// over the joints both could measure.
double meanAngleDeviationDegrees(JointAngleVector a, JointAngleVector b) {
  double sum = 0;
  int n = 0;
  for (int i = 0; i < a.length; i++) {
    if (a[i].isNaN || b[i].isNaN) continue;
    sum += angleDelta(a[i], b[i]);
    n++;
  }
  return n == 0 ? double.nan : (sum / n) * radToDeg;
}

/// Mean landmark displacement between two normalized poses, in torso units.
double meanNormalizedDistance(NormalizedPose a, NormalizedPose b) {
  double sum = 0;
  for (final int lm in LmRegion.fullBody) {
    sum += (a[lm] - b[lm]).length2D;
  }
  return sum / LmRegion.fullBody.length;
}
