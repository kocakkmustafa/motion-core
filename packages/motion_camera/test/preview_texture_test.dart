import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';

Map<String, Object> _running(
  String owner, {
  Map<String, Object> extra = const {},
}) => {
  'protocol': 1,
  'ownerId': owner,
  'generation': 1,
  'w': 720,
  'h': 1280,
  'clock': 'monotonic',
  'library': 'mp-ios-0.10.21',
  ...extra,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel control = MethodChannel('motion_camera/test/preview');
  final List<MethodCall> calls = <MethodCall>[];

  void mock(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null),
  );

  Map<Object?, Object?> args(MethodCall c) =>
      c.arguments! as Map<Object?, Object?>;

  test('a start without preview sends the unchanged protocol', () async {
    mock((c) => _running(args(c)['ownerId']! as String));
    final lease = MotionCameraController(control: control).createCaptureLease();
    final info = await lease.start(modelPath: '/m.task', modelId: 'm');
    expect(args(calls.single).containsKey('preview'), isFalse);
    expect(info.previewTextureId, isNull);
    expect(info.previewQuarterTurns, 0);
  });

  test('a preview start asks for it and decodes the texture', () async {
    mock(
      (c) => _running(
        args(c)['ownerId']! as String,
        extra: const {'previewTextureId': 7, 'previewQuarterTurns': 1},
      ),
    );
    final lease = MotionCameraController(control: control).createCaptureLease();
    final info = await lease.start(
      modelPath: '/m.task',
      modelId: 'm',
      preview: true,
    );
    expect(args(calls.single)['preview'], isTrue);
    expect(info.previewTextureId, 7);
    expect(info.previewQuarterTurns, 1);
  });

  test('a preview start without a texture fails by name', () async {
    mock((c) => _running(args(c)['ownerId']! as String));
    final controller = MotionCameraController(control: control);
    await expectLater(
      controller.startOwned(
        ownerId: 'owner-1',
        modelPath: '/m.task',
        modelId: 'm',
        preview: true,
      ),
      throwsA(
        isA<CameraException>().having(
          (e) => e.failure,
          'failure',
          CameraFailure.ownedProtocolUnavailable,
        ),
      ),
    );
  });

  testWidgets('the preview widget mirrors texture and overlay together', (
    tester,
  ) async {
    const info = CameraSessionInfo(
      width: 720,
      height: 1280,
      clockDomain: ClockDomain.monotonic,
      libraryTag: 'mp-ios-0.10.21',
      previewTextureId: 3,
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MotionCameraPreview(
          session: info,
          overlay: SizedBox(key: Key('overlay')),
        ),
      ),
    );
    expect(find.byType(Texture), findsOneWidget);
    expect(find.byKey(const Key('overlay')), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(Texture), matching: find.byType(Transform)),
      findsWidgets,
    );
  });

  testWidgets('no texture, no widget', (tester) async {
    const info = CameraSessionInfo(
      width: 720,
      height: 1280,
      clockDomain: ClockDomain.monotonic,
      libraryTag: 'mp-ios-0.10.21',
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MotionCameraPreview(session: info),
      ),
    );
    expect(find.byType(Texture), findsNothing);
  });
}
