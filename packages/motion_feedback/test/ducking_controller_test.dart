import 'package:flutter_test/flutter_test.dart';
import 'package:motion_feedback/motion_feedback.dart';

void main() {
  group('DuckingController — bracket-safe nesting', () {
    test('isDucking is false with no active requests', () {
      final controller = DuckingController();
      expect(controller.isDucking, isFalse);
    });

    test('isDucking stays true while any token is outstanding', () {
      final controller = DuckingController();
      final t1 = controller.requestDuck();
      final t2 = controller.requestDuck();
      expect(controller.isDucking, isTrue);

      controller.release(t1);
      expect(controller.isDucking, isTrue, reason: 't2 is still outstanding');

      controller.release(t2);
      expect(controller.isDucking, isFalse);
    });

    test('releasing the same token twice is a safe no-op', () {
      final controller = DuckingController();
      final t1 = controller.requestDuck();
      controller.release(t1);
      expect(() => controller.release(t1), returnsNormally);
      expect(controller.isDucking, isFalse);
    });

    test('releasing an unknown token is a safe no-op and does not affect real tokens', () {
      final controllerA = DuckingController();
      final controllerB = DuckingController();
      final foreignToken = controllerB.requestDuck();
      final localToken = controllerA.requestDuck();

      expect(() => controllerA.release(foreignToken), returnsNormally);
      expect(controllerA.isDucking, isTrue, reason: 'the real local token is still outstanding');

      controllerA.release(localToken);
      expect(controllerA.isDucking, isFalse);
    });
  });
}
