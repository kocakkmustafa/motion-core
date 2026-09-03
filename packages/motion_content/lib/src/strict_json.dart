import 'dart:convert';
import 'dart:typed_data';

import 'content_error.dart';

class StrictJsonLimits {
  const StrictJsonLimits({
    this.maxBytes = 1024 * 1024,
    this.maxNesting = 16,
    this.maxStringLength = 16 * 1024,
    this.maxCollectionEntries = 8192,
    this.maxObjectEntries = 128,
  });

  final int maxBytes;
  final int maxNesting;
  final int maxStringLength;
  final int maxCollectionEntries;
  final int maxObjectEntries;
}

class StrictJsonDecoder {
  const StrictJsonDecoder({this.limits = const StrictJsonLimits()});

  final StrictJsonLimits limits;

  Object? decode(Uint8List bytes) {
    if (bytes.length > limits.maxBytes) {
      failContent(ContentErrorCode.resourceLimit);
    }
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      failContent(ContentErrorCode.parse);
    }
    try {
      return _Parser(source, limits).parseDocument();
    } on _JsonFailure catch (failure) {
      failContent(failure.code);
    }
  }
}

class _JsonFailure implements Exception {
  const _JsonFailure(this.code);
  final ContentErrorCode code;
}

class _Parser {
  _Parser(this.source, this.limits);

  final String source;
  final StrictJsonLimits limits;
  int index = 0;

  Object? parseDocument() {
    _skipWhitespace();
    final value = _parseValue(0);
    _skipWhitespace();
    if (index != source.length) {
      throw const _JsonFailure(ContentErrorCode.parse);
    }
    return value;
  }

  Object? _parseValue(int depth) {
    _skipWhitespace();
    if (index >= source.length) {
      throw const _JsonFailure(ContentErrorCode.parse);
    }
    final code = source.codeUnitAt(index);
    if (code == 0x7b) return _parseObject(depth);
    if (code == 0x5b) return _parseArray(depth);
    if (code == 0x22) return _parseString();
    if (code == 0x74) return _parseLiteral('true', true);
    if (code == 0x66) return _parseLiteral('false', false);
    if (code == 0x6e) return _parseLiteral('null', null);
    if (code == 0x2d || _isDigit(code)) return _parseInteger();
    throw const _JsonFailure(ContentErrorCode.parse);
  }

  Map<String, Object?> _parseObject(int depth) {
    _enterContainer(depth);
    index += 1;
    final result = <String, Object?>{};
    _skipWhitespace();
    if (_consume(0x7d)) return result;
    while (true) {
      if (result.length >= limits.maxObjectEntries) {
        throw const _JsonFailure(ContentErrorCode.resourceLimit);
      }
      _skipWhitespace();
      if (index >= source.length || source.codeUnitAt(index) != 0x22) {
        throw const _JsonFailure(ContentErrorCode.parse);
      }
      final key = _parseString();
      if (result.containsKey(key)) {
        throw const _JsonFailure(ContentErrorCode.duplicateJsonKey);
      }
      _skipWhitespace();
      if (!_consume(0x3a)) throw const _JsonFailure(ContentErrorCode.parse);
      result[key] = _parseValue(depth + 1);
      _skipWhitespace();
      if (_consume(0x7d)) return result;
      if (!_consume(0x2c)) throw const _JsonFailure(ContentErrorCode.parse);
    }
  }

  List<Object?> _parseArray(int depth) {
    _enterContainer(depth);
    index += 1;
    final result = <Object?>[];
    _skipWhitespace();
    if (_consume(0x5d)) return result;
    while (true) {
      if (result.length >= limits.maxCollectionEntries) {
        throw const _JsonFailure(ContentErrorCode.resourceLimit);
      }
      result.add(_parseValue(depth + 1));
      _skipWhitespace();
      if (_consume(0x5d)) return result;
      if (!_consume(0x2c)) throw const _JsonFailure(ContentErrorCode.parse);
    }
  }

  void _enterContainer(int depth) {
    if (depth >= limits.maxNesting) {
      throw const _JsonFailure(ContentErrorCode.resourceLimit);
    }
  }

