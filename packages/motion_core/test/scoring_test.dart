import 'dart:math' as math;

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Frozen copy of the pre-remediation full-grid implementation.
///
/// The production implementation may change its storage shape, but every
/// in-band arithmetic operation, predecessor tie-break and reported raw path
/// cost must remain exactly equivalent to this oracle.
DtwResult _legacyFullGridAlign(
  Dtw dtw,
  int n,
  int m,
  PairCost cost, {
  int? dtUs,
}) {
  if (n == 0 || m == 0) {
    return const DtwResult(
      normalizedCost: 1.0,
      pathRef: <int>[],
      pathLearner: <int>[],
      refToLearner: <int>[],
      bandSaturated: true,
    );
  }

  final int radius = dtw.effectiveRadius(dtUs);
  final double slope = (n > 1) ? (m - 1) / (n - 1) : 0.0;
  double loBand(int i) => (i * slope) - radius;
  double hiBand(int i) => (i * slope) + radius;
  int lowFor(int i) => math.max(0, loBand(i).floor());
  int highFor(int i) => math.min(m - 1, hiBand(i).ceil());

  final List<List<double>> acc = List<List<double>>.generate(
    n,
    (_) => List<double>.filled(m, double.infinity),
    growable: false,
  );

  for (int i = 0; i < n; i++) {
    final int lo = lowFor(i);
    final int hi = highFor(i);
    for (int j = lo; j <= hi; j++) {
      final double c = cost(i, j);
      if (i == 0 && j == 0) {
        acc[i][j] = c;
        continue;
      }
      double best = double.infinity;
      if (i > 0 && acc[i - 1][j] + dtw.warpPenalty < best) {
        best = acc[i - 1][j] + dtw.warpPenalty;
      }
      if (j > 0 && acc[i][j - 1] + dtw.warpPenalty < best) {
        best = acc[i][j - 1] + dtw.warpPenalty;
      }
      if (i > 0 && j > 0 && acc[i - 1][j - 1] < best) {
        best = acc[i - 1][j - 1];
      }
      acc[i][j] = best.isInfinite ? double.infinity : best + c;
    }
  }

  if (acc[n - 1][m - 1].isInfinite) {
    return DtwResult(
      normalizedCost: 1.0,
      pathRef: const <int>[],
      pathLearner: const <int>[],
      refToLearner: List<int>.generate(
        n,
        (int i) => math.min(m - 1, i),
        growable: false,
      ),
      bandSaturated: true,
      bandEdgeRatio: 1.0,
    );
  }

  final List<int> pr = <int>[];
  final List<int> pl = <int>[];
  int edgeTouches = 0;
  int i = n - 1;
  int j = m - 1;
  while (true) {
    pr.add(i);
    pl.add(j);
    if (j <= loBand(i) || j >= hiBand(i)) edgeTouches++;
    if (i == 0 && j == 0) break;
    if (i == 0) {
      j -= 1;
      continue;
    }
    if (j == 0) {
      i -= 1;
      continue;
    }
    final double diag = acc[i - 1][j - 1];
    final double up = acc[i - 1][j] + dtw.warpPenalty;
    final double left = acc[i][j - 1] + dtw.warpPenalty;
    if (diag <= up && diag <= left) {
      i -= 1;
      j -= 1;
    } else if (up <= left) {
      i -= 1;
    } else {
      j -= 1;
    }
  }
  final List<int> pathRef = pr.reversed.toList(growable: false);
  final List<int> pathLearner = pl.reversed.toList(growable: false);

  final List<List<int>> buckets =
      List<List<int>>.generate(n, (_) => <int>[], growable: false);
  for (int k = 0; k < pathRef.length; k++) {
    buckets[pathRef[k]].add(pathLearner[k]);
  }
  final List<int> refToLearner = List<int>.generate(
    n,
    (int idx) {
      final List<int> bucket = buckets[idx];
      if (bucket.isEmpty) return math.min(m - 1, (idx * slope).round());
      return bucket[bucket.length ~/ 2];
    },
    growable: false,
  );

  double pathCost = 0;
  for (int k = 0; k < pathRef.length; k++) {
    pathCost += cost(pathRef[k], pathLearner[k]);
  }
  final double edgeRatio = edgeTouches / pathRef.length;
  return DtwResult(
    normalizedCost: pathCost / pathRef.length,
    pathRef: pathRef,
    pathLearner: pathLearner,
    refToLearner: refToLearner,
    bandSaturated: edgeRatio > dtw.saturationRatio,
    bandEdgeRatio: edgeRatio,
  );
}

