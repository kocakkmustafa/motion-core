import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a conservative bundled logical path', () {
    expect(
      () => PathPolicy.validate('assets/motion_content/models/pose.tflite'),
      returnsNormally,
    );
  });

  test('rejects paths instead of normalizing attacker-controlled input', () {
    for (final path in [
      '',
      '/absolute/file',
      'C:/windows/file',
      'https://example.org/file',
      'assets\\model.bin',
      'assets/../model.bin',
      'assets/./model.bin',
      'assets//model.bin',
      'assets/model.bin/',
      'assets/\u0000/model.bin',
      ' assets/model.bin',
    ]) {
      expect(
        () => PathPolicy.validate(path),
        throwsA(isA<ContentException>()),
        reason: path,
      );
    }
  });
}
