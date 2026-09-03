import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

void main() {
  group('SemanticVersion', () {
    test('parses and compares strict major.minor.patch versions', () {
      expect(SemanticVersion.parse('1.2.3').toString(), '1.2.3');
      expect(
        SemanticVersion.parse('1.10.0'),
        greaterThan(SemanticVersion.parse('1.2.9')),
      );
      expect(
        SemanticVersion.parse('2.0.0'),
        greaterThan(SemanticVersion.parse('1.99.99')),
      );
      expect(
        SemanticVersion.parse('1.2.3') <= SemanticVersion.parse('1.2.3'),
        isTrue,
      );
      expect(
        SemanticVersion.parse('1.2.3') >= SemanticVersion.parse('1.2.3'),
        isTrue,
      );
      expect(
        SemanticVersion.parse('1.2.2') < SemanticVersion.parse('1.2.3'),
        isTrue,
      );
      expect(SemanticVersion.parse('1.2.3'), SemanticVersion.parse('1.2.3'));
      expect(
        SemanticVersion.parse('1.2.3').hashCode,
        SemanticVersion.parse('1.2.3').hashCode,
      );
    });

    test('rejects prerelease, build, partial, padded, and signed versions', () {
      for (final value in [
        '1.2',
        '1.2.3-beta',
        '1.2.3+4',
        '01.2.3',
        '-1.2.3',
        '1.2.3 ',
      ]) {
        expect(
          () => SemanticVersion.parse(value),
          throwsFormatException,
          reason: value,
        );
      }
    });
  });
}