void _expectExactAlignment(DtwResult actual, DtwResult expected) {
  expect(actual.normalizedCost, expected.normalizedCost);
  expect(actual.pathRef, expected.pathRef);
  expect(actual.pathLearner, expected.pathLearner);
  expect(actual.refToLearner, expected.refToLearner);
  expect(actual.bandSaturated, expected.bandSaturated);
  expect(actual.bandEdgeRatio, expected.bandEdgeRatio);
}

void main() {
  final SyntheticPose testPose = SyntheticPose.neutral.copyWith(
    leftUpperArm: math.pi / 3,
    leftForearm: math.pi / 6,
    rightUpperArm: math.pi / 1.6,
    leftThigh: math.pi / 2 - 0.3,
  );

  group('Tolerance', () {
    test('full credit inside the free band, none beyond zeroAt', () {
      final Tolerance t = Tolerance.degrees(free: 10, zeroAt: 40);
      expect(t.similarity(5 * degToRad), 1.0);
      expect(t.similarity(10 * degToRad), 1.0);
      expect(t.similarity(40 * degToRad), 0.0);
      expect(t.similarity(60 * degToRad), 0.0);
      expect(t.similarity(25 * degToRad), closeTo(0.5, 1e-9));
    });
  });

  group('body-proportion invariance (G4 gate requirement)', () {
    test('identical movement scores identically across body types', () {
      final JointAngleVector slim =
          anglesOf(testPose, body: SyntheticBody.tallSlim);
      final JointAngleVector broad =
          anglesOf(testPose, body: SyntheticBody.shortBroad);

      final PoseSimilarityResult r =
          const AngularSimilarity().compare(slim, broad);

      expect(r.coverage, 1.0);
      expect(r.score, greaterThan(0.99),
          reason: 'a tall, slim dancer and a short, broad one performing the '
              'same pose must not receive different scores');
      expect(meanAngleDeviationDegrees(slim, broad), lessThan(3.0));
    });

    test('raw normalized positions are NOT proportion-invariant', () {
      // This is the executable justification for the family rule that scoring
      // must run on angles, never on raw coordinates: the very same pose lands
      // limbs in materially different normalized positions depending on build.
      final NormalizedPose slim = PoseNormalizer().normalize(
        SyntheticPoseBuilder(body: SyntheticBody.tallSlim)
            .build(testPose, tUs: 0),
      );
      final NormalizedPose broad = PoseNormalizer().normalize(
        SyntheticPoseBuilder(body: SyntheticBody.shortBroad)
            .build(testPose, tUs: 0),
      );

      final double positional = meanNormalizedDistance(slim, broad);
      final double angular = meanAngleDeviationDegrees(
        anglesOf(testPose, body: SyntheticBody.tallSlim),
        anglesOf(testPose, body: SyntheticBody.shortBroad),
      );

      expect(positional, greaterThan(0.04),
          reason: 'positional comparison carries a real body-shape penalty');
      expect(angular, lessThan(3.0),
          reason: 'angular comparison does not');
    });
  });

  group('AngularSimilarity', () {
    test('unmeasurable joints shrink coverage instead of scoring as errors', () {
      final JointAngleVector a = anglesOf(testPose);
      final List<double> vis = List<double>.filled(Lm.count, 1.0);
      vis[Lm.leftWrist] = 0.1;
      final JointAngleVector gated = const JointAngleExtractor().gate(a, vis);

      final PoseSimilarityResult r = const AngularSimilarity().compare(a, gated);

      expect(r.coverage, lessThan(1.0));
      expect(r.score, greaterThan(0.99),
          reason: 'an occluded wrist is missing evidence, not a wrong pose');
      expect(r.isReportable(), isTrue);
    });

    test('refuses to be reportable when almost nothing was measured', () {
      final JointAngleVector a = anglesOf(testPose);
      final List<double> vis = List<double>.filled(Lm.count, 0.1);
      final JointAngleVector gated = const JointAngleExtractor().gate(a, vis);
      final PoseSimilarityResult r = const AngularSimilarity().compare(a, gated);

      expect(r.isReportable(), isFalse);
    });

    test('identifies the worst joint for a single correction', () {
      final JointAngleVector reference = anglesOf(SyntheticPose.neutral);
      final JointAngleVector learner = anglesOf(
        SyntheticPose.neutral.copyWith(rightUpperArm: -math.pi / 2),
      );

      final PoseSimilarityResult r =
          const AngularSimilarity().compare(reference, learner);

      expect(r.worst, isNotNull);
      // Raising the upper arm also changes the elbow's interior angle, so any
      // right-arm joint is a correct attribution; what matters is that the
      // engine does not point at the legs.
      expect(r.worst!.id, startsWith('right_'));
      expect(r.worst!.id, isNot(contains('thigh')));
      expect(r.worst!.id, isNot(contains('knee')));
    });

    test('per-joint tolerance overrides apply', () {
      final JointAngleVector reference = anglesOf(SyntheticPose.neutral);
      final JointAngleVector learner = anglesOf(
        SyntheticPose.neutral.copyWith(leftThigh: math.pi / 2 - 0.30),
      );

      final AngularSimilarity lenient = const AngularSimilarity();
      final AngularSimilarity strict = AngularSimilarity(
        perJointTolerance: <String, Tolerance>{
          'left_thigh': Tolerance.degrees(free: 2, zeroAt: 10),
        },
      );

      expect(strict.compare(reference, learner).score,
          lessThan(lenient.compare(reference, learner).score));
    });
  });

  group('Dtw', () {
    test('sparse rows preserve the full-grid result and tie-break exactly', () {
      final scenarios = <({Dtw dtw, int n, int m, int? dtUs})>[
        (
          dtw: const Dtw(
            bandRadius: 1,
            bandRadiusS: null,
            minBandRadius: 1,
          ),
          n: 7,
          m: 9,
          dtUs: null,
        ),
        (
          dtw: const Dtw(
            bandRadius: 5,
            bandRadiusS: null,
            minBandRadius: 1,
            warpPenalty: 0,
          ),
          n: 6,
          m: 6,
          dtUs: null,
        ),
        (
          dtw: const Dtw(
            bandRadius: 1,
            bandRadiusS: 0.15,
            minBandRadius: 1,
            warpPenalty: 0.03,
          ),
          n: 11,
          m: 5,
          dtUs: 50000,
        ),
        (
          dtw: const Dtw(
            bandRadius: 4,
            bandRadiusS: null,
            minBandRadius: 1,
          ),
          n: 1,
          m: 5,
          dtUs: null,
        ),
      ];

      for (final scenario in scenarios) {
        double cost(int i, int j) => ((i * 3 + j * 5) % 7) / 7;
        final DtwResult expected = _legacyFullGridAlign(
          scenario.dtw,
          scenario.n,
          scenario.m,
          cost,
          dtUs: scenario.dtUs,
        );
        final DtwResult actual = scenario.dtw.align(
          scenario.n,
          scenario.m,
          cost,
          dtUs: scenario.dtUs,
        );
        _expectExactAlignment(actual, expected);
      }

      // Every predecessor has equal accumulated cost here. This freezes the
      // legacy backtrace preference explicitly: diagonal, then up, then left.
      const Dtw tied = Dtw(
        bandRadius: 8,
        bandRadiusS: null,
        minBandRadius: 1,
        warpPenalty: 0,
      );
      double tiedCost(int i, int j) => 0;
      _expectExactAlignment(
        tied.align(8, 5, tiedCost),
        _legacyFullGridAlign(tied, 8, 5, tiedCost),
      );
    });

    test('a large narrow-band alignment fits the sparse cell budget', () {
      const int length = 12000;
      const Dtw sparse = Dtw(
        bandRadius: 2,
        bandRadiusS: null,
        minBandRadius: 1,
        maxSequenceLength: length,
        maxStoredCells: 60000,
      );

      final DtwCapacity capacity = sparse.capacityFor(length, length);
      expect(capacity.allowed, isTrue);
      expect(capacity.storedCells, 59994);
      expect(sparse.canAlign(length, length), isTrue);

      final DtwResult result = sparse.align(
        length,
        length,
        (int i, int j) => i == j ? 0 : 1,
      );
      expect(result.normalizedCost, 0);
      expect(result.pathRef, hasLength(length));
      expect(result.pathLearner, result.pathRef);
    });

    test('sequence and sparse-cell limits fail closed with named reasons', () {
      const Dtw sequenceBound = Dtw(
        maxSequenceLength: 4,
        maxStoredCells: 100,
      );
      int sequenceCostCalls = 0;
      expect(sequenceBound.canAlign(5, 5), isFalse);
      expect(
        () => sequenceBound.align(5, 5, (int i, int j) {
          sequenceCostCalls++;
          return 0;
        }),
        throwsA(
          isA<DtwLimitExceeded>().having(
            (DtwLimitExceeded e) => e.reason,
            'reason',
            DtwLimitReason.sequenceLengthExceeded,
          ),
        ),
      );
      expect(sequenceCostCalls, 0);

      const Dtw cellBound = Dtw(
        bandRadius: 4,
        bandRadiusS: null,
        minBandRadius: 4,
        maxSequenceLength: 10,
        maxStoredCells: 20,
      );
      int cellCostCalls = 0;
      expect(cellBound.canAlign(5, 5), isFalse);
      expect(
        () => cellBound.align(5, 5, (int i, int j) {
          cellCostCalls++;
          return 0;
        }),
        throwsA(
          isA<DtwLimitExceeded>().having(
            (DtwLimitExceeded e) => e.reason,
            'reason',
            DtwLimitReason.storedCellLimitExceeded,
          ),
        ),
      );
      expect(cellCostCalls, 0);
    });

    test('callers cannot raise the library-wide hard ceilings', () {
      const Dtw attemptedOverride = Dtw(
        maxSequenceLength: 1 << 30,
        maxStoredCells: 1 << 40,
      );
      expect(
        attemptedOverride.effectiveMaxSequenceLength,
        Dtw.hardMaxSequenceLength,
      );
      expect(
        attemptedOverride.effectiveMaxStoredCells,
        Dtw.hardMaxStoredCells,
      );
      expect(
        attemptedOverride.canAlign(Dtw.hardMaxSequenceLength + 1, 1),
        isFalse,
      );
    });

    test('identical sequences align on the diagonal at zero cost', () {
      final List<PoseFrame> frames = basicSideStep().sample(fps: 30);
      final List<JointAngleVector> v = frames
          .map((PoseFrame f) => const JointAngleExtractor()
              .extract(PoseNormalizer().normalize(f)))
          .toList(growable: false);

      const AngularSimilarity sim = AngularSimilarity();
      final DtwResult r = const Dtw().align(
        v.length,
        v.length,
        (int i, int j) => sim.distance(v[i], v[j]),
      );

      expect(r.normalizedCost, closeTo(0, 1e-9));
      expect(r.bandSaturated, isFalse);
      for (int i = 0; i < v.length; i++) {
        expect(r.refToLearner[i], i);
      }
    });

    test('a constant lag shows up as a uniform timing offset', () {
      // The learner performs the movement correctly, 200 ms late. DTW should
      // still match it frame-for-frame — the lateness must surface as timing,
      // not as a shape penalty.
      const int lagUs = 200000;
      final SyntheticSequence seq = basicSideStep();
      final List<PoseFrame> ref = seq.sample(fps: 30);
      final List<PoseFrame> learner = seq.sample(fps: 30, timeShiftUs: lagUs);

      final List<JointAngleVector> a = ref
          .map((PoseFrame f) => const JointAngleExtractor()
              .extract(PoseNormalizer().normalize(f)))
          .toList(growable: false);
      final List<JointAngleVector> b = learner
          .map((PoseFrame f) => const JointAngleExtractor()
              .extract(PoseNormalizer().normalize(f)))
          .toList(growable: false);

      const AngularSimilarity sim = AngularSimilarity();
      final DtwResult r = const Dtw()
          .align(a.length, b.length, (int i, int j) => sim.distance(a[i], b[j]));

      expect(r.normalizedCost, closeTo(0, 1e-9),
          reason: 'the shape was correct');

      final List<int> offsets = r.timingOffsetsUs(
        ref.map((PoseFrame f) => f.tUs).toList(growable: false),
        learner.map((PoseFrame f) => f.tUs).toList(growable: false),
      );
      expect(offsets.every((int o) => o == lagUs), isTrue,
          reason: 'the lateness was recovered exactly');
    });

    test('warps a faster performance onto the reference', () {
      final SyntheticSequence seq = basicSideStep();
      final List<PoseFrame> ref = seq.sample(fps: 30);
      final List<PoseFrame> fast = seq.sample(fps: 30, tempoRatio: 1.4);

      final List<JointAngleVector> a = ref
          .map((PoseFrame f) => const JointAngleExtractor()
              .extract(PoseNormalizer().normalize(f)))
          .toList(growable: false);
      final List<JointAngleVector> b = fast
          .map((PoseFrame f) => const JointAngleExtractor()
              .extract(PoseNormalizer().normalize(f)))
          .toList(growable: false);

      expect(b.length, lessThan(a.length));

      const AngularSimilarity sim = AngularSimilarity();
      final DtwResult r = const Dtw()
          .align(a.length, b.length, (int i, int j) => sim.distance(a[i], b[j]));

      expect(r.normalizedCost, lessThan(0.05),
          reason: 'same movement, different tempo — shape still matches');
      expect(r.refToLearner.first, 0);
      expect(r.refToLearner.last, b.length - 1);
    });

    test('a global tempo difference is absorbed, not flagged', () {
      // The corridor follows the diagonal of the two actual lengths, so a
      // learner who simply performs the whole phrase faster is aligned
      // normally. Only *internal* misplacement should trip the alarm.
      final SyntheticSequence seq = basicSideStep(beatIntervalUs: 1500000);
      final List<JointAngleVector> a = angleSeries(seq.sample(fps: 30));
      final List<JointAngleVector> b =
          angleSeries(seq.sample(fps: 30, tempoRatio: 1.5));

      const AngularSimilarity sim = AngularSimilarity();
      final DtwResult r = const Dtw()
          .align(a.length, b.length, (int i, int j) => sim.distance(a[i], b[j]));

      expect(r.bandSaturated, isFalse);
      expect(r.bandEdgeRatio, lessThan(0.15));
    });

    test('warping is penalised so the aligner cannot park on a rest pose', () {
      // Without a warping penalty the cheapest path through a wide corridor is
      // to hold one learner frame while the reference advances through its most
      // distinctive moments — scoring a motionless learner as if they had
      // performed the step. This is the regression guard for that.
      final List<JointAngleVector> a =
          angleSeries(basicSideStep().sample(fps: 30));
      final List<JointAngleVector> b =
          angleSeries(armsOverhead().sample(fps: 30));

      const AngularSimilarity sim = AngularSimilarity();
      double cost(int i, int j) => sim.distance(a[i], b[j]);

      final DtwResult penalised =
          const Dtw().align(a.length, b.length, cost);
      final DtwResult unpenalised =
          const Dtw(warpPenalty: 0).align(a.length, b.length, cost);

      expect(unpenalised.normalizedCost, lessThan(penalised.normalizedCost),
          reason: 'unpenalised DTW flatters a wrong movement by warping to it');
      expect(penalised.normalizedCost, greaterThan(0.15));
    });

    test('reports band saturation instead of a score it cannot justify', () {
      // The learner performs a four-count phrase a full second behind. Matching
      // them means riding the corridor wall for most of the take: the alignment
      // is at the limit of what we allow, and saying "I could not match this"
      // is the honest outcome. A shape score computed along a path we do not
      // believe would be a confident lie.
      final List<PoseFrame> ref = fourCountPhrase().sample(fps: 30);
      final List<PoseFrame> behind = delayedByFrames(ref, 30);

      final List<JointAngleVector> a = angleSeries(ref);
      final List<JointAngleVector> b = angleSeries(behind);
      expect(a.length, b.length, reason: 'same take length');

      const AngularSimilarity sim = AngularSimilarity();
      final DtwResult r = const Dtw()
          .align(a.length, b.length, (int i, int j) => sim.distance(a[i], b[j]));

      expect(r.bandEdgeRatio, greaterThan(0.15));
      expect(r.bandSaturated, isTrue);
    });

    test('handles empty input without throwing', () {
      final DtwResult r = const Dtw().align(0, 0, (int i, int j) => 0);
      expect(r.bandSaturated, isTrue);
      expect(r.normalizedCost, 1.0);
    });
  });
}
