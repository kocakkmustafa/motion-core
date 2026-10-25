import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_platform_signals/motion_platform_signals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      MotionPlatformSignals.channel,
      (call) async => handler(call),
    );
  }

  tearDown(
    () =>
        messenger.setMockMethodCallHandler(MotionPlatformSignals.channel, null),
  );

  test('the App Store app transaction ID passes through', () async {
    answer((call) {
      expect(call.method, 'appTransactionId');
      return '704289572311429985';
    });
    expect(
      await MotionPlatformSignals.appTransactionId(),
      '704289572311429985',
    );
  });

  test(
    'unavailable, empty, oversized or failing answers become null',
    () async {
      for (final value in <Object?>[null, '', 'x' * 65]) {
        answer((_) => value);
        expect(await MotionPlatformSignals.appTransactionId(), isNull);
      }
      answer((_) => throw PlatformException(code: 'storekit'));
      expect(await MotionPlatformSignals.appTransactionId(), isNull);
      messenger.setMockMethodCallHandler(MotionPlatformSignals.channel, null);
      expect(await MotionPlatformSignals.appTransactionId(), isNull);
    },
  );
}
