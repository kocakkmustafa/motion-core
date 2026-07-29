import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';
import 'package:motion_core/motion_core.dart';

void main() {
  group('PassPlan', () {
    test('maps expectations to plans', () {
      expect(
        PassPlan.forExpectation(
            const OrientationExpectation.exactly(BodyOrientation.upright)),
        PassPlan.uprightOnly,
      );
      expect(
        PassPlan.forExpectation(
            const OrientationExpectation.exactly(BodyOrientation.inverted)),
        PassPlan.invertedOnly,
      );
      expect(
        PassPlan.forExpectation(const OrientationExpectation.ambiguous()),
        PassPlan.dual,
      );
    });

    test('covers() mirrors what each plan runs', () {
      expect(PassPlan.uprightOnly.covers(BodyOrientation.upright), isTrue);
      expect(PassPlan.uprightOnly.covers(BodyOrientation.inverted), isFalse);
      expect(PassPlan.invertedOnly.covers(BodyOrientation.upright), isFalse);
      expect(PassPlan.invertedOnly.covers(BodyOrientation.inverted), isTrue);
      expect(PassPlan.dual.covers(BodyOrientation.upright), isTrue);
      expect(PassPlan.dual.covers(BodyOrientation.inverted), isTrue);
    });
  });
}
