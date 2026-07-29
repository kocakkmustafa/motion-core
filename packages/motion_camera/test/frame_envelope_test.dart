import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';
import 'package:motion_core/motion_core.dart';

Float32List packedLandmarks({double base = 0.5}) {
  final Float32List data = Float32List(132);
  for (int i = 0; i < Lm.count; i++) {
    data[i * 4] = base + i * 0.001; // x
    data[i * 4 + 1] = base - i * 0.001; // y
    data[i * 4 + 2] = 0.01 * i; // z
    data[i * 4 + 3] = 0.9; // vis
  }
  return data;
}

Map<Object?, Object?> validEvent({
  int t = 1000000,
  bool up = true,
  bool? inv,
}) =>
    <Object?, Object?>{
      't': t,
      'w': 1080,
      'h': 1920,
      'model': 'mp-ios-0.10.21+pose_landmarker_full',
      'clock': 'monotonic',
      'infUs': 21000,
      'dropped': 2,
      if (up) 'up': packedLandmarks(),
      if (inv != null) 'inv': inv ? packedLandmarks(base: 0.4) : null,
    };

void main() {
  group('CameraFrameEnvelope.decode', () {
    test('decodes a single-pass envelope with all measured fields', () {
      final CameraFrameEnvelope e = CameraFrameEnvelope.decode(validEvent());
      expect(e.tUs, 1000000);
      expect(e.size.width, 1080);
      expect(e.size.height, 1920);
      expect(e.clockDomain, ClockDomain.monotonic);
      expect(e.inferenceUs, 21000);
      expect(e.dropped, 2);
      expect(e.ran(BodyOrientation.upright), isTrue);
      expect(e.ran(BodyOrientation.inverted), isFalse);
      final PoseFrame frame = e.pass(BodyOrientation.upright)!;
      expect(frame.tUs, 1000000);
      expect(frame.modelVersion, 'mp-ios-0.10.21+pose_landmarker_full');
      expect(frame.landmarks.length, Lm.count);
      expect(frame.visibility(0), closeTo(0.9, 1e-6));
    });

    test('null pass value means "ran, no person" — distinct from absent', () {
      final CameraFrameEnvelope e =
          CameraFrameEnvelope.decode(validEvent(inv: false));
      expect(e.ran(BodyOrientation.inverted), isTrue);
      expect(e.pass(BodyOrientation.inverted), isNull);
    });

    test('asking for an unplanned pass throws, never returns null', () {
      final CameraFrameEnvelope e = CameraFrameEnvelope.decode(validEvent());
      expect(
        () => e.pass(BodyOrientation.inverted),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('was not run'),
        )),
      );
    });

    test('unknown clock domain string is a protocol error', () {
      final Map<Object?, Object?> event = validEvent();
      event['clock'] = 'wall';
      expect(() => CameraFrameEnvelope.decode(event),
          throwsA(isA<FormatException>()));
    });

    test('unknown clock domain decodes as ClockDomain.unknown', () {
      final Map<Object?, Object?> event = validEvent();
      event['clock'] = 'unknown';
      expect(CameraFrameEnvelope.decode(event).clockDomain,
          ClockDomain.unknown);
    });

    test('wrong landmark buffer length is a protocol error', () {
      final Map<Object?, Object?> event = validEvent();
      event['up'] = Float32List(131);
      expect(() => CameraFrameEnvelope.decode(event),
          throwsA(isA<FormatException>()));
    });

    test('an envelope with zero passes is a protocol error', () {
      final Map<Object?, Object?> event = validEvent(up: false);
      expect(() => CameraFrameEnvelope.decode(event),
          throwsA(isA<FormatException>()));
    });

    test('dual-pass envelope answers both orientations', () {
      final CameraFrameEnvelope e =
          CameraFrameEnvelope.decode(validEvent(inv: true));
      expect(e.pass(BodyOrientation.upright), isNotNull);
      expect(e.pass(BodyOrientation.inverted), isNotNull);
      // The two passes carry different landmark content.
      expect(
        e.pass(BodyOrientation.upright)!.point(0).x,
        isNot(closeTo(e.pass(BodyOrientation.inverted)!.point(0).x, 1e-9)),
      );
    });
  });
}
