import 'dart:convert';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:motion_content/src/strict_json.dart';
import 'package:test/test.dart';

Object? decode(
  String source, {
  StrictJsonLimits limits = const StrictJsonLimits(),
}) => StrictJsonDecoder(
  limits: limits,
).decode(Uint8List.fromList(utf8.encode(source)));

ContentErrorCode decodeError(
  String source, {
  StrictJsonLimits limits = const StrictJsonLimits(),
}) {
  try {
    decode(source, limits: limits);
  } on ContentException catch (error) {
    return error.error.code;
  }
  throw StateError('Expected strict JSON rejection');
}

void main() {
  test('decodes every supported primitive and JSON string escape', () {
    expect(
      decode(
        r''' { "s":"\"\\\/\b\f\n\r\t\u0041", "t":true, "f":false, "n":null, "i":-12 } ''',
      ),
      <String, Object?>{
        's': '"\\/\b\f\n\r\tA',
        't': true,
        'f': false,
        'n': null,
        'i': -12,
      },
    );
    expect(decode('{}'), <String, Object?>{});
    expect(decode('[]'), <Object?>[]);
    expect(decode('[0,12]'), <Object?>[0, 12]);
    expect(decode(r'"\uD83D\uDE00"'), '😀');
  });

  test(
    'rejects malformed UTF-8, trailing input, invalid tokens, and floats',
    () {
      expect(
        () => const StrictJsonDecoder().decode(Uint8List.fromList([0xff])),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.parse,
          ),
        ),
      );
      for (final source in [
        '',
        '{}x',
        '{x:1}',
        '{"x" 1}',
        '{"x":1 "y":2}',
        '[1 2]',
        'tru',
        'unknown',
        '1.0',
        '1e2',
        '01',
        '-',
        '"unterminated',
        '"line\nbreak"',
        r'"\q"',
        r'"\u12x4"',
        r'"\u12"',
        r'"\uD800"',
        r'"\uDC00"',
        r'"\uD800\u0041"',
      ]) {
        expect(decodeError(source), ContentErrorCode.parse, reason: source);
      }
    },
  );

  test('custom object and collection ceilings fail before growth', () {
    expect(
      decodeError(
        '{"a":1,"b":2}',
        limits: const StrictJsonLimits(maxObjectEntries: 1),
      ),
      ContentErrorCode.resourceLimit,
    );
    expect(
      decodeError(
        '[1,2]',
        limits: const StrictJsonLimits(maxCollectionEntries: 1),
      ),
      ContentErrorCode.resourceLimit,
    );
  });

  test('rejects duplicate escaped-equivalent keys', () {
    expect(
      decodeError(r'{"a":1,"\u0061":2}'),
      ContentErrorCode.duplicateJsonKey,
    );
  });
}
