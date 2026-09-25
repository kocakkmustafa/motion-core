import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';

void main() {
  test('production service URL must use HTTPS', () async {
    await expectLater(
      MotionAccountRuntime.initialize(
        url: 'http://motion.example.invalid',
        publishableKey: 'public-test-key',
        app: MotionApp.ostinato,
        emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
        onDeletedAccount: (_) async {},
        localAccountIds: () async => const <String>[],
      ),
      throwsArgumentError,
    );
  });

  test('another app callback is rejected before starting auth', () async {
    await expectLater(
      MotionAccountRuntime.initialize(
        url: 'https://motion.example.invalid',
        publishableKey: 'public-test-key',
        app: MotionApp.gravita,
        emailRedirectTo: 'com.yulalab.jablab://auth/callback',
        onDeletedAccount: (_) async {},
        localAccountIds: () async => const <String>[],
      ),
      throwsArgumentError,
    );
  });
}
