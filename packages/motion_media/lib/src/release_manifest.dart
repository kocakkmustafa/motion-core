import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

import 'canonical_release_json.dart';
import 'source_projection.dart';

/// Internal v2l structural contract. A successful result is not permission
/// to display media: production roots and reviewer attestations are closed.
final class StructuralReleaseVerifier {
  StructuralReleaseVerifier._();

  static const int maxManifestBytes = 4 * 1024 * 1024;
  static const int maxCoverageBytes = 2 * 1024 * 1024;
  static const int maxVideoBytes = 64 * 1024 * 1024;
  static const int maxVttBytes = 1024 * 1024;
  static final List<int> _domain = <int>[
    ...utf8.encode('motion-media-release-v1'),
    0,
  ];
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
  static const String _zeroHash =
      '0000000000000000000000000000000000000000000000000000000000000000';
  static final RegExp _releaseId = RegExp(r'^[a-z0-9][a-z0-9.-]{0,63}$');
  static final RegExp _dnsLabel = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );
  static const Set<String> _topFields = <String>{
    'schemaVersion',
    'kind',
    'appId',
    'sourceManifestSHA256',
    'sourceCatalogSHA256',
    'courseSourceSHA256',
    'reviewTrustRootSHA256',
    'releaseId',
    'assetHost',
    'keyId',
    'distribution',
    'entries',
    'coverageReceiptSHA256',
  };
  static const Set<String> _entryFields = <String>{
    'lessonId',
    'assetId',
    'sceneId',
    'sceneOrder',
    'variantStem',
    'sourcePinSHA256',
    'lessonCanonicalSHA256',
    'productionSpecSHA256',
    'sourceCueSHA256',
    'idempotencyKey',
    'durationMs',
    'acceptanceReceiptSHA256',
    'captionReviewReceiptSHA256',
    'rightsReceiptSHA256',
    'remoteInventoryReceiptSHA256',
    'candidateNativeQaReceiptSHA256',
    'technicalProfileReceiptSHA256',
    'video',
    'captions',
  };
  static const List<String> _receiptFields = <String>[
    'acceptanceReceiptSHA256',
    'captionReviewReceiptSHA256',
    'rightsReceiptSHA256',
    'remoteInventoryReceiptSHA256',
    'candidateNativeQaReceiptSHA256',
    'technicalProfileReceiptSHA256',
  ];
  static const Set<String> _fileFields = <String>{
    'path',
    'bytes',
    'sha256',
    'mime',
  };
  static const Set<String> _coverageFields = <String>{
    'schemaVersion',
    'appId',
    'sourceCatalogSHA256',
    'acceptedSourcePins',
    'openSourcePins',
    'heldSourcePins',
  };

  static Future<StructuralReleaseResult> verify({
    required List<int> rawManifest,
    required List<int> rawSignature,
    required List<int> rawCoverage,
    required SourceMembershipIndex source,
    required String sourceCatalogSha256,
    required String sourceManifestSha256,
    required ReleaseTrustRoot root,
  }) => _verify(
    rawManifest: rawManifest,
    rawSignature: rawSignature,
    rawCoverage: rawCoverage,
    source: source,
    sourceCatalogSha256: sourceCatalogSha256,
    sourceManifestSha256: sourceManifestSha256,
    root: root,
  ).then((validated) => validated.structural);

  static Future<_ValidatedReleaseData> _verify({
    required List<int> rawManifest,
    required List<int> rawSignature,
    required List<int> rawCoverage,
    required SourceMembershipIndex source,
    required String sourceCatalogSha256,
    required String sourceManifestSha256,
    required ReleaseTrustRoot root,
  }) async {
    _require(
      rawManifest.isNotEmpty && rawManifest.length <= maxManifestBytes,
      'MANIFEST_SIZE',
    );
    _require(
      rawCoverage.isNotEmpty && rawCoverage.length <= maxCoverageBytes,
      'COVERAGE_SIZE',
    );
    _require(rawSignature.length == 64, 'SIGNATURE_FORMAT');
    // One bounded snapshot per caller-owned input before the signature await.
    final manifestBytes = List<int>.unmodifiable(rawManifest);
    final coverageBytes = List<int>.unmodifiable(rawCoverage);
    final signatureBytes = List<int>.unmodifiable(rawSignature);
    _shaHex(root.expectedManifestSha256, 'EXPECTED_MANIFEST_SHA_FORMAT');
    _require(
      _digest(manifestBytes) == root.expectedManifestSha256,
      'MANIFEST_BINARY_PIN',
    );
    final Map<String, Object?> manifest;
    final Map<String, Object?> coverage;
    try {
      manifest = CanonicalReleaseJson.parseObject(
        manifestBytes,
        maxBytes: maxManifestBytes,
        code: 'MANIFEST',
      );
      coverage = CanonicalReleaseJson.parseObject(
        coverageBytes,
        maxBytes: maxCoverageBytes,
        code: 'COVERAGE',
      );
    } on CanonicalReleaseJsonError catch (error) {
      throw ReleaseContractError(error.code);
    }
    _require(root.ed25519PublicKey.length == 32, 'PUBLIC_KEY_FORMAT');
    bool validSignature;
    try {
      validSignature = await Ed25519().verify(
        <int>[..._domain, ...manifestBytes],
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(
            root.ed25519PublicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      throw const ReleaseContractError('SIGNATURE_INVALID');
    }
    _require(validSignature, 'SIGNATURE_INVALID');
    _require(
      _digest(coverageBytes) == manifest['coverageReceiptSHA256'],
      'COVERAGE_DIGEST',
    );
    return _validate(
      manifest,
      coverage,
      source: source,
      sourceCatalogSha256: sourceCatalogSha256,
      sourceManifestSha256: sourceManifestSha256,
      root: root,
    );
  }

  /// Structural test using a bounded projection whose exact bytes and course
  /// source pin are owned by the calling app binary. No media authority.
  static Future<PinnedProjectionReleaseResult> verifyWithProjection({
    required List<int> rawManifest,
    required List<int> rawSignature,
    required List<int> rawCoverage,
    required List<int> rawProjection,
    required SourceProjectionPin projectionPin,
    required ReleaseTrustRoot root,
  }) {
    final SourceProjectionData projection;
    try {
      projection = SourceProjectionDecoder.decode(
        rawProjection,
        pin: projectionPin,
      );
    } on SourceProjectionError catch (error) {
      throw ReleaseContractError(error.code);
    }
    return _verify(
      rawManifest: rawManifest,
      rawSignature: rawSignature,
      rawCoverage: rawCoverage,
      source: SourceMembershipIndex._(
        projection.appId,
        projection.courseSourceSha256,
        projection.variants,
        projection.held,
      ),
      sourceCatalogSha256: projection.sourceCatalogSha256,
      sourceManifestSha256: projection.sourceManifestSha256,
      root: root,
    ).then(
      (validated) => PinnedProjectionReleaseResult._(
        validated.structural,
        VerifiedReleaseCatalog._fromValidated(validated.entries),
        validated.origin,
      ),
    );
  }

  static _ValidatedReleaseData _validate(
    Map<String, Object?> manifest,
    Map<String, Object?> coverage, {
    required SourceMembershipIndex source,
    required String sourceCatalogSha256,
    required String sourceManifestSha256,
    required ReleaseTrustRoot root,
  }) {
    _shaHex(sourceCatalogSha256, 'SOURCE_CATALOG_SHA_FORMAT');
    _shaHex(sourceManifestSha256, 'SOURCE_MANIFEST_SHA_FORMAT');
    _shaHex(root.reviewTrustRootSha256, 'REVIEW_ROOT_SHA_FORMAT');
    _require(_releaseId.hasMatch(root.keyId), 'TRUST_KEY_ID');
    _require(
      _exactFields(manifest, _topFields) &&
          manifest['schemaVersion'] is int &&
          manifest['schemaVersion'] == 1 &&
          manifest['kind'] == 'motion_media_release' &&
          manifest['distribution'] == 'public_free',
      'MANIFEST_SCHEMA',
    );
    final appValue = manifest['appId'];
    _require(appValue is String && appValue == source.appId, 'APP_ID');
    final appId = appValue as String;
    _require(
      manifest['sourceManifestSHA256'] == sourceManifestSha256 &&
          manifest['sourceCatalogSHA256'] == sourceCatalogSha256,
      'SOURCE_VERSION',
    );
    _require(
      manifest['courseSourceSHA256'] == source.courseSourceSha256,
      'COURSE_SHA',
    );
    _require(
      manifest['reviewTrustRootSHA256'] == root.reviewTrustRootSha256 &&
          manifest['keyId'] == root.keyId,
      'TRUST_ROOT',
    );
    _require(
      _validHost(root.assetHost) && manifest['assetHost'] == root.assetHost,
      'ASSET_HOST',
    );
    _require(
      manifest['releaseId'] is String &&
          _releaseId.hasMatch(manifest['releaseId']! as String),
      'RELEASE_ID',
    );
    _shaHex(manifest['coverageReceiptSHA256'], 'COVERAGE_SHA');
    _require(
      _exactFields(coverage, _coverageFields) &&
          coverage['schemaVersion'] is int &&
          coverage['schemaVersion'] == 1 &&
          coverage['appId'] == appId &&
          coverage['sourceCatalogSHA256'] == sourceCatalogSha256,
      'COVERAGE_SCHEMA',
    );
    final accepted = _sortedUniqueHashes(
      coverage['acceptedSourcePins'],
      'COVERAGE_ACCEPTED',
    );
    final opened = _sortedUniqueHashes(
      coverage['openSourcePins'],
      'COVERAGE_OPEN',
    );
    final held = _sortedUniqueHashes(
      coverage['heldSourcePins'],
      'COVERAGE_HELD',
    );
    final acceptedSet = accepted.toSet();
    final openSet = opened.toSet();
    final heldSet = held.toSet();
    _require(
      _sameSet(heldSet, source.held) &&
          acceptedSet.intersection(openSet).isEmpty &&
          acceptedSet.intersection(heldSet).isEmpty &&
          openSet.intersection(heldSet).isEmpty &&
          _sameSet(<String>{
            ...acceptedSet,
            ...openSet,
            ...heldSet,
          }, source.variants.keys.toSet()),
      'COVERAGE_PARTITION',
    );

    final entries = _list(manifest['entries'], 'ENTRY_COUNT');
    _require(
      entries.isNotEmpty && entries.length <= source.variants.length,
      'ENTRY_COUNT',
    );
    final entryPins = <String>[];
    final entryKeys = <(String, String, String)>{};
    final validatedEntries = <Map<String, Object?>>[];
    for (final rawEntry in entries) {
      final entry = _map(rawEntry, 'ENTRY_SCHEMA');
      _require(_exactFields(entry, _entryFields), 'ENTRY_SCHEMA');
      final pin = _shaHex(entry['sourcePinSHA256'], 'ENTRY_SOURCE_PIN');
      final expected = source.variants[pin];
      _require(expected != null, 'ENTRY_NOT_IN_SOURCE');
      _require(!source.held.contains(pin), 'ENTRY_HELD_SOURCE');
      _require(entry['sceneOrder'] is int, 'SCENE_ORDER_TYPE');
      for (final field in expected!.keys) {
        _require(entry[field] == expected[field], 'ENTRY_SOURCE_DRIFT');
      }
      final duration = entry['durationMs'];
      _require(
        duration is int && duration >= 1000 && duration <= 120000,
        'DURATION',
      );
      final receipts = <String>{};
      for (final field in _receiptFields) {
        receipts.add(_shaHex(entry[field], 'RECEIPT_SHA'));
      }
      _require(receipts.length == _receiptFields.length, 'RECEIPT_REUSE');
      final video = _map(entry['video'], 'FILE_SCHEMA');
      _file(video, appId, 'mp4', 'video/mp4', maxVideoBytes);
      final captions = _map(entry['captions'], 'CAPTION_LOCALES');
      _require(_exactFields(captions, <String>{'tr', 'en'}), 'CAPTION_LOCALES');
      final tr = _map(captions['tr'], 'FILE_SCHEMA');
      final en = _map(captions['en'], 'FILE_SCHEMA');
      _file(tr, appId, 'vtt', 'text/vtt', maxVttBytes);
      _file(en, appId, 'vtt', 'text/vtt', maxVttBytes);
      _require(
        <Object?>{video['sha256'], tr['sha256'], en['sha256']}.length == 3,
        'FILE_HASH_REUSE',
      );
      entryPins.add(pin);
      entryKeys.add((
        entry['lessonId']! as String,
        entry['sceneId']! as String,
        entry['variantStem']! as String,
      ));
      validatedEntries.add(entry);
    }
    _require(_sameList(entryPins, accepted), 'ENTRY_COVERAGE');
    _require(entryKeys.length == entries.length, 'ENTRY_KEY_DUPLICATE');
    final sceneVariants = <(String, String), Set<String>>{};
    for (final sourceEntry in source.variants.entries) {
      final scene = (
        sourceEntry.value['lessonId']! as String,
        sourceEntry.value['sceneId']! as String,
      );
      sceneVariants.putIfAbsent(scene, () => <String>{}).add(sourceEntry.key);
    }
    for (final pins in sceneVariants.values) {
      _require(
        pins.intersection(acceptedSet).isEmpty || acceptedSet.containsAll(pins),
        'SCENE_VARIANTS_PARTIAL',
      );
    }
    return _ValidatedReleaseData(
      StructuralReleaseResult(
        appId: appId,
        acceptedVariants: entries.length,
        openVariants: opened.length,
        heldVariants: held.length,
      ),
      validatedEntries,
      VerifiedReleaseOrigin._(
        appId: appId,
        assetHost: root.assetHost,
        releaseId: manifest['releaseId']! as String,
        manifestSha256: root.expectedManifestSha256,
      ),
    );
  }

  static void _file(
    Map<String, Object?> record,
    String appId,
    String extension,
    String mime,
    int cap,
  ) {
    _require(_exactFields(record, _fileFields), 'FILE_SCHEMA');
    final digest = _shaHex(record['sha256'], 'FILE_SHA');
    final bytes = record['bytes'];
    _require(bytes is int && bytes > 0 && bytes <= cap, 'FILE_BYTES');
    _require(record['mime'] == mime, 'FILE_MIME');
    _require(
      record['path'] == 'motion-media/v1/$appId/$digest.$extension',
      'FILE_PATH',
    );
  }

  static List<String> _sortedUniqueHashes(Object? value, String code) {
    final list = _list(value, '${code}_LIST');
    final hashes = <String>[];
    for (final item in list) {
      hashes.add(_shaHex(item, '${code}_HASH'));
    }
    final sorted = hashes.toSet().toList()..sort();
    _require(_sameList(hashes, sorted), '${code}_ORDER');
    return hashes;
  }

  static bool _validHost(String value) {
    if (value.length > 253 ||
        value != value.toLowerCase() ||
        value == 'localhost' ||
        value.contains(':') ||
        value.contains('*') ||
        value.contains('_') ||
        InternetAddress.tryParse(value) != null) {
      return false;
    }
    final labels = value.split('.');
    return labels.length >= 2 && labels.every(_dnsLabel.hasMatch);
  }

  static String _shaHex(Object? value, String code) {
    _require(
      value is String && _hex64.hasMatch(value) && value != _zeroHash,
      code,
    );
    return value! as String;
  }

  static String _digest(List<int> bytes) =>
      hashes.sha256.convert(bytes).toString();

  static bool _exactFields(Map<String, Object?> value, Set<String> fields) =>
      _sameSet(value.keys.toSet(), fields);

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Map<String, Object?> _map(Object? value, String code) {
    _require(value is Map<String, dynamic>, code);
    return (value! as Map<String, dynamic>).cast<String, Object?>();
  }

  static List<Object?> _list(Object? value, String code) {
    _require(value is List, code);
    return (value! as List).cast<Object?>();
  }

  static void _require(bool condition, String code) {
    if (!condition) throw ReleaseContractError(code);
  }
}

final class ReleaseTrustRoot {
  ReleaseTrustRoot({
    required this.keyId,
    required List<int> ed25519PublicKey,
    required this.assetHost,
    required this.reviewTrustRootSha256,
    required this.expectedManifestSha256,
  }) : ed25519PublicKey = List<int>.unmodifiable(ed25519PublicKey);

  final String keyId;
  final List<int> ed25519PublicKey;
  final String assetHost;
  final String reviewTrustRootSha256;
  final String expectedManifestSha256;
}

/// A caller must derive this from an independently checked and binary-pinned
/// v2k source catalog. Construction alone does not confer media authority.
final class SourceMembershipIndex {
  SourceMembershipIndex._(
    this.appId,
    this.courseSourceSha256,
    this.variants,
    this.held,
  );

  final String appId;
  final String courseSourceSha256;
  final Map<String, Map<String, Object?>> variants;
  final Set<String> held;

  static SourceMembershipIndex fromPreverifiedCatalog(
    Map<String, Object?> catalog,
    String appId,
  ) {
    StructuralReleaseVerifier._require(appId.isNotEmpty, 'APP_ID');
    final lessons = StructuralReleaseVerifier._list(
      catalog['lessons'],
      'SOURCE_CATALOG_SCHEMA',
    );
    final pins = StructuralReleaseVerifier._map(
      catalog['courseSourcePins'],
      'SOURCE_CATALOG_SCHEMA',
    );
    StructuralReleaseVerifier._require(pins.containsKey(appId), 'APP_ID');
    final appPin = StructuralReleaseVerifier._map(
      pins[appId],
      'SOURCE_APP_MISSING',
    );
    final courseSha = StructuralReleaseVerifier._shaHex(
      appPin['sha256'],
      'SOURCE_COURSE_SHA',
    );
    final index = <String, Map<String, Object?>>{};
    final held = <String>{};
    for (final rawLesson in lessons) {
      final lesson = StructuralReleaseVerifier._map(
        rawLesson,
        'SOURCE_CATALOG_SCHEMA',
      );
      if (lesson['app'] != appId) continue;
      StructuralReleaseVerifier._require(
        lesson['courseSourceSHA256'] == courseSha,
        'SOURCE_COURSE_DRIFT',
      );
      final scenes = StructuralReleaseVerifier._list(
        lesson['scenes'],
        'SOURCE_SCENES',
      );
      for (var order = 0; order < scenes.length; order++) {
        final scene = StructuralReleaseVerifier._map(
          scenes[order],
          'SOURCE_SCENE',
        );
        final variants = StructuralReleaseVerifier._list(
          scene['variants'],
          'SOURCE_VARIANTS',
        );
        for (final rawVariant in variants) {
          final variant = StructuralReleaseVerifier._map(
            rawVariant,
            'SOURCE_VARIANT',
          );
          final pin = StructuralReleaseVerifier._shaHex(
            variant['sourcePinSHA256'],
            'SOURCE_PIN_FORMAT',
          );
          StructuralReleaseVerifier._require(
            !index.containsKey(pin),
            'SOURCE_PIN_DUPLICATE',
          );
          index[pin] = Map<String, Object?>.unmodifiable(<String, Object?>{
            'lessonId': _text(lesson['lessonId']),
            'assetId': _text(lesson['assetId']),
            'sceneId': _text(scene['sceneId']),
            'sceneOrder': order,
            'variantStem': _text(variant['stem']),
            'lessonCanonicalSHA256': _text(lesson['lessonCanonicalSHA256']),
            'productionSpecSHA256': _text(scene['productionSpecSHA256']),
            'sourceCueSHA256': _text(scene['sourceCueSHA256']),
            'idempotencyKey': _text(scene['idempotencyKey']),
          });
          if (lesson['membershipStatus'] != 'SOURCE_PINNED_TEST_ONLY' ||
              scene['productionState'] != 'PREPRODUCTION_UNGENERATED') {
            held.add(pin);
          }
        }
      }
    }
    StructuralReleaseVerifier._require(index.isNotEmpty, 'SOURCE_APP_EMPTY');
    return SourceMembershipIndex._(
      appId,
      courseSha,
      Map<String, Map<String, Object?>>.unmodifiable(index),
      Set<String>.unmodifiable(held),
    );
  }

  static String _text(Object? value) {
    StructuralReleaseVerifier._require(value is String, 'SOURCE_FIELD');
    return value! as String;
  }
}

final class StructuralReleaseResult {
  const StructuralReleaseResult({
    required this.appId,
    required this.acceptedVariants,
    required this.openVariants,
    required this.heldVariants,
  });

  String get state => 'STRUCTURAL_CRYPTO_CHECK_ONLY';
  final String appId;
  final int acceptedVariants;
  final int openVariants;
  final int heldVariants;
}

/// Only this app-pinned projection path can carry signed file expectations.
/// It is still structural evidence, never playback or release permission.
final class PinnedProjectionReleaseResult {
  const PinnedProjectionReleaseResult._(
    this.structural,
    this.catalog,
    this.origin,
  );

  final StructuralReleaseResult structural;
  final VerifiedReleaseCatalog catalog;
  final VerifiedReleaseOrigin origin;
}

/// Exact origin copied from the signed manifest and caller-pinned trust root.
/// This is structural metadata, not a production release grant.
final class VerifiedReleaseOrigin {
  const VerifiedReleaseOrigin._({
    required this.appId,
    required this.assetHost,
    required this.releaseId,
    required this.manifestSha256,
  });

  final String appId;
  final String assetHost;
  final String releaseId;
  final String manifestSha256;
}

final class _ValidatedReleaseData {
  const _ValidatedReleaseData(this.structural, this.entries, this.origin);

  final StructuralReleaseResult structural;
  final List<Map<String, Object?>> entries;
  final VerifiedReleaseOrigin origin;
}

/// An immutable view of structurally checked manifest entries.
///
/// File bytes have not been fetched or checked here. This internal type is not
/// exported by motion_media.dart and never opens the production gate. Entries
/// are grouped by lesson ID and ordered within a lesson by sceneOrder; the app
/// owns the course's overall lesson order.
final class VerifiedReleaseCatalog {
  VerifiedReleaseCatalog._fromValidated(List<Map<String, Object?>> rows)
    : entries = List<VerifiedReleaseEntry>.unmodifiable(
        <VerifiedReleaseEntry>[
          for (final row in rows) VerifiedReleaseEntry._fromValidated(row),
        ]..sort(VerifiedReleaseEntry._compareWithinLesson),
      );

  final List<VerifiedReleaseEntry> entries;
}

final class VerifiedReleaseEntry {
  VerifiedReleaseEntry._fromValidated(Map<String, Object?> row)
    : lessonId = row['lessonId']! as String,
      sceneId = row['sceneId']! as String,
      sceneOrder = row['sceneOrder']! as int,
      variantStem = row['variantStem']! as String,
      sourcePinSha256 = row['sourcePinSHA256']! as String,
      durationMs = row['durationMs']! as int,
      video = ReleaseFileExpectation._fromValidated(
        StructuralReleaseVerifier._map(row['video'], 'FILE_SCHEMA'),
      ),
      trCaption = ReleaseFileExpectation._fromValidated(
        StructuralReleaseVerifier._map(
          StructuralReleaseVerifier._map(
            row['captions'],
            'CAPTION_LOCALES',
          )['tr'],
          'FILE_SCHEMA',
        ),
      ),
      enCaption = ReleaseFileExpectation._fromValidated(
        StructuralReleaseVerifier._map(
          StructuralReleaseVerifier._map(
            row['captions'],
            'CAPTION_LOCALES',
          )['en'],
          'FILE_SCHEMA',
        ),
      );

  final String lessonId;
  final String sceneId;
  final int sceneOrder;
  final String variantStem;
  final String sourcePinSha256;
  final int durationMs;
  final ReleaseFileExpectation video;
  final ReleaseFileExpectation trCaption;
  final ReleaseFileExpectation enCaption;

  static int _compareWithinLesson(
    VerifiedReleaseEntry a,
    VerifiedReleaseEntry b,
  ) {
    final lesson = a.lessonId.compareTo(b.lessonId);
    if (lesson != 0) return lesson;
    final order = a.sceneOrder.compareTo(b.sceneOrder);
    if (order != 0) return order;
    final scene = a.sceneId.compareTo(b.sceneId);
    if (scene != 0) return scene;
    return a.variantStem.compareTo(b.variantStem);
  }
}

/// Exact expected metadata from a signed entry, not verified local file bytes.
final class ReleaseFileExpectation {
  ReleaseFileExpectation._fromValidated(Map<String, Object?> row)
    : path = row['path']! as String,
      bytes = row['bytes']! as int,
      sha256 = row['sha256']! as String,
      mime = row['mime']! as String;

  final String path;
  final int bytes;
  final String sha256;
  final String mime;
}

final class ReleaseContractError implements Exception {
  const ReleaseContractError(this.code);

  final String code;

  @override
  String toString() => 'ReleaseContractError: $code';
}
