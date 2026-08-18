import 'package:flutter_test/flutter_test.dart';
import 'package:motion_audio/motion_audio.dart';

void main() {
  group('LatencyCalibrationStore', () {
    test('fail-closed: an unknown route returns null, never a guessed value', () {
      final store = LatencyCalibrationStore();
      expect(store.calibrationFor('route-unknown'), isNull);
    });

    test('returns the calibration recorded for a route', () {
      final store = LatencyCalibrationStore();
      final calibration = LatencyCalibration(
        measuredLatency: const Duration(milliseconds: 193),
        calibratedAt: DateTime(2026, 1, 1),
        routeId: 'route-bt-1',
      );
      store.record(calibration);
      expect(store.calibrationFor('route-bt-1'), same(calibration));
    });

    test('re-calibrating the same route replaces the stale value (routes drift)', () {
      final store = LatencyCalibrationStore();
      store.record(LatencyCalibration(
        measuredLatency: const Duration(milliseconds: 193),
        calibratedAt: DateTime(2026, 1, 1),
        routeId: 'route-bt-1',
      ));
      final fresh = LatencyCalibration(
        measuredLatency: const Duration(milliseconds: 260),
        calibratedAt: DateTime(2026, 1, 2),
        routeId: 'route-bt-1',
      );
      store.record(fresh);
      expect(store.calibrationFor('route-bt-1'), same(fresh));
    });

    test('different routes do not collide', () {
      final store = LatencyCalibrationStore();
      final routeA = LatencyCalibration(
        measuredLatency: const Duration(milliseconds: 40),
        calibratedAt: DateTime(2026, 1, 1),
        routeId: 'route-wired',
      );
      final routeB = LatencyCalibration(
        measuredLatency: const Duration(milliseconds: 220),
        calibratedAt: DateTime(2026, 1, 1),
        routeId: 'route-bt-1',
      );
      store.record(routeA);
      store.record(routeB);
      expect(store.calibrationFor('route-wired'), same(routeA));
      expect(store.calibrationFor('route-bt-1'), same(routeB));
    });
  });
}
