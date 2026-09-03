import 'dart:convert';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

import 'test_manifest.dart';

ManifestValidationReport validate(
  Map<String, Object?> map, {
  Set<String> capabilities = const {'cpu'},
}) {
  return ManifestValidator(
    expectedAppId: 'com.example.motion',
    currentCoreContract: SemanticVersion.parse('1.2.0'),
    availableCapabilities: capabilities,
  ).validate(parseManifest(map));
}

void main() {
  test(
    'accepts a complete manifest and reports an optional fallback as degraded',
    () {
      final report = validate(validManifestMap(), capabilities: {'cpu'});
      expect(report.error, isNull);
      expect(report.degradedCapabilities, ['gpu_delegate']);

      final ready = validate(
        validManifestMap(),
        capabilities: {'gpu_delegate'},
      );
      expect(ready.error, isNull);
      expect(ready.degradedCapabilities, isEmpty);
      expect(ready.isBlocked, isFalse);
      expect(ready.isDegraded, isFalse);
      expect(report.isBlocked, isFalse);
      expect(report.isDegraded, isTrue);

      final neitherPrimaryNorFallback = validate(
        validManifestMap(),
        capabilities: const {},
      );
      expect(
        neitherPrimaryNorFallback.error?.code,
        ContentErrorCode.capability,
      );
      expect(neitherPrimaryNorFallback.isBlocked, isTrue);
    },
  );

  test('catalog digest mismatch is reported before identity checks', () {
    final map = validManifestMap()..['catalogDigest'] = '0' * 64;
    final manifest = ContentManifestParser().parse(
      Uint8List.fromList(utf8.encode(jsonEncode(map))),
    );
    final report = ManifestValidator(
      expectedAppId: 'wrong-app',
      currentCoreContract: SemanticVersion.parse('0.0.0'),
    ).validate(manifest);
    expect(report.error?.code, ContentErrorCode.catalogDigestMismatch);
    expect(report.isBlocked, isTrue);
    expect(report.isDegraded, isFalse);
    expect(report.error?.expectedHashPrefix, '000000000000');
    expect(report.error?.actualHashPrefix, hasLength(12));
  });

  test('wrong app identity and incompatible core fail closed', () {
    final wrongApp = validManifestMap()..['appId'] = 'com.example.other';
    expect(validate(wrongApp).error?.code, ContentErrorCode.appIdentity);

    final futureCore = validManifestMap()..['minimumCoreContract'] = '2.0.0';
    expect(validate(futureCore).error?.code, ContentErrorCode.compatibility);
  });

  test('duplicate IDs are rejected in deterministic category order', () {
    final map = validManifestMap();
    final courses = map['courses']! as List<Object?>;
    courses.add(deepCopy(courses.single! as Map<String, Object?>));
    expect(validate(map).error?.code, ContentErrorCode.duplicateId);
    expect(validate(map).error?.contentId, 'foundation');
  });

  test('IDs are unique across the complete content graph', () {
    final map = validManifestMap();
    final asset =
        (map['assets']! as List<Object?>).first! as Map<String, Object?>;
    asset['id'] = 'foundation';

    final report = validate(map);
    expect(report.error?.code, ContentErrorCode.duplicateId);
    expect(report.error?.contentId, 'foundation');
  });

  test(
    'lesson, model, asset, asset-path, and per-model capability duplicates fail',
    () {
      final cases = <Map<String, Object?>>[];

      final lessons = validManifestMap();
      final lessonList = lessons['lessons']! as List<Object?>;
      lessonList.add(deepCopy(lessonList.single! as Map<String, Object?>));
      cases.add(lessons);

      final models = validManifestMap();
      final modelList = models['models']! as List<Object?>;
      modelList.add(deepCopy(modelList.single! as Map<String, Object?>));
      cases.add(models);

      final assets = validManifestMap();
      final assetList = assets['assets']! as List<Object?>;
      assetList.add(deepCopy(assetList.first! as Map<String, Object?>));
      cases.add(assets);

      final paths = validManifestMap();
      final pathAssets = paths['assets']! as List<Object?>;
      final duplicatePath = deepCopy(pathAssets.last! as Map<String, Object?>)
        ..['id'] = 'other-id'
        ..['path'] = (pathAssets.first! as Map<String, Object?>)['path'];
      pathAssets.add(duplicatePath);
      cases.add(paths);

      final capabilities = validManifestMap();
      final model =
          (capabilities['models']! as List<Object?>).single!
              as Map<String, Object?>;
      final capabilityList = model['capabilities']! as List<Object?>;
      capabilityList.add(
        deepCopy(capabilityList.single! as Map<String, Object?>),
      );
      cases.add(capabilities);

      for (final map in cases) {
        expect(validate(map).error?.code, ContentErrorCode.duplicateId);
      }
      expect(
        validate(paths).error?.contentId,
        'other-id',
        reason: 'diagnostics expose a logical ID, never the duplicated path',
      );
    },
  );

  test('unsafe asset and model paths are rejected before graph traversal', () {
    final unsafeAsset = validManifestMap();
    final asset =
        (unsafeAsset['assets']! as List<Object?>).first!
            as Map<String, Object?>;
    asset['path'] = '../model.tflite';
    expect(validate(unsafeAsset).error?.code, ContentErrorCode.unsafePath);

    final unsafeModel = validManifestMap();
    final model =
        (unsafeModel['models']! as List<Object?>).single!
            as Map<String, Object?>;
    model['path'] = 'https://models.example.org/model';
    expect(validate(unsafeModel).error?.code, ContentErrorCode.unsafePath);
  });

  test(
    'orphan course, lesson model, and lesson asset references are rejected',
    () {
      final courseOrphan = validManifestMap();
      final course =
          (courseOrphan['courses']! as List<Object?>).single!
              as Map<String, Object?>;
      course['lessonIds'] = <Object?>['missing'];
      expect(
        validate(courseOrphan).error?.code,
        ContentErrorCode.orphanReference,
      );

      final modelOrphan = validManifestMap();
      final lesson =
          (modelOrphan['lessons']! as List<Object?>).single!
              as Map<String, Object?>;
      lesson['modelIds'] = <Object?>['missing'];
      expect(
        validate(modelOrphan).error?.code,
        ContentErrorCode.orphanReference,
      );

      final assetOrphan = validManifestMap();
      final orphanLesson =
          (assetOrphan['lessons']! as List<Object?>).single!
              as Map<String, Object?>;
      orphanLesson['assetIds'] = <Object?>['missing'];
      expect(
        validate(assetOrphan).error?.code,
        ContentErrorCode.orphanReference,
      );
    },
  );

  test(
    'required capability blocks while optional capability requires a fallback',
    () {
      final required = validManifestMap();
      final model =
          (required['models']! as List<Object?>).single!
              as Map<String, Object?>;
      model['capabilities'] = <Object?>[
        <String, Object?>{'id': 'neural_accelerator', 'required': true},
      ];
      expect(validate(required).error?.code, ContentErrorCode.capability);

      final optionalWithoutFallback = validManifestMap();
      final optionalModel =
          (optionalWithoutFallback['models']! as List<Object?>).single!
              as Map<String, Object?>;
      optionalModel['capabilities'] = <Object?>[
        <String, Object?>{'id': 'gpu_delegate', 'required': false},
      ];
      expect(
        () => parseManifest(optionalWithoutFallback),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.capability,
          ),
        ),
      );
    },
  );

  test('the same device capability may be used by more than one model', () {
    final map = validManifestMap();
    final models = map['models']! as List<Object?>;
    final second = deepCopy(models.single! as Map<String, Object?>)
      ..['id'] = 'pose-model-two';
    models.add(second);

    final available = validate(map, capabilities: {'gpu_delegate'});
    expect(available.error, isNull);

    final unavailable = validate(map);
    expect(unavailable.error, isNull);
    expect(unavailable.degradedCapabilities, ['gpu_delegate']);
  });

  test('model metadata must match an allowlisted asset record', () {
    final map = validManifestMap();
    final model =
        (map['models']! as List<Object?>).single! as Map<String, Object?>;
    model['sha256'] = '0' * 64;
    expect(validate(map).error?.code, ContentErrorCode.hashMismatch);

    final wrongSize = validManifestMap();
    final wrongSizeModel =
        (wrongSize['models']! as List<Object?>).single! as Map<String, Object?>;
    wrongSizeModel['byteLength'] = modelBytes.length + 1;
    expect(validate(wrongSize).error?.code, ContentErrorCode.sizeMismatch);

    final missingAsset = validManifestMap();
    final missingModel =
        (missingAsset['models']! as List<Object?>).single!
            as Map<String, Object?>;
    missingModel['path'] = 'assets/motion_content/models/missing.tflite';
    expect(
      validate(missingAsset).error?.code,
      ContentErrorCode.orphanReference,
    );
  });
}
