import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:motion_content/src/secure_asset_file.dart';
import 'package:test/test.dart';

import 'test_manifest.dart';

Map<String, Object?> sourceManifestMap() {
  final source = deepCopy(validManifestMap())..remove('catalogDigest');
  for (final raw in source['assets']! as List<Object?>) {
    (raw! as Map<String, Object?>)
      ..remove('byteLength')
      ..remove('sha256');
  }
  for (final raw in source['models']! as List<Object?>) {
    (raw! as Map<String, Object?>)
      ..remove('byteLength')
      ..remove('sha256');
  }
  return source;
}

Future<Directory> createAssetRoot() async {
  final root = await Directory.systemTemp.createTemp('motion_content_test_');
  final model = File('${root.path}/assets/motion_content/models/pose.tflite');
  final lesson = File('${root.path}/assets/motion_content/lessons/one.json');
  await model.parent.create(recursive: true);
  await lesson.parent.create(recursive: true);
  await model.writeAsBytes(modelBytes);
  await lesson.writeAsBytes(lessonBytes);
  return root;
}

void main() {
  test('checked-in source fixture builds a canonical empty catalog', () async {
    final root = await Directory.systemTemp.createTemp(
      'motion_content_fixture_test_',
    );
    addTearDown(() => root.delete(recursive: true));
    final sourceBytes = await File(
      'test/fixtures/valid/manifest.source.json',
    ).readAsBytes();

    final bytes = await ManifestBuilder().build(
      sourceBytes: sourceBytes,
      root: root,
    );
    final manifest = ContentManifestParser().parse(bytes);

    expect(manifest.appId, 'com.example.motion');
    expect(manifest.assets, isEmpty);
    expect(utf8.decode(bytes).endsWith('\n'), isTrue);
  });

  test(
    'build emits deterministic canonical bytes and verify enforces byte equality',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final source = Uint8List.fromList(
        utf8.encode(jsonEncode(sourceManifestMap())),
      );
      final builder = ManifestBuilder();

      final first = await builder.build(sourceBytes: source, root: root);
      final second = await builder.build(sourceBytes: source, root: root);
      expect(first, second);
      expect(utf8.decode(first).endsWith('\n'), isTrue);
      await builder.verify(
        manifestBytes: first,
        root: root,
        expectedAppId: 'com.example.motion',
        currentCoreContract: SemanticVersion.parse('1.2.0'),
      );
    },
  );

  test(
    'build rejects symlinks and a single asset larger than 64 MiB',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final model = File(
        '${root.path}/assets/motion_content/models/pose.tflite',
      );
      final target = File('${root.path}/actual-model.bin');
      await target.writeAsBytes(modelBytes);
      await model.delete();
      await Link(model.path).create(target.path);
      final source = Uint8List.fromList(
        utf8.encode(jsonEncode(sourceManifestMap())),
      );
      await expectLater(
        ManifestBuilder().build(sourceBytes: source, root: root),
        throwsA(isA<ContentException>()),
      );

      await model.delete();
      final handle = model.openSync(mode: FileMode.write);
      handle.truncateSync(64 * 1024 * 1024 + 1);
      handle.closeSync();
      await expectLater(
        ManifestBuilder().build(sourceBytes: source, root: root),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.resourceLimit,
          ),
        ),
      );
    },
  );

  test('build rejects symlink roots and intermediate directories', () async {
    final actualRoot = await createAssetRoot();
    addTearDown(() => actualRoot.delete(recursive: true));
    final links = await Directory.systemTemp.createTemp(
      'motion_content_link_test_',
    );
    addTearDown(() => links.delete(recursive: true));
    final source = Uint8List.fromList(
      utf8.encode(jsonEncode(sourceManifestMap())),
    );

    final rootLink = Link('${links.path}/root-link');
    await rootLink.create(actualRoot.path);
    for (final rootPath in [
      rootLink.path,
      '${rootLink.path}/',
      '${rootLink.path}/.',
      '${rootLink.path}/assets/..',
    ]) {
      await expectLater(
        ManifestBuilder().build(sourceBytes: source, root: Directory(rootPath)),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.unsafePath,
          ),
        ),
        reason: 'root symlink must fail for non-canonical spellings',
      );
    }

    final intermediateRoot = await createAssetRoot();
    addTearDown(() => intermediateRoot.delete(recursive: true));
    final models = Directory(
      '${intermediateRoot.path}/assets/motion_content/models',
    );
    final movedModels = Directory('${links.path}/models');
    await models.rename(movedModels.path);
    await Link(models.path).create(movedModels.path);
    await expectLater(
      ManifestBuilder().build(sourceBytes: source, root: intermediateRoot),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.unsafePath,
        ),
      ),
    );
  });

  test('descriptor walk refuses a final-component symlink swap', () async {
    final root = await createAssetRoot();
    addTearDown(() => root.delete(recursive: true));
    final outsideRoot = await Directory.systemTemp.createTemp(
      'motion-content-final-swap-',
    );
    addTearDown(() => outsideRoot.delete(recursive: true));
    final outside = File('${outsideRoot.path}/outside.bin');
    await outside.writeAsBytes(List<int>.filled(32, 9));
    final logicalPath = 'assets/motion_content/models/pose.tflite';
    final target = File('${root.path}/$logicalPath');

    expect(
      () => SecureAssetFile.open(
        rootPath: root.absolute.path,
        logicalPath: logicalPath,
        contentId: 'pose',
        beforeFinalOpenForTesting: () {
          target.deleteSync();
          Link(target.path).createSync(outside.path);
        },
      ),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.unsafePath,
        ),
      ),
    );
  });

  test('descriptor walk refuses a final-component FIFO swap', () async {
    final root = await createAssetRoot();
    addTearDown(() => root.delete(recursive: true));
    final logicalPath = 'assets/motion_content/models/pose.tflite';
    final target = File('${root.path}/$logicalPath');

    expect(
      () => SecureAssetFile.open(
        rootPath: root.absolute.path,
        logicalPath: logicalPath,
        contentId: 'pose',
        beforeFinalOpenForTesting: () {
          target.deleteSync();
          final result = Process.runSync('mkfifo', [target.path]);
          if (result.exitCode != 0) {
            throw StateError('mkfifo failed: ${result.stderr}');
          }
        },
      ),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.unsafePath,
        ),
      ),
    );
  });

  test('descriptor walk stays on the opened parent during a swap', () async {
    final root = await createAssetRoot();
    addTearDown(() => root.delete(recursive: true));
    final outsideRoot = await Directory.systemTemp.createTemp(
      'motion-content-outside-root-',
    );
    addTearDown(() => outsideRoot.delete(recursive: true));
    final outsideModel = File('${outsideRoot.path}/pose.tflite');
    await outsideModel.writeAsBytes(List<int>.filled(modelBytes.length, 9));
    final logicalPath = 'assets/motion_content/models/pose.tflite';
    final models = Directory('${root.path}/assets/motion_content/models');
    final movedModels = Directory(
      '${root.path}/assets/motion_content/models-opened',
    );

    final asset = SecureAssetFile.open(
      rootPath: root.absolute.path,
      logicalPath: logicalPath,
      contentId: 'pose',
      beforeFinalOpenForTesting: () {
        models.renameSync(movedModels.path);
        Link(models.path).createSync(outsideRoot.path);
      },
    );
    try {
      expect(asset.readBounded(maximumSingleAssetBytes, 'pose'), modelBytes);
    } finally {
      asset.close();
    }
  });

  test('build preflights the aggregate 512 MiB asset limit', () async {
    final root = await Directory.systemTemp.createTemp(
      'motion_content_total_limit_test_',
    );
    addTearDown(() => root.delete(recursive: true));
    final sourceMap = sourceManifestMap();
    sourceMap['models'] = <Object?>[];
    final lesson =
        (sourceMap['lessons']! as List<Object?>).single!
            as Map<String, Object?>;
    lesson
      ..['modelIds'] = <Object?>[]
      ..['assetIds'] = <Object?>[];
    final assets = <Object?>[];
    sourceMap['assets'] = assets;

    for (var index = 0; index < 9; index += 1) {
      final logicalPath = 'assets/motion_content/media/asset-$index.bin';
      assets.add(<String, Object?>{'id': 'asset-$index', 'path': logicalPath});
      final file = File('${root.path}/$logicalPath');
      await file.parent.create(recursive: true);
      final handle = file.openSync(mode: FileMode.write);
      handle.truncateSync(maximumSingleAssetBytes);
      handle.closeSync();
    }

    await expectLater(
      ManifestBuilder().build(
        sourceBytes: Uint8List.fromList(utf8.encode(jsonEncode(sourceMap))),
        root: root,
      ),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.resourceLimit,
        ),
      ),
    );
  });

  test('missing provenance receipt fails closed before output', () async {
    final root = await createAssetRoot();
    addTearDown(() => root.delete(recursive: true));
    final sourceMap = sourceManifestMap();
    final model =
        (sourceMap['models']! as List<Object?>).single! as Map<String, Object?>;
    model.remove('vendorArtifactRef');
    final source = Uint8List.fromList(utf8.encode(jsonEncode(sourceMap)));
    await expectLater(
      ManifestBuilder().build(sourceBytes: source, root: root),
      throwsA(isA<ContentException>()),
    );
  });

  test(
    'build validates the declared minimum against the actual Core contract',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final sourceMap = sourceManifestMap()
        ..['minimumCoreContract'] = '999.0.0';

      await expectLater(
        ManifestBuilder().build(
          sourceBytes: Uint8List.fromList(utf8.encode(jsonEncode(sourceMap))),
          root: root,
        ),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.compatibility,
          ),
        ),
      );
    },
  );

  test(
    'source rejects precomputed fields, duplicate paths, and orphan models',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));

      final withDigest = sourceManifestMap()..['catalogDigest'] = '0' * 64;
      final withDigestBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(withDigest)),
      );
      await expectLater(
        ManifestBuilder().build(sourceBytes: withDigestBytes, root: root),
        throwsA(isA<ContentException>()),
      );

      final precomputed = sourceManifestMap();
      final precomputedModel =
          (precomputed['models']! as List<Object?>).single!
              as Map<String, Object?>;
      precomputedModel['sha256'] = '0' * 64;
      await expectLater(
        ManifestBuilder().build(
          sourceBytes: Uint8List.fromList(utf8.encode(jsonEncode(precomputed))),
          root: root,
        ),
        throwsA(isA<ContentException>()),
      );

      final duplicatePath = sourceManifestMap();
      final assets = duplicatePath['assets']! as List<Object?>;
      (assets.last! as Map<String, Object?>)['path'] =
          (assets.first! as Map<String, Object?>)['path'];
      await expectLater(
        ManifestBuilder().build(
          sourceBytes: Uint8List.fromList(
            utf8.encode(jsonEncode(duplicatePath)),
          ),
          root: root,
        ),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.duplicateId,
          ),
        ),
      );

      final orphan = sourceManifestMap();
      final orphanModel =
          (orphan['models']! as List<Object?>).single! as Map<String, Object?>;
      orphanModel['path'] = 'assets/motion_content/models/orphan.tflite';
      await expectLater(
        ManifestBuilder().build(
          sourceBytes: Uint8List.fromList(utf8.encode(jsonEncode(orphan))),
          root: root,
        ),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.orphanReference,
          ),
        ),
      );
    },
  );

  test(
    'missing physical asset and non-canonical manifest fail verification',
    () async {
      final root = await createAssetRoot();
      addTearDown(() => root.delete(recursive: true));
      final source = Uint8List.fromList(
        utf8.encode(jsonEncode(sourceManifestMap())),
      );
      final builder = ManifestBuilder();
      final manifestBytes = await builder.build(
        sourceBytes: source,
        root: root,
      );

      await File(
        '${root.path}/assets/motion_content/lessons/one.json',
      ).delete();
      await expectLater(
        builder.verify(
          manifestBytes: manifestBytes,
          root: root,
          expectedAppId: 'com.example.motion',
          currentCoreContract: SemanticVersion.parse('1.2.0'),
        ),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.missingAsset,
          ),
        ),
      );

      await File(
        '${root.path}/assets/motion_content/lessons/one.json',
      ).writeAsBytes(lessonBytes);
      final decoded =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, Object?>;
      final nonCanonical = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(decoded)),
      );
      await expectLater(
        builder.verify(
          manifestBytes: nonCanonical,
          root: root,
          expectedAppId: 'com.example.motion',
          currentCoreContract: SemanticVersion.parse('1.2.0'),
        ),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.schema,
          ),
        ),
      );
    },
  );
}
