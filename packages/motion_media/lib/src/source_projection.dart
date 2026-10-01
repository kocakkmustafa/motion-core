import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;

import 'canonical_release_json.dart';

/// The app binary must own these exact pins. This generic Core contract has
/// no built-in app identity, course content, media, or reviewer authority.
final class SourceProjectionPin {
  SourceProjectionPin({
    required this.appId,
    required this.projectionSha256,
    required this.sourceCatalogSha256,
    required this.sourceManifestSha256,
    required this.courseSourceSha256,
    required this.variantCount,
    required this.heldCount,
  });

  final String appId;
  final String projectionSha256;
  final String sourceCatalogSha256;
  final String sourceManifestSha256;
  final String courseSourceSha256;
  final int variantCount;
  final int heldCount;
}

/// Bounded, canonical single-app source membership decoder.
///
/// A matching digest establishes only that bytes match an app-owned pin. It
/// does not authorize release media; the production gate is separate/closed.
final class SourceProjectionDecoder {
  SourceProjectionDecoder._();

  static const int maxBytes = 2 * 1024 * 1024;
  static const int maxVariants = 10000;
  static const String _zeroHash =
      '0000000000000000000000000000000000000000000000000000000000000000';
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static const Set<String> _topFields = <String>{
    'schemaVersion',
    'kind',
    'appId',
    'sourceCatalogSHA256',
    'sourceManifestSHA256',
    'courseSourceSHA256',
    'rows',
  };
  static const List<String> _identityFields = <String>[
    'lessonId',
    'assetId',
    'sceneId',
    'sceneOrder',
    'variantStem',
    'lessonCanonicalSHA256',
    'productionSpecSHA256',
    'sourceCueSHA256',
    'idempotencyKey',
  ];

