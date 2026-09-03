import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String canonicalJsonEncode(Object? value) {
  if (value == null || value is bool || value is int) return jsonEncode(value);
  if (value is String) return jsonEncode(value);
  if (value is double || value is num) {
    throw const FormatException('Floating-point values are not canonical');
  }
  if (value is List<Object?>) {
    return '[${value.map(canonicalJsonEncode).join(',')}]';
  }
  if (value is Map<Object?, Object?>) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw const FormatException('Object keys must be strings');
      }
      keys.add(key);
    }
    keys.sort();
    final fields = <String>[];
    for (final key in keys) {
      fields.add('${jsonEncode(key)}:${canonicalJsonEncode(value[key])}');
    }
    return '{${fields.join(',')}}';
  }
  throw FormatException(
    'Unsupported canonical JSON type: ${value.runtimeType}',
  );
}

String computeCatalogDigest(Map<String, Object?> manifestBody) {
  final body = Map<String, Object?>.of(manifestBody)..remove('catalogDigest');
  return computeSha256Hex(
    Uint8List.fromList(utf8.encode(canonicalJsonEncode(body))),
  );
}

String computeSha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
