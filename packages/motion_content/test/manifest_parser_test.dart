import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

import 'test_manifest.dart';

ContentErrorCode errorCodeFor(Uint8List bytes) {
  try {
    ContentManifestParser().parse(bytes);
  } on ContentException catch (error) {
    return error.error.code;
  }
  throw StateError('Expected manifest parse to fail');
}

void main() {
  group('ContentManifestParser strict schema', () {
    test('parses an immutable, exact-locale manifest', () {
      final manifest = parseManifest();
      expect(manifest.appId, 'com.example.motion');
      expect(manifest.locales, ['tr', 'en']);
      expect(() => manifest.locales.add('de'), throwsUnsupportedError);
      expect(
        manifest.models.single.provenance,
        isA<ThirdPartyModelProvenance>(),
      );
    });

    test('public collection constructors defensively copy caller maps', () {
      final title = <String, String>{'tr': 'Temel', 'en': 'Foundation'};
      final description = <String, String>{
        'tr': 'Temel dersler',
        'en': 'Foundation lessons',
      };
      final course = ContentCourse(
        id: 'foundation',
        order: 0,
        visibility: 'free',
        title: title,
        description: description,
        lessonIds: const ['lesson-one'],
      );

      title['en'] = 'mutated';
      description['tr'] = 'degisti';

      expect(course.title['en'], 'Foundation');
      expect(course.description['tr'], 'Temel dersler');
      expect(
        () => course.title['en'] = 'still-mutating',
        throwsUnsupportedError,
      );
    });

    test(
      'rejects missing, unknown, wrong-type, and unsupported root fields',
      () {
        final cases = <(Map<String, Object?>, ContentErrorCode)>[];
        final missing = validManifestMap()..remove('appId');
        cases.add((missing, ContentErrorCode.schema));
        final unknown = validManifestMap()..['surprise'] = true;
        cases.add((unknown, ContentErrorCode.schema));
        final wrongType = validManifestMap()..['courses'] = 'not-a-list';
        cases.add((wrongType, ContentErrorCode.schema));
        final unsupported = validManifestMap()..['schemaVersion'] = 2;
        cases.add((unsupported, ContentErrorCode.schema));

        for (final entry in cases) {
          expect(errorCodeFor(encodeManifest(entry.$1)), entry.$2);
        }
      },
    );

    test('rejects duplicate raw JSON properties before typed decoding', () {
      final bytes = File(
        'test/fixtures/invalid/duplicate-key.json',
      ).readAsBytesSync();
      expect(errorCodeFor(bytes), ContentErrorCode.duplicateJsonKey);
    });

    test(
      'rejects missing, extra, and blank locale content without fallback',
      () {
        final missingLocale = validManifestMap();
        final course =
            (missingLocale['courses']! as List<Object?>).single!
                as Map<String, Object?>;
        (course['title']! as Map<String, Object?>).remove('tr');
        expect(
          errorCodeFor(encodeManifest(missingLocale)),
          ContentErrorCode.locale,
        );

        final blankLocale = validManifestMap();
        final lesson =
            (blankLocale['lessons']! as List<Object?>).single!
                as Map<String, Object?>;
        (lesson['instruction']! as Map<String, Object?>)['en'] = '  ';
        expect(
          errorCodeFor(encodeManifest(blankLocale)),
          ContentErrorCode.locale,
        );

        final extraLocale = validManifestMap()
          ..['locales'] = <Object?>['tr', 'en', 'de'];
        expect(
          errorCodeFor(encodeManifest(extraLocale)),
          ContentErrorCode.locale,
        );
      },
    );

    test(
      'enforces first-party and third-party provenance as a closed union',
      () {
        final firstParty = validManifestMap();
        final model =
            (firstParty['models']! as List<Object?>).single!
                as Map<String, Object?>;
        model
          ..['provenanceKind'] = 'firstParty'
          ..remove('vendorArtifactRef')
          ..remove('vendorChecksum')
          ..['trainingReceiptRef'] = 'training:2026-09-03'
          ..['holdoutReceiptRef'] = 'holdout:2026-09-03';
        final provenance =
            parseManifest(firstParty).models.single.provenance
                as FirstPartyModelProvenance;
        expect(provenance.kind, 'firstParty');
        expect(
          provenance.toJson(),
          containsPair('trainingReceiptRef', 'training:2026-09-03'),
        );
        expect(
          provenance.toJson(),
          containsPair('holdoutReceiptRef', 'holdout:2026-09-03'),
        );
        expect(provenance.toJson(), isNot(contains('vendorArtifactRef')));

        model.remove('holdoutReceiptRef');
        expect(
          errorCodeFor(encodeManifest(firstParty)),
          ContentErrorCode.schema,
        );

        final mixed = validManifestMap();
        final mixedModel =
            (mixed['models']! as List<Object?>).single! as Map<String, Object?>;
        mixedModel['trainingReceiptRef'] = 'not-allowed-for-third-party';
        expect(errorCodeFor(encodeManifest(mixed)), ContentErrorCode.schema);

        final unknown = validManifestMap();
        final unknownModel =
            (unknown['models']! as List<Object?>).single!
                as Map<String, Object?>;
        unknownModel['provenanceKind'] = 'unknown';
        expect(errorCodeFor(encodeManifest(unknown)), ContentErrorCode.schema);
      },
    );

    test('rejects invalid identifiers, versions, hashes, and booleans', () {
      final invalidId = validManifestMap();
      final asset =
          (invalidId['assets']! as List<Object?>).first!
              as Map<String, Object?>;
      asset['id'] = '../asset';
      expect(errorCodeFor(encodeManifest(invalidId)), ContentErrorCode.schema);

      final invalidVersion = validManifestMap()..['contentVersion'] = '1.0';
      expect(
        errorCodeFor(encodeManifest(invalidVersion)),
        ContentErrorCode.schema,
      );

      final invalidHash = validManifestMap();
      final hashedAsset =
          (invalidHash['assets']! as List<Object?>).first!
              as Map<String, Object?>;
      hashedAsset['sha256'] = 'not-a-sha256';
      expect(
        errorCodeFor(encodeManifest(invalidHash)),
        ContentErrorCode.schema,
      );

      final invalidBoolean = validManifestMap();
      final model =
          (invalidBoolean['models']! as List<Object?>).single!
              as Map<String, Object?>;
      final capability =
          (model['capabilities']! as List<Object?>).single!
              as Map<String, Object?>;
      capability['required'] = 'false';
      expect(
        errorCodeFor(encodeManifest(invalidBoolean)),
        ContentErrorCode.schema,
      );
    });

    test(
      'rejects asset optionality because every listed byte is mandatory',
      () {
        final map = validManifestMap();
        final asset =
            (map['assets']! as List<Object?>).last! as Map<String, Object?>;
        asset['required'] = true;
        expect(errorCodeFor(encodeManifest(map)), ContentErrorCode.schema);
      },
    );

    test('rejects credential-bearing or placeholder model provenance', () {
      for (final sourceUrl in [
        'http://models.example.org/model',
        'https://user:secret@models.example.org/model',
        'https://models.example.org/model?token=secret',
        'https://models.example.org/sk-proj-1234567890abcdef/model',
        'https://models.example.org/sk%2Dproj%2D1234567890abcdef/model',
        'https://models.example.org/sk%252Dproj%252D1234567890abcdef/model',
      ]) {
        final map = validManifestMap();
        final model =
            (map['models']! as List<Object?>).single! as Map<String, Object?>;
        model['sourceUrl'] = sourceUrl;
        expect(errorCodeFor(encodeManifest(map)), ContentErrorCode.schema);
      }
      final placeholder = validManifestMap();
      final model =
          (placeholder['models']! as List<Object?>).single!
              as Map<String, Object?>;
      for (final value in ['N/A', '  n/a  ']) {
        model['licenseSpdx'] = value;
        expect(
          errorCodeFor(encodeManifest(placeholder)),
          ContentErrorCode.schema,
        );
      }

      for (final entry in <String, String>{
        'licenseSpdx': 'license with free text',
        'sourceVersion': 'version with user data',
        'exportTool': 'sk-proj-1234567890abcdef',
        'exportToolVersion': 'v1/../../secret',
        'vendorArtifactRef': 'vendor:AKIA1234567890ABCDEF',
      }.entries) {
        final map = validManifestMap();
        final constrainedModel =
            (map['models']! as List<Object?>).single! as Map<String, Object?>;
        constrainedModel[entry.key] = entry.value;
        expect(errorCodeFor(encodeManifest(map)), ContentErrorCode.schema);
      }

      final fakeSpdx = validManifestMap();
      final fakeSpdxModel =
          (fakeSpdx['models']! as List<Object?>).single!
              as Map<String, Object?>;
      fakeSpdxModel['licenseSpdx'] = 'Definitely-Not-A-Real-SPDX-License';
      expect(errorCodeFor(encodeManifest(fakeSpdx)), ContentErrorCode.schema);

      for (final license in ['MIT', 'BSD-2-Clause', 'BSD-3-Clause']) {
        final supportedSpdx = validManifestMap();
        final supportedSpdxModel =
            (supportedSpdx['models']! as List<Object?>).single!
                as Map<String, Object?>;
        supportedSpdxModel['licenseSpdx'] = license;
        expect(() => parseManifest(supportedSpdx), returnsNormally);
      }

      final firstParty = validManifestMap();
      final firstPartyModel =
          (firstParty['models']! as List<Object?>).single!
              as Map<String, Object?>;
      firstPartyModel
        ..['provenanceKind'] = 'firstParty'
        ..remove('vendorArtifactRef')
        ..remove('vendorChecksum')
        ..['trainingReceiptRef'] = 'training:raw user sentence'
        ..['holdoutReceiptRef'] = 'holdout:2026-09-03';
      expect(errorCodeFor(encodeManifest(firstParty)), ContentErrorCode.schema);
    });
  });

  group('ContentManifestParser resource limits', () {
    test('rejects a manifest larger than 1 MiB before schema parsing', () {
      final bytes = Uint8List.fromList(
        utf8.encode('{"x":"${'a' * (1024 * 1024)}"}'),
      );
      expect(errorCodeFor(bytes), ContentErrorCode.resourceLimit);
    });

    test('rejects nesting deeper than 16 and strings longer than 16 KiB', () {
      final deeplyNested = '${'[' * 17}0${']' * 17}';
      expect(
        errorCodeFor(Uint8List.fromList(utf8.encode(deeplyNested))),
        ContentErrorCode.resourceLimit,
      );
      final longString = Uint8List.fromList(
        utf8.encode('{"x":"${'a' * 16385}"}'),
      );
      expect(errorCodeFor(longString), ContentErrorCode.resourceLimit);
    });

    test(
      'rejects collection and declared-byte ceilings before asset reads',
      () {
        final tooManyCourses = validManifestMap();
        final courseTemplate =
            (tooManyCourses['courses']! as List<Object?>).single;
        tooManyCourses['courses'] = List<Object?>.filled(257, courseTemplate);
        expect(
          errorCodeFor(encodeManifest(tooManyCourses)),
          ContentErrorCode.resourceLimit,
        );

        final oversizedAsset = validManifestMap();
        final oversized =
            (oversizedAsset['assets']! as List<Object?>).first!
                as Map<String, Object?>;
        oversized['byteLength'] = maximumSingleAssetBytes + 1;
        expect(
          errorCodeFor(encodeManifest(oversizedAsset)),
          ContentErrorCode.resourceLimit,
        );

        final tooManyBytes = validManifestMap();
        final assetTemplate = deepCopy(
          (tooManyBytes['assets']! as List<Object?>).first!
              as Map<String, Object?>,
        );
        tooManyBytes['assets'] = <Object?>[
          for (var index = 0; index < 9; index += 1)
            deepCopy(assetTemplate)
              ..['id'] = 'asset-$index'
              ..['path'] = 'assets/motion_content/data/asset-$index.bin'
              ..['byteLength'] = maximumSingleAssetBytes,
        ];
        expect(
          errorCodeFor(encodeManifest(tooManyBytes)),
          ContentErrorCode.resourceLimit,
        );
      },
    );
  });

  test(
    'ContentException string is stable and never includes raw payload/path',
    () {
      const error = ContentException(
        ContentError(
          code: ContentErrorCode.hashMismatch,
          contentId: 'asset-id',
          expectedHashPrefix: '0123456789ab',
          actualHashPrefix: 'abcdef012345',
        ),
      );
      final rendered = error.toString();
      expect(rendered, contains('hashMismatch'));
      expect(rendered, contains('asset-id'));
      expect(rendered, contains('0123456789ab'));
      expect(rendered, contains('abcdef012345'));
      expect(rendered, isNot(contains('/private/')));
      expect(rendered, isNot(contains('token')));
    },
  );
}