  static SourceProjectionData decode(
    List<int> untrustedRaw, {
    required SourceProjectionPin pin,
  }) {
    // Cap before copying, hashing, decoding, or allocating parsed objects.
    _require(
      untrustedRaw.isNotEmpty && untrustedRaw.length <= maxBytes,
      'PROJECTION_SIZE',
    );
    _require(pin.appId.isNotEmpty, 'PROJECTION_APP_ID');
    _sha(pin.projectionSha256, 'PROJECTION_EXPECTED_SHA');
    _sha(pin.sourceCatalogSha256, 'PROJECTION_CATALOG_SHA');
    _sha(pin.sourceManifestSha256, 'PROJECTION_MANIFEST_SHA');
    _sha(pin.courseSourceSha256, 'PROJECTION_COURSE_SHA');
    _require(
      pin.variantCount > 0 &&
          pin.variantCount <= maxVariants &&
          pin.heldCount >= 0 &&
          pin.heldCount <= pin.variantCount,
      'PROJECTION_EXPECTED_COUNTS',
    );
    final raw = Uint8List.fromList(untrustedRaw);
    _require(_digest(raw) == pin.projectionSha256, 'PROJECTION_BINARY_PIN');
    final Map<String, Object?> value;
    try {
      value = CanonicalReleaseJson.parseObject(
        raw,
        maxBytes: maxBytes,
        code: 'SOURCE_PROJECTION',
      );
    } on CanonicalReleaseJsonError catch (error) {
      throw SourceProjectionError(error.code);
    }
    _require(
      _sameSet(value.keys.toSet(), _topFields) &&
          value['schemaVersion'] is int &&
          value['schemaVersion'] == 1 &&
          value['kind'] == 'MOTION_V2L_APP_SOURCE_PROJECTION_V1' &&
          value['appId'] == pin.appId &&
          value['sourceCatalogSHA256'] == pin.sourceCatalogSha256 &&
          value['sourceManifestSHA256'] == pin.sourceManifestSha256 &&
          value['courseSourceSHA256'] == pin.courseSourceSha256,
      'PROJECTION_SCHEMA',
    );
    final rows = _list(value['rows'], 'PROJECTION_ROWS');
    _require(rows.length == pin.variantCount, 'PROJECTION_VARIANT_COUNT');
    final variants = <String, Map<String, Object?>>{};
    final held = <String>{};
    final orderByScene = <(String, String), int>{};
    final sceneByOrder = <(String, int), String>{};
    final ordersByLesson = <String, Set<int>>{};
    for (final rawRow in rows) {
      final row = _list(rawRow, 'PROJECTION_ROW');
      _require(row.length == 11, 'PROJECTION_ROW');
      final sourcePin = _sha(row[0], 'PROJECTION_SOURCE_PIN');
      _require(!variants.containsKey(sourcePin), 'PROJECTION_PIN_DUPLICATE');
      final rawSceneOrder = row[4];
      final heldFlag = row[10];
      _require(
        rawSceneOrder is int && rawSceneOrder >= 0 && heldFlag is bool,
        'PROJECTION_ROW',
      );
      final sceneOrder = rawSceneOrder as int;
      final identity = Map<String, Object?>.unmodifiable({
        for (var i = 0; i < _identityFields.length; i++)
          _identityFields[i]: switch (i) {
            3 => sceneOrder,
            5 || 6 || 7 => _sha(row[i + 1], 'PROJECTION_IDENTITY_SHA'),
            _ => _text(row[i + 1]),
          },
      });
      _require(
        identity['idempotencyKey'] ==
            'motion-media-v1:${identity['productionSpecSHA256']}',
        'PROJECTION_IDEMPOTENCY',
      );
      final lessonId = identity['lessonId']! as String;
      final sceneId = identity['sceneId']! as String;
      final sceneKey = (lessonId, sceneId);
      final previousOrder = orderByScene[sceneKey];
      _require(
        previousOrder == null || previousOrder == sceneOrder,
        'PROJECTION_SCENE_ORDER_CONFLICT',
      );
      orderByScene[sceneKey] = sceneOrder;
      final orderKey = (lessonId, sceneOrder);
      final previousScene = sceneByOrder[orderKey];
      _require(
        previousScene == null || previousScene == sceneId,
        'PROJECTION_SCENE_ORDER_DUPLICATE',
      );
      sceneByOrder[orderKey] = sceneId;
      ordersByLesson.putIfAbsent(lessonId, () => <int>{}).add(sceneOrder);
      variants[sourcePin] = identity;
      if (heldFlag == true) held.add(sourcePin);
    }
    for (final orders in ordersByLesson.values) {
      for (var order = 0; order < orders.length; order++) {
        _require(orders.contains(order), 'PROJECTION_SCENE_ORDER_GAP');
      }
    }
    _require(held.length == pin.heldCount, 'PROJECTION_HELD_COUNT');
    return SourceProjectionData._(
      pin.appId,
      pin.sourceCatalogSha256,
      pin.sourceManifestSha256,
      pin.courseSourceSha256,
      Map<String, Map<String, Object?>>.unmodifiable(variants),
      Set<String>.unmodifiable(held),
    );
  }

  static List<Object?> _list(Object? value, String code) {
    _require(value is List, code);
    return (value! as List).cast<Object?>();
  }

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static String _sha(Object? value, String code) {
    _require(
      value is String && _hex64.hasMatch(value) && value != _zeroHash,
      code,
    );
    return value! as String;
  }

  static String _text(Object? value) {
    _require(value is String && value.isNotEmpty, 'PROJECTION_TEXT');
    return value! as String;
  }

  static String _digest(List<int> bytes) =>
      hashes.sha256.convert(bytes).toString();

  static void _require(bool condition, String code) {
    if (!condition) throw SourceProjectionError(code);
  }
}

final class SourceProjectionData {
  const SourceProjectionData._(
    this.appId,
    this.sourceCatalogSha256,
    this.sourceManifestSha256,
    this.courseSourceSha256,
    this.variants,
    this.held,
  );

  final String appId;
  final String sourceCatalogSha256;
  final String sourceManifestSha256;
  final String courseSourceSha256;
  final Map<String, Map<String, Object?>> variants;
  final Set<String> held;
}

final class SourceProjectionError implements Exception {
  const SourceProjectionError(this.code);

  final String code;

  @override
  String toString() => 'SourceProjectionError: $code';
}
