import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

void main() {
  test('canonical bytes and digest match an independent fixed vector', () {
    final vector = <String, Object?>{
      'z': <Object?>[1, 2],
      'a': <String, Object?>{'b': true, 'a': 'x'},
    };

    expect(canonicalJsonEncode(vector), '{"a":{"a":"x","b":true},"z":[1,2]}');
    expect(
      computeCatalogDigest(vector),
      '5dcaf8d225f6bd5aa5f1f69f8634570b1d19ad043897cff2b7ee53013d292b7f',
    );
  });

  test('object order is canonical while array order remains semantic', () {
    final left = <String, Object?>{
      'z': <Object?>[1, 2],
      'a': <String, Object?>{'b': true, 'a': 'x'},
    };
    final reordered = <String, Object?>{
      'a': <String, Object?>{'a': 'x', 'b': true},
      'z': <Object?>[1, 2],
    };
    final arrayChanged = <String, Object?>{
      'a': <String, Object?>{'a': 'x', 'b': true},
      'z': <Object?>[2, 1],
    };

    expect(computeCatalogDigest(left), computeCatalogDigest(reordered));
    expect(
      computeCatalogDigest(left),
      isNot(computeCatalogDigest(arrayChanged)),
    );
  });

  test('catalogDigest is never included in its own digest input', () {
    final first = <String, Object?>{
      'schemaVersion': 1,
      'catalogDigest': 'first',
    };
    final second = <String, Object?>{
      'schemaVersion': 1,
      'catalogDigest': 'second',
    };
    expect(computeCatalogDigest(first), computeCatalogDigest(second));
  });

  test('floating-point and non-finite values are rejected', () {
    for (final value in [1.5, double.nan, double.infinity]) {
      expect(
        () => canonicalJsonEncode(<String, Object?>{'value': value}),
        throwsFormatException,
      );
    }
  });

  test('unsupported values and non-string object keys are rejected', () {
    expect(
      () => canonicalJsonEncode(<Object?, Object?>{1: 'value'}),
      throwsFormatException,
    );
    expect(() => canonicalJsonEncode(DateTime(2026)), throwsFormatException);
  });
}
