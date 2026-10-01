import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:motion_media/motion_media.dart';
import 'package:motion_media/src/canonical_release_json.dart';
import 'package:motion_media/src/release_manifest.dart';
import 'package:test/test.dart';

const _catalogSha =
    '87854b777591afc1b5c20b2a27db44bcd9a5e502453ec161f601ad5d94e9f906';
const _sourceManifestSha =
    '2c0a7630fca46508a34480ac3b0145664fa270ce6d92494e7b2aba6644d29b9c';
const _manifestSha =
    'ff187fab19f4718aaced3c09962f0d726dc5082c4a71e23020c6286162afe412';
const _coverageSha =
    'e8afb02d418f82ce11092c60a88e60c03b2032550e5fef5210e99e4877af27d8';
const _publicKeyHex =
    '03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8';
const _signatureHex =
    '1084ccae13aadeeae37a1f5e79fde072852f6a0eae8c64a54bc06dd3402a54ccab273440639b3c9f87fbc418be5ddd9cbe3ab20401e995edf1ad10a029271f05';
const _reviewRootSha =
    '08fa03b963cb26aaef1a958eb6c5f7806ce31419ae9b2eb2a60b7e23619ed571';

List<int> _hex(String value) => <int>[
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

String _digest(List<int> bytes) => sha256.convert(bytes).toString();

ReleaseTrustRoot _root(String manifestSha) => ReleaseTrustRoot(
  keyId: 'synthetic-key-never-ship',
  ed25519PublicKey: _hex(_publicKeyHex),
  assetHost: 'media.example.org',
  reviewTrustRootSha256: _reviewRootSha,
  expectedManifestSha256: manifestSha,
);

Future<void> _reject(Future<Object?> future, String code) async {
  await expectLater(
    future,
    throwsA(
      isA<ReleaseContractError>().having((error) => error.code, 'code', code),
    ),
  );
}

void main() {
  late List<int> manifest;
  late List<int> coverage;
  late List<int> signature;
  late List<int> sourceCatalogBytes;
  late SourceMembershipIndex source;
  late KeyPair testKeyPair;

  setUpAll(() async {
    final dir = Directory('test/fixtures');
    manifest = await File(
      '${dir.path}/v2l_synthetic_release.json',
    ).readAsBytes();
    coverage = await File(
      '${dir.path}/v2l_synthetic_coverage.json',
    ).readAsBytes();
    signature = await File(
      '${dir.path}/v2l_synthetic_release.sig',
    ).readAsBytes();
    sourceCatalogBytes = await File(
      '${dir.path}/v2l_synthetic_source_catalog.json',
    ).readAsBytes();
    source = SourceMembershipIndex.fromPreverifiedCatalog(
      (jsonDecode(utf8.decode(sourceCatalogBytes)) as Map<String, dynamic>)
          .cast<String, Object?>(),
      'ostinato',
    );
    testKeyPair = await Ed25519().newKeyPairFromSeed(
      List<int>.generate(32, (index) => index),
    );
  });

  Future<StructuralReleaseResult> verify({
    List<int>? rawManifest,
    List<int>? rawCoverage,
    List<int>? rawSignature,
    String? expectedManifestSha,
    SourceMembershipIndex? membership,
  }) => StructuralReleaseVerifier.verify(
    rawManifest: rawManifest ?? manifest,
    rawSignature: rawSignature ?? signature,
    rawCoverage: rawCoverage ?? coverage,
    source: membership ?? source,
    sourceCatalogSha256: _catalogSha,
    sourceManifestSha256: _sourceManifestSha,
    root: _root(expectedManifestSha ?? _manifestSha),
  );

  Future<StructuralReleaseResult> mutate(
    void Function(Map<String, dynamic>, Map<String, dynamic>) change,
  ) async {
    final editedManifest =
        jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    final editedCoverage =
        jsonDecode(utf8.decode(coverage)) as Map<String, dynamic>;
    change(editedManifest, editedCoverage);
    final rawCoverage = CanonicalReleaseJson.encode(editedCoverage);
    editedManifest['coverageReceiptSHA256'] = _digest(rawCoverage);
    final rawManifest = CanonicalReleaseJson.encode(editedManifest);
    final signed = await Ed25519().sign(<int>[
      ...utf8.encode('motion-media-release-v1'),
      0,
      ...rawManifest,
    ], keyPair: testKeyPair);
    return verify(
      rawManifest: rawManifest,
      rawCoverage: rawCoverage,
      rawSignature: signed.bytes,
      expectedManifestSha: _digest(rawManifest),
    );
  }

  test('Python canonical UTF-8 vector is byte-exact', () {
    final value = <String, Object?>{
      'z': 'İ',
      'a': <Object?>[1, true, 'x\n'],
      'b': <String, Object?>{'é': 'λ'},
    };
    final raw = CanonicalReleaseJson.encode(value);
    expect(
      raw,
      _hex(
        '7b2261223a5b312c747275652c22785c6e225d2c2262223a7b22c3a9223a22cebb227d2c227a223a22c4b0227d',
      ),
    );
    expect(raw.length, 45);
    expect(
      _digest(raw),
      '7b3db3b25eedbd4590f813be04c7c22142ab076d4ed601cc32f1fe347bed503c',
    );
    expect(
      CanonicalReleaseJson.parseObject(raw, maxBytes: 45, code: 'VECTOR')['z'],
      'İ',
    );
  });

  test('Python scalar ordering and escaped string vectors are byte-exact', () {
    final scalarOrder = CanonicalReleaseJson.encode(<String, Object?>{
      '\u{10000}': 2,
      '\u{e000}': 1,
    });
    expect(scalarOrder, _hex('7b22ee8080223a312c22f0908080223a327d'));
    expect(
      _digest(scalarOrder),
      '8706b5798a29d65739b3d1bbb1d009f87d005c71c8130c5353c4990c15ddfec8',
    );
    final escaped = CanonicalReleaseJson.encode(<String, Object?>{
      'x': '[]{}\\"\u2028e\u0301',
    });
    expect(escaped, _hex('7b2278223a225b5d7b7d5c5c5c22e280a865cc81227d'));
    expect(
      _digest(escaped),
      '97ceb98525ebf654da961f32764e2591d3bcbc557ddadfd3914f8077ab289802',
    );
    expect(
      CanonicalReleaseJson.parseObject(escaped, maxBytes: 22, code: 'VECTOR'),
      <String, Object?>{'x': '[]{}\\"\u2028e\u0301'},
    );
  });

  test(
    'Python complete manifest, coverage, and Ed25519 vector is exact',
    () async {
      expect(manifest.length, 2528);
      expect(_digest(manifest), _manifestSha);
      expect(coverage.length, 323);
      expect(_digest(coverage), _coverageSha);
      expect(sourceCatalogBytes.length, 1467);
      expect(_digest(sourceCatalogBytes), _catalogSha);
      expect(signature.length, 64);
      expect(signature, _hex(_signatureHex));
      expect(
        CanonicalReleaseJson.encode(jsonDecode(utf8.decode(manifest))),
        manifest,
      );
      expect(
        CanonicalReleaseJson.encode(jsonDecode(utf8.decode(coverage))),
        coverage,
      );
      final public = await testKeyPair.extractPublicKey() as SimplePublicKey;
      expect(public.bytes, _hex(_publicKeyHex));
      final result = await verify();
      expect(result.state, 'STRUCTURAL_CRYPTO_CHECK_ONLY');
      expect(result.appId, 'ostinato');
      expect(result.acceptedVariants, 1);
      expect(result.openVariants, 0);
      expect(result.heldVariants, 1);
      expect(source.variants.length, 2);
      expect(source.held.length, 1);
      expect(() => (result as dynamic).catalog, throwsNoSuchMethodError);
    },
  );

  test('verification snapshots all three mutable caller byte lists', () async {
    final callerManifest = List<int>.of(manifest);
    final callerSignature = List<int>.of(signature);
    final callerCoverage = List<int>.of(coverage);
    final pending = verify(
      rawManifest: callerManifest,
      rawSignature: callerSignature,
      rawCoverage: callerCoverage,
    );
    callerManifest[0] ^= 1;
    callerSignature[0] ^= 1;
    callerCoverage[0] ^= 1;
    final result = await pending;
    expect(result.acceptedVariants, 1);
    expect(result.heldVariants, 1);
  });

  test(
    'no catalog escapes missing, duplicate, or held signed entries',
    () async {
      await _reject(
        mutate((m, c) => (m['entries'] as List).clear()),
        'ENTRY_COUNT',
      );
      await _reject(
        mutate(
          (m, c) => (m['entries'] as List).add((m['entries'] as List).first),
        ),
        'ENTRY_COVERAGE',
      );
      await _reject(
        mutate(
          (m, c) => (m['entries'] as List).first['sourcePinSHA256'] =
              source.held.single,
        ),
        'ENTRY_HELD_SOURCE',
      );
      await _reject(
        mutate(
          (m, c) => (m['entries'] as List).first['video']['sha256'] = _digest(
            utf8.encode('wrong-video-digest'),
          ),
        ),
        'FILE_PATH',
      );
    },
  );

  test(
    'production entry is closed without reading any catalog asset',
    () async {
      var assetReads = 0;
      for (final app in <String>[
        'ostinato',
        'choreia',
        'jablab',
        'gravita',
        'lissom',
      ]) {
        final decision = await ReleaseProductionGate.verifyBundled(
          appId: app,
          readAsset: (_) async {
            assetReads++;
            return manifest;
          },
        );
        expect(decision.mediaAvailable, isFalse);
        expect(decision.code, 'NO_APPROVED_PRODUCTION_ROOT');
      }
      expect(assetReads, 0);
    },
  );

  test('duplicate decoded key and excessive depth fail before decode', () {
    for (final raw in <String>[
      '{"a":1,"a":2}',
      r'{"a":1,"\u0061":2}',
      r'{"outer":{"a":1,"\u0061":2}}',
    ]) {
      expect(
        () => CanonicalReleaseJson.parseObject(
          utf8.encode(raw),
          maxBytes: 100,
          code: 'VECTOR',
        ),
        throwsA(
          isA<CanonicalReleaseJsonError>().having(
            (error) => error.code,
            'code',
            'DUPLICATE_JSON_KEY',
          ),
        ),
      );
    }
    final deep =
        '{"x":${List<String>.filled(65, '[').join()}0'
        '${List<String>.filled(65, ']').join()}}';
    expect(
      () => CanonicalReleaseJson.parseObject(
        utf8.encode(deep),
        maxBytes: 200,
        code: 'VECTOR',
      ),
      throwsA(
        isA<CanonicalReleaseJsonError>().having(
          (error) => error.code,
          'code',
          'VECTOR_DEPTH',
        ),
      ),
    );
    final atLimit =
        '{"x":${List<String>.filled(63, '[').join()}0'
        '${List<String>.filled(63, ']').join()}}';
    expect(
      CanonicalReleaseJson.parseObject(
        utf8.encode(atLimit),
        maxBytes: 200,
        code: 'VECTOR',
      )['x'],
      isA<List<Object?>>(),
    );
  });

  test('noncanonical, malformed, and oversized JSON fails closed', () {
    final cases = <(List<int>, String)>[
      (utf8.encode('{"a":1}\n'), 'VECTOR_NONCANONICAL'),
      (utf8.encode('{"x":1e999}'), 'VECTOR_JSON'),
      (<int>[0xff], 'VECTOR_JSON'),
      (utf8.encode('{}'), 'VECTOR_SIZE'),
    ];
    for (final (raw, code) in cases) {
      expect(
        () => CanonicalReleaseJson.parseObject(
          raw,
          maxBytes: code == 'VECTOR_SIZE' ? 1 : 100,
          code: 'VECTOR',
        ),
        throwsA(
          isA<CanonicalReleaseJsonError>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }
  });

  test('binary pin rejects even a re-signed other release ID', () async {
    final edited = jsonDecode(utf8.decode(manifest)) as Map<String, dynamic>;
    edited['releaseId'] = 'synthetic-release-2';
    final raw = CanonicalReleaseJson.encode(edited);
    final signed = await Ed25519().sign(<int>[
      ...utf8.encode('motion-media-release-v1'),
      0,
      ...raw,
    ], keyPair: testKeyPair);
    await _reject(
      verify(rawManifest: raw, rawSignature: signed.bytes),
      'MANIFEST_BINARY_PIN',
    );
  });

  test('wrong signature, wrong domain, and truncated signature fail', () async {
    final wrong = List<int>.of(signature)..[0] ^= 1;
    await _reject(verify(rawSignature: wrong), 'SIGNATURE_INVALID');
    final noDomain = await Ed25519().sign(manifest, keyPair: testKeyPair);
    await _reject(verify(rawSignature: noDomain.bytes), 'SIGNATURE_INVALID');
    await _reject(
      verify(rawSignature: signature.sublist(1)),
      'SIGNATURE_FORMAT',
    );
  });

  test('changed canonical coverage fails the signed digest', () async {
    final changed = jsonDecode(utf8.decode(coverage)) as Map<String, dynamic>;
    changed['heldSourcePins'] = <String>[];
    await _reject(
      verify(rawCoverage: CanonicalReleaseJson.encode(changed)),
      'COVERAGE_DIGEST',
    );
  });

  test(
    'signed schema, source, coverage, and file mutations are denied',
    () async {
      await _reject(
        mutate((m, c) => m['distribution'] = 'paid'),
        'MANIFEST_SCHEMA',
      );
      await _reject(
        mutate((m, c) => m['assetHost'] = 'media.example.org.evil.org'),
        'ASSET_HOST',
      );
      await _reject(
        mutate((m, c) => m['sourceManifestSHA256'] = _catalogSha),
        'SOURCE_VERSION',
      );
      await _reject(
        mutate((m, c) => c['heldSourcePins'] = <String>[]),
        'COVERAGE_PARTITION',
      );
      await _reject(
        mutate((m, c) => (m['entries'] as List).first['sceneOrder'] = 1),
        'ENTRY_SOURCE_DRIFT',
      );
      await _reject(
        mutate((m, c) => (m['entries'] as List).first['durationMs'] = 0),
        'DURATION',
      );
      await _reject(
        mutate(
          (m, c) =>
              ((m['entries'] as List).first['captions'] as Map).remove('en'),
        ),
        'CAPTION_LOCALES',
      );
      await _reject(
        mutate(
          (m, c) => (m['entries'] as List).first['video']['path'] =
              'motion-media/v1/../evil.mp4',
        ),
        'FILE_PATH',
      );
      await _reject(
        mutate(
          (m, c) => (m['entries'] as List).first['rightsReceiptSHA256'] =
              (m['entries'] as List).first['acceptanceReceiptSHA256'],
        ),
        'RECEIPT_REUSE',
      );
    },
  );
}
