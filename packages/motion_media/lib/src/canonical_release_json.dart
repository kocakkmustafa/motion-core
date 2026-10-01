import 'dart:convert';

/// A bounded, exact-byte JSON reader for the v2l release contract.
///
/// This accepts Python's `json.dumps(ensure_ascii=False, sort_keys=True,
/// separators=(',', ':'), allow_nan=False)` representation for the v2l schema.
/// The schema has integer-only numeric fields. Duplicate decoded object keys
/// and excessive nesting are rejected before Dart's JSON decoder runs.
final class CanonicalReleaseJson {
  CanonicalReleaseJson._();

  static const int maxDepth = 64;

  static Map<String, Object?> parseObject(
    List<int> raw, {
    required int maxBytes,
    required String code,
  }) {
    if (raw.isEmpty || raw.length > maxBytes) {
      throw CanonicalReleaseJsonError('${code}_SIZE');
    }
    try {
      final source = utf8.decode(raw, allowMalformed: false);
      _JsonGuard(source, code).inspect();
      final value = jsonDecode(source);
      if (value is! Map<String, dynamic>) {
        throw CanonicalReleaseJsonError('${code}_OBJECT');
      }
      if (!_sameBytes(raw, encode(value))) {
        throw CanonicalReleaseJsonError('${code}_NONCANONICAL');
      }
      return value.cast<String, Object?>();
    } on CanonicalReleaseJsonError {
      rethrow;
    } on FormatException {
      throw CanonicalReleaseJsonError('${code}_JSON');
    } on RangeError {
      throw CanonicalReleaseJsonError('${code}_JSON');
    }
  }

  static List<int> encode(Object? value) => utf8.encode(_writeValue(value));

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _writeValue(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is int) return value.toString();
    if (value is String) return _writeString(value);
    if (value is List) {
      return '[${value.map(_writeValue).join(',')}]';
    }
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('JSON object key is not a string');
      }
      final keys = value.keys.cast<String>().toList()
        ..sort(_compareUnicodeScalars);
      return '{${keys.map((key) => '${_writeString(key)}:${_writeValue(value[key])}').join(',')}}';
    }
    // v2l has no floating-point fields. Reject even finite doubles instead
    // of allowing Python/Dart formatting differences to become ambiguous.
    throw const FormatException('Unsupported JSON value');
  }

  static int _compareUnicodeScalars(String a, String b) {
    final ai = a.runes.iterator;
    final bi = b.runes.iterator;
    while (true) {
      final hasA = ai.moveNext();
      final hasB = bi.moveNext();
      if (!hasA || !hasB) return hasA == hasB ? 0 : (hasA ? 1 : -1);
      final delta = ai.current.compareTo(bi.current);
      if (delta != 0) return delta;
    }
  }

  static String _writeString(String value) {
    final out = StringBuffer('"');
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length) {
          throw const FormatException('Unpaired surrogate');
        }
        final low = value.codeUnitAt(i);
        if (low < 0xdc00 || low > 0xdfff) {
          throw const FormatException('Unpaired surrogate');
        }
        final scalar = 0x10000 + ((unit - 0xd800) << 10) + (low - 0xdc00);
        out.write(String.fromCharCode(scalar));
        continue;
      }
      if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Unpaired surrogate');
      }
      switch (unit) {
        case 0x22:
          out.write(r'\"');
          break;
        case 0x5c:
          out.write(r'\\');
          break;
        case 0x08:
          out.write(r'\b');
          break;
        case 0x0c:
          out.write(r'\f');
          break;
        case 0x0a:
          out.write(r'\n');
          break;
        case 0x0d:
          out.write(r'\r');
          break;
        case 0x09:
          out.write(r'\t');
          break;
        default:
          if (unit < 0x20) {
            out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
          } else {
            out.writeCharCode(unit);
          }
          break;
      }
    }
    out.write('"');
    return out.toString();
  }
}

final class CanonicalReleaseJsonError implements Exception {
  const CanonicalReleaseJsonError(this.code);

  final String code;

  @override
  String toString() => 'CanonicalReleaseJsonError: $code';
}

/// Small lexical pass: limits depth and catches duplicate decoded keys.
/// `jsonDecode` performs complete JSON syntax validation afterward.
final class _JsonGuard {
  _JsonGuard(this.source, this.code);

  static final RegExp _number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );

  final String source;
  final String code;
  int index = 0;

  void inspect() {
    _space();
    _value(0);
    _space();
    if (index != source.length) _invalid();
  }

  void _value(int depth) {
    if (depth > CanonicalReleaseJson.maxDepth) {
      throw CanonicalReleaseJsonError('${code}_DEPTH');
    }
    _space();
    if (index >= source.length) _invalid();
    switch (source.codeUnitAt(index)) {
      case 0x7b: // {
        _object(depth);
        return;
      case 0x5b: // [
        _array(depth);
        return;
      case 0x22: // "
        _string();
        return;
      case 0x74: // true
        _literal('true');
        return;
      case 0x66: // false
        _literal('false');
        return;
      case 0x6e: // null
        _literal('null');
        return;
      default:
        final match = _number.matchAsPrefix(source, index);
        if (match == null) _invalid();
        index = match.end;
        return;
    }
  }

  void _object(int depth) {
    index++;
    _space();
    if (_take(0x7d)) return;
    final keys = <String>{};
    while (true) {
      _space();
      if (index >= source.length || source.codeUnitAt(index) != 0x22) {
        _invalid();
      }
      final key = _string();
      if (!keys.add(key)) {
        throw const CanonicalReleaseJsonError('DUPLICATE_JSON_KEY');
      }
      _space();
      if (!_take(0x3a)) _invalid(); // :
      _value(depth + 1);
      _space();
      if (_take(0x7d)) return;
      if (!_take(0x2c)) _invalid(); // ,
    }
  }

  void _array(int depth) {
    index++;
    _space();
    if (_take(0x5d)) return;
    while (true) {
      _value(depth + 1);
      _space();
      if (_take(0x5d)) return;
      if (!_take(0x2c)) _invalid();
    }
  }

  String _string() {
    final start = index++;
    while (index < source.length) {
      final unit = source.codeUnitAt(index++);
      if (unit == 0x22) {
        final parsed = jsonDecode(source.substring(start, index));
        if (parsed is! String) _invalid();
        return parsed;
      }
      if (unit == 0x5c) {
        if (index >= source.length) _invalid();
        final escaped = source.codeUnitAt(index++);
        if (escaped == 0x75) {
          if (index + 4 > source.length) _invalid();
          for (var j = 0; j < 4; j++) {
            final hex = source.codeUnitAt(index++);
            if (!((hex >= 0x30 && hex <= 0x39) ||
                (hex >= 0x41 && hex <= 0x46) ||
                (hex >= 0x61 && hex <= 0x66))) {
              _invalid();
            }
          }
        }
      } else if (unit < 0x20) {
        _invalid();
      }
    }
    _invalid();
  }

  void _literal(String text) {
    if (!source.startsWith(text, index)) _invalid();
    index += text.length;
  }

  bool _take(int unit) {
    if (index >= source.length || source.codeUnitAt(index) != unit) {
      return false;
    }
    index++;
    return true;
  }

  void _space() {
    while (index < source.length) {
      final c = source.codeUnitAt(index);
      if (c != 0x20 && c != 0x09 && c != 0x0a && c != 0x0d) return;
      index++;
    }
  }

  Never _invalid() => throw CanonicalReleaseJsonError('${code}_JSON');
}
