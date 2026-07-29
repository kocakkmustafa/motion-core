import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';

import 'frame_envelope_test.dart' show validEvent;

CameraFrameEnvelope envelopeAt(int tUs, {int dropped = 0, int infUs = 20000}) {
  final Map<Object?, Object?> event = validEvent(t: tUs);
  event['dropped'] = dropped;
  event['infUs'] = infUs;
  return CameraFrameEnvelope.decode(event);
}

void main() {
  group('RateMeter', () {
    test('reports null before two events — unmeasurable is not zero', () {
      final RateMeter meter = RateMeter();
      expect(meter.perSecond, isNull);
      meter.record(0);
      expect(meter.perSecond, isNull);
    });

    test('measures a steady 30fps stream', () {
      final RateMeter meter = RateMeter();
      for (int i = 0; i < 60; i++) {
        meter.record(i * 33333);
      }
      expect(meter.perSecond, closeTo(30.0, 0.1));
    });

    test('window forgets old events: a stall collapses the reading', () {
      final RateMeter meter = RateMeter(windowUs: 1000000);
      for (int i = 0; i < 30; i++) {
        meter.record(i * 33333);
      }
      // 3-second stall, then two slow frames 500ms apart.
      meter.record(4000000);
      meter.record(4500000);
      // Only the two post-stall frames remain in the 1s window.
      expect(meter.perSecond, closeTo(2.0, 0.01));
    });
  });

  group('ThroughputMonitor', () {
    test('two-speed reading: captured vs judged vs ratio', () {
      final ThroughputMonitor monitor = ThroughputMonitor();
      // Inference keeps up with every other camera frame: each envelope
      // reports one dropped frame. Envelopes at 15/s → camera at 30/s.
      for (int i = 0; i < 30; i++) {
        monitor.record(envelopeAt(i * 66666, dropped: 1));
      }
      expect(monitor.judgedPerSecond, closeTo(15.0, 0.1));
      expect(monitor.capturedPerSecond, closeTo(30.0, 0.3));
      expect(monitor.judgedRatio, closeTo(0.5, 0.01));
      expect(monitor.meanInferenceUs, closeTo(20000, 1));
    });

    test('windowed ratio recovers after an early stall (no lifetime poison)',
        () {
      final ThroughputMonitor monitor = ThroughputMonitor(windowUs: 1000000);
      // Bad start: heavy drops.
      for (int i = 0; i < 10; i++) {
        monitor.record(envelopeAt(i * 100000, dropped: 5));
      }
      // Recovery: clean 30fps for 2 seconds.
      for (int i = 0; i < 60; i++) {
        monitor.record(envelopeAt(2000000 + i * 33333));
      }
      // The window only sees the clean tail…
      expect(monitor.judgedRatio, closeTo(1.0, 0.01));
      expect(monitor.judgedPerSecond, closeTo(30.0, 0.5));
      // …while the session totals still tell the whole story.
      expect(monitor.sessionDroppedCount, 50);
      expect(monitor.sessionJudgedCount, 70);
    });

    test('empty monitor reports null everywhere', () {
      final ThroughputMonitor monitor = ThroughputMonitor();
      expect(monitor.judgedPerSecond, isNull);
      expect(monitor.capturedPerSecond, isNull);
      expect(monitor.judgedRatio, isNull);
      expect(monitor.meanInferenceUs, isNull);
    });
  });
}
