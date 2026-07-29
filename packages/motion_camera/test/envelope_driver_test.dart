import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';
import 'package:motion_core/motion_core.dart';

import 'frame_envelope_test.dart' show validEvent;

void main() {
  group('EnvelopeDriver', () {
    test('answers detectAs from the loaded envelope', () {
      final EnvelopeDriver driver = EnvelopeDriver();
      driver.load(CameraFrameEnvelope.decode(validEvent(t: 5000)));
      final PoseFrame? frame = driver.detectAs(5000, BodyOrientation.upright);
      expect(frame, isNotNull);
      expect(frame!.tUs, 5000);
    });

    test('detectAs before any envelope throws', () {
      expect(
        () => EnvelopeDriver().detectAs(1, BodyOrientation.upright),
        throwsStateError,
      );
    });

    test('timestamp mismatch throws — desync must fail loud', () {
      final EnvelopeDriver driver = EnvelopeDriver();
      driver.load(CameraFrameEnvelope.decode(validEvent(t: 5000)));
      expect(
        () => driver.detectAs(6000, BodyOrientation.upright),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('desynchronized'),
        )),
      );
    });

    test('feeds OrientationAwarePoseSource end to end', () {
      final EnvelopeDriver driver = EnvelopeDriver();
      final OrientationAwarePoseSource source =
          OrientationAwarePoseSource(driver);
      driver.load(CameraFrameEnvelope.decode(validEvent(t: 7000)));
      final OrientationResolution r = source.next(
        7000,
        const OrientationExpectation.exactly(BodyOrientation.upright),
      );
      // The synthetic packed landmarks are not an anatomically plausible
      // skeleton, so the structural validator may refuse — what this test
      // pins is the seam: the source consumed the envelope without throwing
      // and produced a resolution for the same timestamp.
      expect(r.tUs, 7000);
      expect(r.dualPass, isFalse);
    });
  });
}