  String _parseString() {
    index += 1;
    final result = StringBuffer();
    var decodedLength = 0;
    while (index < source.length) {
      final code = source.codeUnitAt(index++);
      if (code == 0x22) return result.toString();
      if (code < 0x20) throw const _JsonFailure(ContentErrorCode.parse);
      if (code != 0x5c) {
        result.writeCharCode(code);
        decodedLength += 1;
      } else {
        if (index >= source.length) {
          throw const _JsonFailure(ContentErrorCode.parse);
        }
        final escaped = source.codeUnitAt(index++);
        if (escaped == 0x75) {
          final first = _parseHexCodeUnit();
          if (first >= 0xd800 && first <= 0xdbff) {
            if (index + 2 > source.length ||
                source.codeUnitAt(index) != 0x5c ||
                source.codeUnitAt(index + 1) != 0x75) {
              throw const _JsonFailure(ContentErrorCode.parse);
            }
            index += 2;
            final second = _parseHexCodeUnit();
            if (second < 0xdc00 || second > 0xdfff) {
              throw const _JsonFailure(ContentErrorCode.parse);
            }
            result
              ..writeCharCode(first)
              ..writeCharCode(second);
            decodedLength += 2;
          } else {
            if (first >= 0xdc00 && first <= 0xdfff) {
              throw const _JsonFailure(ContentErrorCode.parse);
            }
            result.writeCharCode(first);
            decodedLength += 1;
          }
        } else {
          switch (escaped) {
            case 0x22:
            case 0x5c:
            case 0x2f:
              result.writeCharCode(escaped);
            case 0x62:
              result.writeCharCode(0x08);
            case 0x66:
              result.writeCharCode(0x0c);
            case 0x6e:
              result.writeCharCode(0x0a);
            case 0x72:
              result.writeCharCode(0x0d);
            case 0x74:
              result.writeCharCode(0x09);
            default:
              throw const _JsonFailure(ContentErrorCode.parse);
          }
          decodedLength += 1;
        }
      }
      if (decodedLength > limits.maxStringLength) {
        throw const _JsonFailure(ContentErrorCode.resourceLimit);
      }
    }
    throw const _JsonFailure(ContentErrorCode.parse);
  }

  int _parseHexCodeUnit() {
    if (index + 4 > source.length) {
      throw const _JsonFailure(ContentErrorCode.parse);
    }
    var value = 0;
    for (var offset = 0; offset < 4; offset += 1) {
      final code = source.codeUnitAt(index++);
      final digit = switch (code) {
        >= 0x30 && <= 0x39 => code - 0x30,
        >= 0x41 && <= 0x46 => code - 0x41 + 10,
        >= 0x61 && <= 0x66 => code - 0x61 + 10,
        _ => -1,
      };
      if (digit < 0) throw const _JsonFailure(ContentErrorCode.parse);
      value = value * 16 + digit;
    }
    return value;
  }

  int _parseInteger() {
    final start = index;
    if (_consume(0x2d) && index >= source.length) {
      throw const _JsonFailure(ContentErrorCode.parse);
    }
    if (_consume(0x30)) {
      if (index < source.length && _isDigit(source.codeUnitAt(index))) {
        throw const _JsonFailure(ContentErrorCode.parse);
      }
    } else {
      if (index >= source.length ||
          !_isNonZeroDigit(source.codeUnitAt(index))) {
        throw const _JsonFailure(ContentErrorCode.parse);
      }
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        index += 1;
      }
    }
    if (index < source.length) {
      final next = source.codeUnitAt(index);
      if (next == 0x2e || next == 0x65 || next == 0x45) {
        throw const _JsonFailure(ContentErrorCode.parse);
      }
    }
    final value = int.tryParse(source.substring(start, index));
    if (value == null) throw const _JsonFailure(ContentErrorCode.resourceLimit);
    return value;
  }

  T _parseLiteral<T>(String literal, T value) {
    if (!source.startsWith(literal, index)) {
      throw const _JsonFailure(ContentErrorCode.parse);
    }
    index += literal.length;
    return value;
  }

  bool _consume(int code) {
    if (index < source.length && source.codeUnitAt(index) == code) {
      index += 1;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code != 0x20 && code != 0x09 && code != 0x0a && code != 0x0d) return;
      index += 1;
    }
  }

  bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
  bool _isNonZeroDigit(int code) => code >= 0x31 && code <= 0x39;
}
