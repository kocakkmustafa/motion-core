import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

class _WorkingAdapter implements SecureKeyAdapter {
  @override
  Future<SecureKeyResult> getOrCreateKey(String alias) async =>
      SecureKeySuccess([1, 2, 3, 4]);
}

class _BrokenAdapter implements SecureKeyAdapter {
  @override
  Future<SecureKeyResult> getOrCreateKey(String alias) async =>
      const SecureKeyFailure('keychain unavailable');
}

void main() {
  group('SecureKeyAdapter contract — failure cannot be mistaken for success', () {
    test('a working adapter yields SecureKeySuccess with key bytes', () async {
      final result = await _WorkingAdapter().getOrCreateKey('db-key');
      expect(result, isA<SecureKeySuccess>());
      expect((result as SecureKeySuccess).keyBytes, [1, 2, 3, 4]);
    });

    test('fail-closed: a broken adapter yields SecureKeyFailure, never fake key bytes', () async {
      final result = await _BrokenAdapter().getOrCreateKey('db-key');
      expect(result, isA<SecureKeyFailure>());
      expect(result, isNot(isA<SecureKeySuccess>()));
    });
  });
}
