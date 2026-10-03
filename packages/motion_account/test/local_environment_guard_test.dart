import 'package:flutter_test/flutter_test.dart';

import 'support/local_motion_environment.dart';

Map<String, String> _environment({
  String api = 'http://127.0.0.1:55321',
  String mailpit = 'http://127.0.0.1:55324',
}) => {
  'MOTION_LOCAL_API_URL': api,
  'MOTION_LOCAL_ANON_KEY': 'local-fixture-public-key',
  'MOTION_LOCAL_MAILPIT_URL': mailpit,
};

void main() {
  test('absent local environment is intentionally disabled', () {
    expect(LocalMotionEnvironment.from({}), isNull);
  });

  test('partial or empty environment fails before any network operation', () {
    expect(
      () => LocalMotionEnvironment.from({
        'MOTION_LOCAL_API_URL': 'http://127.0.0.1:55321',
      }),
      throwsArgumentError,
    );
    final empty = _environment()..['MOTION_LOCAL_ANON_KEY'] = '';
    expect(() => LocalMotionEnvironment.from(empty), throwsArgumentError);
  });

  for (final host in ['127.0.0.1', 'localhost']) {
    test('exact dedicated $host endpoints are accepted', () {
      final local = LocalMotionEnvironment.from(
        _environment(api: 'http://$host:55321', mailpit: 'http://$host:55324'),
      )!;
      expect(local.apiUrl, 'http://$host:55321');
      expect(local.mailpitUrl, 'http://$host:55324');
    });
  }

  for (final target in [
    'https://example.supabase.co',
    'http://127.0.0.1:54321',
    'http://127.0.0.1:55321/path',
    'http://127.0.0.1:55321/',
    'http://127.0.0.1:55321?target=external',
    'http://127.0.0.1:55321#fragment',
    'http://user@127.0.0.1:55321',
    'http://127.0.0.1.example.invalid:55321',
    'http://[::1]:55321',
  ]) {
    test('API rejects $target', () {
      expect(
        () => LocalMotionEnvironment.from(_environment(api: target)),
        throwsArgumentError,
      );
    });
  }

  test('external mail service rejected even with valid local Auth', () {
    expect(
      () => LocalMotionEnvironment.from(
        _environment(mailpit: 'https://mail.example.invalid'),
      ),
      throwsArgumentError,
    );
  });
}
