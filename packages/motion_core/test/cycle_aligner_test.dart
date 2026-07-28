import 'dart:math' as math;

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

/// Periodic scalar "pose signature": one value per frame, period [period],
/// starting [phaseShift] frames into the cycle. Asymmetric within the cycle
/// (sin + second harmonic) so that distinct phases are actually
/// distinguishable — a plain sine is mirror-symmetric around its peak.
List<double> loop(int length, int period, {int phaseShift = 0}) =>
    List<double>.generate(length, (int t) {
      final double p = 2 * math.pi * ((t + phaseShift) % period) / period;
      return 0.6 * math.sin(p) + 0.25 * math.sin(2 * p + 0.7);
    }, growable: false);

PairCost costOf(List<double> ref, List<double> learner) =>
    (int i, int j) => (ref[i] - learner[j]).abs() / 2.0;

void main() {
  const int period = 24; // ~0.8 s at 30 fps — the measured street-dance range
  const CycleAligner aligner = CycleAligner();

  group('CycleAligner (M-C-18)', () {
    test('recovers a known phase shift between two takes of the same loop',
        () {
      final List<double> ref = loop(period * 3, period);
      final List<double> learner = loop(period * 3, period, phaseShift: 9);

      final CycleAlignment a = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: learner.length,
        learnerPeriod: period,
        cost: costOf(ref, learner),
      );

      expect(a.resolved, isTrue, reason: a.reason);
      expect(a.normalizedCost, lessThan(0.02));
      // Learner runs 9 frames ahead: its cycle start sits period-9 frames in.
      expect(a.phaseOffset, period - 9);
      expect(a.secondCycleCost, isNotNull);
      expect(a.secondCycleCost!, lessThan(0.05),
          reason: 'the next cycle must agree — the material is truly periodic');
    });

    test('fixed-endpoint DTW on the same pair stays expensive — the problem '
        'this class exists for', () {
      final List<double> ref = loop(period * 3, period);
      final List<double> learner = loop(period * 3, period, phaseShift: 9);

      final DtwResult fixed = const Dtw()
          .align(ref.length, learner.length, costOf(ref, learner));
      final CycleAlignment cyclic = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: learner.length,
        learnerPeriod: period,
        cost: costOf(ref, learner),
      );

      expect(fixed.normalizedCost, greaterThan(10 * cyclic.normalizedCost),
          reason: 'endpoint constraint forces mismatched moments together; '
              'phase-resolved comparison is an order of magnitude cleaner');
    });

    test('different tempo still aligns once phase is resolved', () {
      const int learnerPeriod = 30; // 1.25× slower
      final List<double> ref = loop(period * 3, period);
      final List<double> learner =
          loop(learnerPeriod * 3, learnerPeriod, phaseShift: 11);

      final CycleAlignment a = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: learner.length,
        learnerPeriod: learnerPeriod,
        cost: costOf(ref, learner),
      );

      expect(a.resolved, isTrue, reason: a.reason);
      expect(a.normalizedCost, lessThan(0.08),
          reason: 'per-cycle DTW absorbs tempo difference inside the band');
    });

    test('a static learner is not rewarded', () {
      final List<double> ref = loop(period * 3, period);
      final List<double> still =
          List<double>.filled(period * 3, 0.55, growable: false);

      final CycleAlignment a = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: still.length,
        learnerPeriod: period,
        cost: costOf(ref, still),
      );

      // Every phase of a constant signal scores identically — the phase is
      // meaningless, and saying so beats awarding a score along an arbitrary
      // alignment (M-C-05's parking lesson, one level up).
      expect(a.resolved, isFalse);
      expect(a.similarity, 0.0);
    });

    test('phase-ambiguous material yields no verdict, not a guess', () {
      // Two cycles per asserted period: offsets half a period apart are
      // indistinguishable by construction.
      final List<double> ref = loop(period * 3, period ~/ 2);
      final List<double> learner = loop(period * 3, period ~/ 2, phaseShift: 3);

      final CycleAlignment a = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: learner.length,
        learnerPeriod: period,
        cost: costOf(ref, learner),
      );

      expect(a.resolved, isFalse);
      expect(a.reason, contains('ambiguous'));
    });

    test('refuses to wrap a learner shorter than two cycles', () {
      final List<double> ref = loop(period * 2, period);
      final List<double> learner = loop((period * 1.5).round(), period);

      final CycleAlignment a = aligner.align(
        refStart: 0,
        refPeriod: period,
        learnerLen: learner.length,
        learnerPeriod: period,
        cost: costOf(ref, learner),
      );

      expect(a.resolved, isFalse);
      expect(a.reason, contains('two cycles'));
    });
  });
}
