import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

import 'content_bundle_loader_test.dart';
import 'test_manifest.dart';

void main() {
  test(
    'only allowlisted paths open and each read returns a defensive copy',
    () async {
      final data = validReaderData();
      final raw = MemoryReader(data);
      final result = await loaderFor(raw).load() as ContentReady;
      expect(
        result.assets.allowedLogicalPaths,
        contains('assets/motion_content/lessons/one.json'),
      );

      final first = await result.assets.read(
        'assets/motion_content/lessons/one.json',
      );
      first[0] = 255;
      final second = await result.assets.read(
        'assets/motion_content/lessons/one.json',
      );
      expect(second, lessonBytes);
      expect(identical(first, second), isFalse);

      await expectLater(
        result.assets.read('assets/motion_content/lessons/unlisted.json'),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.missingAsset,
          ),
        ),
      );
      await expectLater(
        result.assets.read('../lesson.json'),
        throwsA(
          isA<ContentException>().having(
            (error) => error.error.code,
            'code',
            ContentErrorCode.unsafePath,
          ),
        ),
      );
    },
  );

  test('read-again verification detects post-startup mutation', () async {
    final data = validReaderData();
    final result = await loaderFor(MemoryReader(data)).load() as ContentReady;
    data['assets/motion_content/lessons/one.json'] = Uint8List.fromList(
      List<int>.filled(lessonBytes.length, 9),
    );

    await expectLater(
      result.assets.read('assets/motion_content/lessons/one.json'),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.hashMismatch,
        ),
      ),
    );
  });

  test('timeout and upstream failures remain safe typed exceptions', () async {
    final asset = parseManifest().assets.last;
    final timeoutResult =
        await loaderFor(
              MemoryReader(validReaderData()),
              policy: ContentLoadPolicy(timeoutRunner: NthTimeoutRunner(4)),
            ).load()
            as ContentReady;
    await expectLater(
      timeoutResult.assets.read(asset.path),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.timeout,
        ),
      ),
    );

    final typedRaw = _MutableReader(validReaderData());
    final typedResult = await loaderFor(typedRaw).load() as ContentReady;
    typedRaw.error = const ContentException(
      ContentError(
        code: ContentErrorCode.io,
        contentId: '/private/token-bearing-path',
        expectedHashPrefix: 'secret',
      ),
    );
    await expectLater(
      typedResult.assets.read(asset.path),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.io,
        ),
      ),
    );
    try {
      await typedResult.assets.read(asset.path);
      fail('expected typed upstream failure');
    } on ContentException catch (error) {
      expect(error.error.contentId, asset.id);
      expect(error.error.expectedHashPrefix, isNull);
    }

    final missingRaw = _MutableReader(validReaderData());
    final missingResult = await loaderFor(missingRaw).load() as ContentReady;
    missingRaw.error = StateError('physical detail');
    await expectLater(
      missingResult.assets.read(asset.path),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.missingAsset,
        ),
      ),
    );
  });

  test('read-again verification checks size before hash', () async {
    final asset = parseManifest().assets.last;
    final data = validReaderData();
    final result = await loaderFor(MemoryReader(data)).load() as ContentReady;
    data[asset.path] = Uint8List.fromList([1]);
    await expectLater(
      result.assets.read(asset.path),
      throwsA(
        isA<ContentException>().having(
          (error) => error.error.code,
          'code',
          ContentErrorCode.sizeMismatch,
        ),
      ),
    );
  });
}

final class _MutableReader implements ContentAssetReader {
  _MutableReader(this.data);

  final Map<String, Uint8List> data;
  Object? error;

  @override
  Future<Uint8List> read(String logicalPath) {
    final currentError = error;
    if (currentError != null) return Future.error(currentError);
    final bytes = data[logicalPath];
    if (bytes == null) return Future.error(StateError('missing'));
    return Future.value(bytes);
  }
}
