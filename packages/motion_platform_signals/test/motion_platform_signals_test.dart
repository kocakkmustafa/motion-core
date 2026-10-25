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

  test('a shared store age range maps to the signal', () async {
    answer((call) {
      expect(call.method, 'requestAgeSignal');
      expect(call.arguments, {
        'ageGates': [13, 16, 18],
      });
      return {
        'source': 'apple',
        'shared': true,
        'lower': 13,
        'upper': 15,
        'declaration': 'guardianDeclared',
      };
    });
    final signal = await MotionPlatformSignals.requestAgeSignal();
    expect(signal?.source, 'apple');
    expect(signal?.shared, isTrue);
    expect((signal?.lower, signal?.upper), (13, 15));
    expect(signal?.declaration, 'guardianDeclared');
  });

  test('declined, open-ended and malformed answers', () async {
    answer((_) => {'source': 'google', 'shared': false, 'lower': 13});
    final declined = await MotionPlatformSignals.requestAgeSignal();
    expect(declined?.shared, isFalse);
    expect(declined?.lower, isNull, reason: 'bounds only when shared');

    answer(
      (_) => {'source': 'google', 'shared': true, 'lower': 18, 'upper': null},
    );
    final adult = await MotionPlatformSignals.requestAgeSignal();
    expect((adult?.lower, adult?.upper), (18, null));

    for (final raw in <Object?>[
      null,
      'x',
      {'source': 'other', 'shared': true},
      {'source': 'apple'},
      {'source': 'apple', 'shared': true, 'lower': 16, 'upper': 13},
    ]) {
      answer((_) => raw);
      expect(
        await MotionPlatformSignals.requestAgeSignal(),
        isNull,
        reason: '$raw',
      );
    }
    answer((_) => throw PlatformException(code: 'notAvailable'));
    expect(await MotionPlatformSignals.requestAgeSignal(), isNull);
  });
}
