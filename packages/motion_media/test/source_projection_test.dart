import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:motion_media/motion_media.dart';
import 'package:motion_media/src/canonical_release_json.dart';
import 'package:motion_media/src/release_manifest.dart';
import 'package:test/test.dart';

const _catalogSha =
    '87854b777591afc1b5c20b2a27db44bcd9a5e502453ec161f601ad5d94e9f906';
const _sourceManifestSha =
    '2c0a7630fca46508a34480ac3b0145664fa270ce6d92494e7b2aba6644d29b9c';
const _reviewRootSha =
    '08fa03b963cb26aaef1a958eb6c5f7806ce31419ae9b2eb2a60b7e23619ed571';

String _digest(List<int> bytes) => hashes.sha256.convert(bytes).toString();

void main() {
  late List<int> manifest;
  late List<int> coverage;
  late List<int> signature;
  late SourceMembershipIndex source;
  late List<int> projection;
  late SourceProjectionPin pin;
  late ReleaseTrustRoot root;

  SourceProjectionPin expectedPin(
    List<int> raw, {
    int variantCount = 2,
    int heldCount = 1,
    String appId = 'ostinato',
    String? courseSha,
  }) => SourceProjectionPin(
    appId: appId,
    projectionSha256: _digest(raw),
    sourceCatalogSha256: _catalogSha,
    sourceManifestSha256: _sourceManifestSha,
    courseSourceSha256: courseSha ?? source.courseSourceSha256,
    variantCount: variantCount,
    heldCount: heldCount,
  );

  Future<void> rejects(
    List<int> raw,
    SourceProjectionPin bound,
    String code,
  ) async {
    await expectLater(
      Future<void>(() {
        SourceProjectionDecoder.decode(raw, pin: bound);
      }),
      throwsA(
        isA<SourceProjectionError>().having(
          (error) => error.code,
          'code',
          code,
        ),
      ),
    );
  }

  setUpAll(() async {
    final fixtures = Directory('test/fixtures');
    manifest = await File(
      '${fixtures.path}/v2l_synthetic_release.json',
    ).readAsBytes();
    coverage = await File(
      '${fixtures.path}/v2l_synthetic_coverage.json',
    ).readAsBytes();
    signature = await File(
      '${fixtures.path}/v2l_synthetic_release.sig',
    ).readAsBytes();
    final catalog =
        jsonDecode(
              await File(
                '${fixtures.path}/v2l_synthetic_source_catalog.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    source = SourceMembershipIndex.fromPreverifiedCatalog(
      catalog.cast<String, Object?>(),
      'ostinato',
    );
    projection = CanonicalReleaseJson.encode(<String, Object?>{
      'schemaVersion': 1,
      'kind': 'MOTION_V2L_APP_SOURCE_PROJECTION_V1',
      'appId': 'ostinato',
      'sourceCatalogSHA256': _catalogSha,
      'sourceManifestSHA256': _sourceManifestSha,
      'courseSourceSHA256': source.courseSourceSha256,
      'rows': <List<Object?>>[
        for (final item in source.variants.entries)
          <Object?>[
            item.key,
            item.value['lessonId'],
            item.value['assetId'],
            item.value['sceneId'],
            item.value['sceneOrder'],
            item.value['variantStem'],
            item.value['lessonCanonicalSHA256'],
            item.value['productionSpecSHA256'],
            item.value['sourceCueSHA256'],
            item.value['idempotencyKey'],
            source.held.contains(item.key),
          ],
      ],
    });
    pin = expectedPin(projection);
    final key = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (index) => index),
    );
    final public = await key.extractPublicKey();
    root = ReleaseTrustRoot(
      keyId: 'synthetic-key-never-ship',
      ed25519PublicKey: public.bytes,
      assetHost: 'media.example.org',
      reviewTrustRootSha256: _reviewRootSha,
      expectedManifestSha256: _digest(manifest),
    );
  });

  test(
    'bounded app-owned bytes feed structural v2l without playback',
    () async {
      final decoded = SourceProjectionDecoder.decode(projection, pin: pin);
      expect(decoded.appId, 'ostinato');
      expect(decoded.variants.length, 2);
      expect(decoded.held.length, 1);
      expect(decoded.courseSourceSha256, source.courseSourceSha256);
      final callerManifest = List<int>.of(manifest);
      final result = await StructuralReleaseVerifier.verifyWithProjection(
        rawManifest: callerManifest,
        rawSignature: signature,
        rawCoverage: coverage,
        rawProjection: projection,
        projectionPin: pin,
        root: root,
      );
      expect(result.structural.state, 'STRUCTURAL_CRYPTO_CHECK_ONLY');
      expect(result.structural.acceptedVariants, 1);
      final entry = result.catalog.entries.single;
      final signedEntry =
          (jsonDecode(utf8.decode(manifest))
                  as Map<String, dynamic>)['entries'][0]
              as Map<String, dynamic>;
      expect(
        (entry.lessonId, entry.sceneId, entry.variantStem, entry.sceneOrder),
        (
          signedEntry['lessonId'],
          signedEntry['sceneId'],
          signedEntry['variantStem'],
          signedEntry['sceneOrder'],
        ),
      );
      for (final (actual, expected)
          in <(ReleaseFileExpectation, Map<String, dynamic>)>[
            (entry.video, signedEntry['video'] as Map<String, dynamic>),
            (
              entry.trCaption,
              signedEntry['captions']['tr'] as Map<String, dynamic>,
            ),
            (
              entry.enCaption,
              signedEntry['captions']['en'] as Map<String, dynamic>,
            ),
          ]) {
        expect(
          (actual.path, actual.bytes, actual.sha256, actual.mime),
          (
            expected['path'],
            expected['bytes'],
            expected['sha256'],
            expected['mime'],
          ),
        );
      }
      expect(() => result.catalog.entries.clear(), throwsUnsupportedError);
      callerManifest[0] ^= 1;
      expect(entry.video.sha256, signedEntry['video']['sha256']);
      final production = await ReleaseProductionGate.verifyBundled(
        appId: 'ostinato',
        readAsset: (_) async => manifest,
      );
      expect(production.mediaAvailable, isFalse);
      expect(production.code, 'NO_APPROVED_PRODUCTION_ROOT');
    },
  );

  test(
    'catalog follows pinned scene order rather than manifest hash order',
    () async {
      final alteredSource =
          jsonDecode(
                await File(
                  'test/fixtures/v2l_synthetic_source_catalog.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final scenes =
          ((alteredSource['lessons'] as List).single
                  as Map<String, dynamic>)['scenes']
              as List;
      scenes.insert(0, scenes.removeAt(1));
      (scenes.first as Map<String, dynamic>)['productionState'] =
          'PREPRODUCTION_UNGENERATED';
      final catalogSha = _digest(CanonicalReleaseJson.encode(alteredSource));
      final membership = SourceMembershipIndex.fromPreverifiedCatalog(
        alteredSource.cast<String, Object?>(),
        'ostinato',
      );
      expect(membership.held, isEmpty);
      final changedProjection = CanonicalReleaseJson.encode(<String, Object?>{
        'schemaVersion': 1,
        'kind': 'MOTION_V2L_APP_SOURCE_PROJECTION_V1',
        'appId': 'ostinato',
        'sourceCatalogSHA256': catalogSha,
        'sourceManifestSHA256': _sourceManifestSha,
        'courseSourceSHA256': membership.courseSourceSha256,
        'rows': <List<Object?>>[
          for (final item in membership.variants.entries)
            <Object?>[
              item.key,
              item.value['lessonId'],
              item.value['assetId'],
              item.value['sceneId'],
              item.value['sceneOrder'],
              item.value['variantStem'],
              item.value['lessonCanonicalSHA256'],
              item.value['productionSpecSHA256'],
              item.value['sourceCueSHA256'],
              item.value['idempotencyKey'],
              false,
            ],
        ],
      });
      final changedPin = SourceProjectionPin(
        appId: 'ostinato',
        projectionSha256: _digest(changedProjection),
        sourceCatalogSha256: catalogSha,
        sourceManifestSha256: _sourceManifestSha,
        courseSourceSha256: membership.courseSourceSha256,
        variantCount: 2,
        heldCount: 0,
      );

      final editedManifest =
          jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
      final originalEntry =
          (editedManifest['entries'] as List).single as Map<String, dynamic>;
      final firstPin = originalEntry['sourcePinSHA256'] as String;
      final secondPin = source.held.single;
      for (final field in membership.variants[firstPin]!.entries) {
        originalEntry[field.key] = field.value;
      }
      final secondEntry = Map<String, dynamic>.from(originalEntry)
        ..['sourcePinSHA256'] = secondPin;
      for (final field in membership.variants[secondPin]!.entries) {
        secondEntry[field.key] = field.value;
      }
      editedManifest['entries'] = <Map<String, dynamic>>[
        originalEntry,
        secondEntry,
      ]; // Accepted pins remain in SHA order, opposite to scene order.
      editedManifest['sourceCatalogSHA256'] = catalogSha;
      final editedCoverage =
          jsonDecode(utf8.decode(coverage)) as Map<String, dynamic>;
      editedCoverage['sourceCatalogSHA256'] = catalogSha;
      editedCoverage['acceptedSourcePins'] = <String>[firstPin, secondPin];
      editedCoverage['heldSourcePins'] = <String>[];
      final rawCoverage = CanonicalReleaseJson.encode(editedCoverage);
      editedManifest['coverageReceiptSHA256'] = _digest(rawCoverage);
      final rawManifest = CanonicalReleaseJson.encode(editedManifest);
      final key = await Ed25519().newKeyPairFromSeed(
        List<int>.generate(32, (index) => index),
      );
      final signed = await Ed25519().sign(<int>[
        ...utf8.encode('motion-media-release-v1'),
        0,
        ...rawManifest,
      ], keyPair: key);
      final changedRoot = ReleaseTrustRoot(
        keyId: root.keyId,
        ed25519PublicKey: root.ed25519PublicKey,
        assetHost: root.assetHost,
        reviewTrustRootSha256: root.reviewTrustRootSha256,
        expectedManifestSha256: _digest(rawManifest),
      );
      final result = await StructuralReleaseVerifier.verifyWithProjection(
        rawManifest: rawManifest,
        rawSignature: signed.bytes,
        rawCoverage: rawCoverage,
        rawProjection: changedProjection,
        projectionPin: changedPin,
        root: changedRoot,
      );
      expect(result.structural.acceptedVariants, 2);
      expect(
        result.catalog.entries.map((entry) => entry.sceneOrder).toList(),
        <int>[0, 1],
      );
      expect(
        result.catalog.entries.first.sceneId,
        membership.variants[secondPin]!['sceneId'],
      );
      expect(
        result.catalog.entries.last.sceneId,
        membership.variants[firstPin]!['sceneId'],
      );
      final wrongProjection = List<int>.of(changedProjection);
      wrongProjection[0] ^= 1;
      expect(
        () => StructuralReleaseVerifier.verifyWithProjection(
          rawManifest: rawManifest,
          rawSignature: signed.bytes,
          rawCoverage: rawCoverage,
          rawProjection: wrongProjection,
          projectionPin: changedPin,
          root: changedRoot,
        ),
        throwsA(
          isA<ReleaseContractError>().having(
            (error) => error.code,
            'code',
            'PROJECTION_BINARY_PIN',
          ),
        ),
      );
    },
  );

  test(
    'scene order is functional, unique, and contiguous per lesson',
    () async {
      Future<void> rejectOrder(
        void Function(List<dynamic>) change,
        String code,
      ) async {
        final value =
            jsonDecode(utf8.decode(projection)) as Map<String, dynamic>;
        final rows = value['rows'] as List<dynamic>;
        change(rows);
        final raw = CanonicalReleaseJson.encode(value);
        await rejects(raw, expectedPin(raw), code);
      }

      await rejectOrder((rows) {
        (rows[1] as List)[3] = (rows[0] as List)[3];
      }, 'PROJECTION_SCENE_ORDER_CONFLICT');
      await rejectOrder((rows) {
        (rows[1] as List)[4] = (rows[0] as List)[4];
      }, 'PROJECTION_SCENE_ORDER_DUPLICATE');
      await rejectOrder((rows) {
        (rows[1] as List)[4] = 2;
      }, 'PROJECTION_SCENE_ORDER_GAP');

      final value = jsonDecode(utf8.decode(projection)) as Map<String, dynamic>;
      final rows = value['rows'] as List<dynamic>;
      final sameSceneVariant = List<Object?>.of(
        (rows.first as List).cast<Object?>(),
      );
      sameSceneVariant[0] = _digest(utf8.encode('second-variant-pin'));
      sameSceneVariant[5] = 'second-variant';
      rows.add(sameSceneVariant);
      final raw = CanonicalReleaseJson.encode(value);
      final decoded = SourceProjectionDecoder.decode(
        raw,
        pin: expectedPin(raw, variantCount: 3),
      );
      expect(decoded.variants.length, 3);
      expect(decoded.variants[sameSceneVariant[0]]!['sceneOrder'], 0);
    },
  );

  test(
    'wrong bytes and oversized input reject before JSON interpretation',
    () async {
      final wrong = List<int>.of(projection)..[0] ^= 1;
      await rejects(wrong, pin, 'PROJECTION_BINARY_PIN');
      await rejects(
        List<int>.filled(SourceProjectionDecoder.maxBytes + 1, 0),
        pin,
        'PROJECTION_SIZE',
      );
    },
  );

  test(
    'partial rows and missing HOLD reject against app-owned counts',
    () async {
      final partial =
          jsonDecode(utf8.decode(projection)) as Map<String, dynamic>;
      (partial['rows'] as List).removeLast();
      final rawPartial = CanonicalReleaseJson.encode(partial);
      await rejects(
        rawPartial,
        expectedPin(rawPartial),
        'PROJECTION_VARIANT_COUNT',
      );
      final missingHold =
          jsonDecode(utf8.decode(projection)) as Map<String, dynamic>;
      for (final row in missingHold['rows'] as List) {
        (row as List)[10] = false;
      }
      final rawMissingHold = CanonicalReleaseJson.encode(missingHold);
      await rejects(
        rawMissingHold,
        expectedPin(rawMissingHold),
        'PROJECTION_HELD_COUNT',
      );
    },
  );

  test('app and course pin changes reject with exact schema code', () async {
    await rejects(
      projection,
      expectedPin(projection, appId: 'wrong-app'),
      'PROJECTION_SCHEMA',
    );
    await rejects(
      projection,
      expectedPin(projection, courseSha: _digest(utf8.encode('wrong-course'))),
      'PROJECTION_SCHEMA',
    );
  });

  test('signed entry disagrees with changed projection scene order', () async {
    final changed = jsonDecode(utf8.decode(projection)) as Map<String, dynamic>;
    final rows = changed['rows'] as List;
    (rows.first as List)[4] = 1;
    (rows.last as List)[4] = 0;
    final raw = CanonicalReleaseJson.encode(changed);
    await expectLater(
      StructuralReleaseVerifier.verifyWithProjection(
        rawManifest: manifest,
        rawSignature: signature,
        rawCoverage: coverage,
        rawProjection: raw,
        projectionPin: expectedPin(raw),
        root: root,
      ),
      throwsA(
        isA<ReleaseContractError>().having(
          (error) => error.code,
          'code',
          'ENTRY_SOURCE_DRIFT',
        ),
      ),
    );
  });
}
