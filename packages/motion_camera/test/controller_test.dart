import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel control = MethodChannel('motion_camera/control');
  final List<MethodCall> calls = <MethodCall>[];

  void mockControl(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (MethodCall call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  group('MotionCameraController', () {
    test('start sends the full request and decodes session facts', () async {
      mockControl(
        (MethodCall call) async => <Object?, Object?>{
          'w': 1080,
          'h': 1920,
          'clock': 'monotonic',
          'library': 'mp-ios-0.10.21',
        },
      );
      final MotionCameraController controller = MotionCameraController();
      final CameraSessionInfo info = await controller.start(
        modelPath: '/models/pose_landmarker_full.task',
        modelId: 'pose_landmarker_full',
        lens: CameraLens.front,
        initialPlan: PassPlan.dual,
      );
      expect(info.width, 1080);
      expect(info.height, 1920);
      expect(info.clockDomain, ClockDomain.monotonic);
      expect(info.libraryTag, 'mp-ios-0.10.21');
      expect(calls.single.method, 'start');
      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(args['modelId'], 'pose_landmarker_full');
      expect(args['lens'], 'front');
      expect(args['plan'], 'dual');
    });

    test('recognized native refusal becomes a typed CameraException', () async {
      mockControl(
        (MethodCall call) async => throw PlatformException(
          code: 'camera-permission-denied',
          message: 'user has not granted camera access',
        ),
      );
      final MotionCameraController controller = MotionCameraController();
      expect(
        () => controller.start(modelPath: '/m.task', modelId: 'm'),
        throwsA(
          isA<CameraException>().having(
            (CameraException e) => e.failure,
            'failure',
            CameraFailure.permissionDenied,
          ),
        ),
      );
    });

    test('unrecognized platform error is rethrown untranslated', () async {
      mockControl(
        (MethodCall call) async =>
            throw PlatformException(code: 'something-novel'),
      );
      final MotionCameraController controller = MotionCameraController();
      expect(() => controller.stop(), throwsA(isA<PlatformException>()));
    });

    test('stop is idempotent at the Dart-facing contract', () async {
      mockControl((MethodCall call) async => null);
      final MotionCameraController controller = MotionCameraController();

      await controller.stop();
      await controller.stop();

      expect(calls.map((MethodCall call) => call.method), <String>[
        'stop',
        'stop',
      ]);
    });

    test('lifecycle teardown refusals stay typed at the Dart boundary', () {
      expect(
        CameraFailure.fromCode('lifecycle-unavailable'),
        CameraFailure.lifecycleUnavailable,
      );
      expect(
        CameraFailure.fromCode('session-interrupted'),
        CameraFailure.sessionInterrupted,
      );
    });

    test('setPassPlan sends the wire name', () async {
      mockControl((MethodCall call) async => null);
      final MotionCameraController controller = MotionCameraController();
      await controller.setPassPlan(PassPlan.invertedOnly);
      expect(calls.single.method, 'setPassPlan');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['plan'],
        'inverted',
      );
    });
  });
}
