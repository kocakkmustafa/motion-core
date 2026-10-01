import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:motion_media/motion_media.dart';
import 'package:test/test.dart';

void main() {
  test('public barrel does not expose the preproduction cache', () {
    final barrel = File('lib/motion_media.dart').readAsStringSync();
    expect(barrel, isNot(contains("export 'src/verified_media_cache.dart'")));
  });

  test(
    'public source API verifies pinned identity without authorizing media',
    () async {
      final sourcePin = 'a'.padLeft(64, 'a');
      final catalogSha = 'b'.padLeft(64, 'b');
      final manifestSha = 'c'.padLeft(64, 'c');
      final courseSha = 'd'.padLeft(64, 'd');
      final lessonSha = 'e'.padLeft(64, 'e');
      final specSha = 'f'.padLeft(64, 'f');
      final cueSha = '1'.padLeft(64, '1');
      // Sorted keys and compact JSON match the canonical wire format.
      final raw = utf8.encode(
        jsonEncode(<String, Object?>{
          'appId': 'synthetic-app',
          'courseSourceSHA256': courseSha,
          'kind': 'MOTION_V2L_APP_SOURCE_PROJECTION_V1',
          'rows': <List<Object?>>[
            <Object?>[
              sourcePin,
              'synthetic-lesson',
              'synthetic-asset',
              'synthetic-scene',
              0,
              'synthetic-variant',
              lessonSha,
              specSha,
              cueSha,
              'motion-media-v1:$specSha',
              false,
            ],
          ],
          'schemaVersion': 1,
          'sourceCatalogSHA256': catalogSha,
          'sourceManifestSHA256': manifestSha,
        }),
      );
      final pin = SourceProjectionPin(
        appId: 'synthetic-app',
        projectionSha256: hashes.sha256.convert(raw).toString(),
        sourceCatalogSha256: catalogSha,
        sourceManifestSha256: manifestSha,
        courseSourceSha256: courseSha,
        variantCount: 1,
        heldCount: 0,
      );

      final SourceProjectionData source = SourceProjectionDecoder.decode(
        raw,
        pin: pin,
      );
      expect(source.appId, 'synthetic-app');
      expect(source.variants.keys, contains(sourcePin));
      expect(source.variants[sourcePin]!['sceneOrder'], 0);
      expect(source.held, isEmpty);

      final changed = List<int>.of(raw)..[0] = 0x20;
      expect(
        () => SourceProjectionDecoder.decode(changed, pin: pin),
        throwsA(
          isA<SourceProjectionError>().having(
            (error) => error.code,
            'code',
            'PROJECTION_BINARY_PIN',
          ),
        ),
      );

      var assetReads = 0;
      final decision = await ReleaseProductionGate.verifyBundled(
        appId: 'synthetic-app',
        readAsset: (_) async {
          assetReads++;
          return raw;
        },
      );
      expect(decision.mediaAvailable, isFalse);
      expect(decision.code, 'NO_APPROVED_PRODUCTION_ROOT');
      expect(assetReads, 0);
    },
  );
}
