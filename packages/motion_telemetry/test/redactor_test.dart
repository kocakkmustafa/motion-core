import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

void main() {
  group('Redactor.allowsKey', () {
    final redactor = Redactor();

    test('allows generic operational attribute keys', () {
      for (final key in ['app_version', 'error_class', 'duration_bucket', 'config_version']) {
        expect(redactor.allowsKey(key), isTrue, reason: key);
      }
    });

    test('fail-closed: rejects forbidden-content keys case-insensitively', () {
      for (final key in [
        'angle',
        'jointAngle',
        'landmark',
        'landmarks',
        'audioClipUrl',
        'videoPath',
        'injuryNote',
        'songTitle',
        'choreographyName',
        'freeTextComment',
      ]) {
        expect(redactor.allowsKey(key), isFalse, reason: key);
      }
    });
  });

  group('Redactor.allowsStringValue — safe-token shape, not a denylist', () {
    final redactor = Redactor();

    test('allows short enum-like tokens', () {
      for (final v in ['ios', 'network_timeout', 'v2.3.1', 'ANDROID']) {
        expect(redactor.allowsStringValue(v), isTrue, reason: v);
      }
    });

    test('fail-closed: rejects values containing spaces (shaped like free text)', () {
      expect(redactor.allowsStringValue('felt a sharp pain in my knee'), isFalse);
    });

    test('fail-closed: rejects values longer than the safe-token limit', () {
      expect(redactor.allowsStringValue('a' * 41), isFalse);
    });
  });
}
