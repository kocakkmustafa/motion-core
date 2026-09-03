import 'dart:async';
import 'dart:typed_data';

import 'package:motion_content/motion_content.dart';
import 'package:test/test.dart';

import 'test_manifest.dart';

class MemoryReader implements ContentAssetReader {
  MemoryReader(this.data);

  final Map<String, Uint8List> data;
  int calls = 0;

  @override
  Future<Uint8List> read(String logicalPath) async {
    calls += 1;
    final value = data[logicalPath];
    if (value == null) throw StateError('missing');
    return value;
  }
}

class SequenceReader implements ContentAssetReader {
  SequenceReader(this.responses);

  final List<FutureOr<Uint8List> Function(String)> responses;
  int calls = 0;

  @override
  Future<Uint8List> read(String logicalPath) async {
    final response = responses[calls++];
    return response(logicalPath);
  }
}

class ErrorReader implements ContentAssetReader {
  ErrorReader(this.error);

  final Object error;

  @override
  Future<Uint8List> read(String logicalPath) => Future<Uint8List>.error(error);
}

class FirstTimeoutRunner implements ContentTimeoutRunner {
  int calls = 0;

  @override
  Future<T> run<T>(Future<T> operation, Duration timeout) {
    calls += 1;
    if (calls == 1) return Future<T>.error(TimeoutException('bounded'));
    return operation;
  }
}

class NthTimeoutRunner implements ContentTimeoutRunner {
  NthTimeoutRunner(this.timeoutAt);

  final int timeoutAt;
  int calls = 0;

  @override
  Future<T> run<T>(Future<T> operation, Duration timeout) {
    calls += 1;
    if (calls == timeoutAt) {
      return Future<T>.error(TimeoutException('bounded'));
    }
    return operation;
  }
}

ContentBundleLoader loaderFor(
  ContentAssetReader reader, {
  ContentLoadPolicy? policy,
  Set<String> capabilities = const {'gpu_delegate'},
}) {
  return ContentBundleLoader(
    reader: reader,
    expectedAppId: 'com.example.motion',
    currentCoreContract: SemanticVersion.parse('1.2.0'),
    availableCapabilities: capabilities,
    policy: policy,
  );
}

void main() {
  test(
    'validates manifest and every asset sequentially without payload caching',
    () async {
      final reader = MemoryReader(validReaderData());
      final result = await loaderFor(reader).load();
      expect(result, isA<ContentReady>());
      final ready = result as ContentReady;
      expect(ready.catalog.manifest.appId, 'com.example.motion');
      expect(reader.calls, 3);

      await ready.assets.read('assets/motion_content/lessons/one.json');
      expect(
        reader.calls,
        4,
        reason:
            'validated reads must return to the source, not a payload cache',
      );
    },
  );

  test('loader does not expose its unvalidated source reader', () {
    final loader = loaderFor(MemoryReader(validReaderData()));

    expect(() => (loader as dynamic).reader, throwsNoSuchMethodError);
  });

  test('missing, size-mismatched, and hash-mismatched bytes block', () async {
    final missing = validReaderData()
      ..remove('assets/motion_content/lessons/one.json');
    expect(
      (await loaderFor(MemoryReader(missing)).load() as ContentBlocked)
          .error
          .code,
      ContentErrorCode.missingAsset,
    );

    final wrongSize = validReaderData()
      ..['assets/motion_content/lessons/one.json'] = Uint8List.fromList([1]);
    expect(
      (await loaderFor(MemoryReader(wrongSize)).load() as ContentBlocked)
          .error
          .code,
      ContentErrorCode.sizeMismatch,
    );

    final wrongHash = validReaderData()
      ..['assets/motion_content/lessons/one.json'] = Uint8List.fromList(
        List<int>.filled(lessonBytes.length, 7),
      );
    final hashFailure =
        await loaderFor(MemoryReader(wrongHash)).load() as ContentBlocked;
    expect(hashFailure.error.code, ContentErrorCode.hashMismatch);
    expect(hashFailure.error.expectedHashPrefix, hasLength(12));
    expect(hashFailure.error.actualHashPrefix, hasLength(12));
  });

  test(
    'never-completing read times out and retry starts a fresh attempt',
    () async {
      final data = validReaderData();
      final reader = MemoryReader(data);
      final timeoutRunner = FirstTimeoutRunner();
      final loader = loaderFor(
        reader,
        policy: ContentLoadPolicy(
          readTimeout: const Duration(milliseconds: 1),
          timeoutRunner: timeoutRunner,
        ),
      );

      final first = await loader.load();
      expect((first as ContentBlocked).error.code, ContentErrorCode.timeout);

      final second = await loader.load();
      expect(second, isA<ContentReady>());
      expect(
        reader.calls,
        4,
        reason: 'one timed-out manifest + a complete fresh attempt',
      );
    },
  );

  test(
    'the default timeout runner bounds a genuinely never-completing read',
    () async {
      final data = validReaderData();
      final never = Completer<Uint8List>();
      final reader = SequenceReader([
        (_) => never.future,
        (path) => data[path]!,
        (path) => data[path]!,
        (path) => data[path]!,
      ]);
      final loader = loaderFor(
        reader,
        policy: const ContentLoadPolicy(
          readTimeout: Duration(milliseconds: 10),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final first = await loader.load();
      stopwatch.stop();
      expect((first as ContentBlocked).error.code, ContentErrorCode.timeout);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));

      final second = await loader.load();
      expect(second, isA<ContentReady>());
      expect(reader.calls, 4);
    },
  );

  test('concurrent callers share exactly one in-flight attempt', () async {
    final manifestCompleter = Completer<Uint8List>();
    final data = validReaderData();
    final reader = SequenceReader([
      (_) => manifestCompleter.future,
      (path) => data[path]!,
      (path) => data[path]!,
    ]);
    final loader = loaderFor(reader);

    final first = loader.load();
    final second = loader.load();
    expect(identical(first, second), isTrue);
    expect(reader.calls, 1);

    manifestCompleter.complete(data['assets/motion_content/manifest.json']);
    expect(await first, isA<ContentReady>());
    expect(reader.calls, 3);
  });

  test(
    'optional capability with explicit fallback produces typed degraded result',
    () async {
      final result = await loaderFor(
        MemoryReader(validReaderData()),
        capabilities: const {'cpu'},
      ).load();
      expect(result, isA<ContentDegraded>());
      expect((result as ContentDegraded).unavailableCapabilities, [
        'gpu_delegate',
      ]);
    },
  );

  test('missing primary and fallback capabilities block', () async {
    final result = await loaderFor(
      MemoryReader(validReaderData()),
      capabilities: const {},
    ).load();
    expect(result, isA<ContentBlocked>());
    expect((result as ContentBlocked).error.code, ContentErrorCode.capability);
  });

  test('oversized reader results fail before defensive copying', () async {
    final oversizedManifest = MemoryReader({
      'assets/motion_content/manifest.json': Uint8List(1024 * 1024 + 1),
    });
    final manifestResult = await loaderFor(oversizedManifest).load();
    expect(
      (manifestResult as ContentBlocked).error.code,
      ContentErrorCode.resourceLimit,
    );

    final data = validReaderData()
      ..['assets/motion_content/models/pose.tflite'] = Uint8List(
        maximumSingleAssetBytes + 1,
      );
    final assetResult = await loaderFor(MemoryReader(data)).load();
    expect(
      (assetResult as ContentBlocked).error.code,
      ContentErrorCode.resourceLimit,
    );
  });

  test(
    'manifest read, parse, and metadata failures stay typed and sanitized',
    () async {
      final typedReadFailure = await loaderFor(
        ErrorReader(
          const ContentException(
            ContentError(
              code: ContentErrorCode.io,
              contentId: '/private/token-bearing-path',
              expectedHashPrefix: 'secret',
            ),
          ),
        ),
      ).load();
      final sanitizedReadFailure = typedReadFailure as ContentBlocked;
      expect(sanitizedReadFailure.error.code, ContentErrorCode.io);
      expect(sanitizedReadFailure.error.contentId, isNull);
      expect(sanitizedReadFailure.error.expectedHashPrefix, isNull);

      final invalidManifest = validReaderData()
        ..['assets/motion_content/manifest.json'] = Uint8List.fromList([0xff]);
      final parseFailure = await loaderFor(
        MemoryReader(invalidManifest),
      ).load();
      expect(
        (parseFailure as ContentBlocked).error.code,
        ContentErrorCode.parse,
      );

      final wrongIdentity = ContentBundleLoader(
        reader: MemoryReader(validReaderData()),
        expectedAppId: 'com.example.other',
        currentCoreContract: SemanticVersion.parse('1.2.0'),
        availableCapabilities: const {'gpu_delegate'},
      );
      final identityFailure = await wrongIdentity.load();
      expect(
        (identityFailure as ContentBlocked).error.code,
        ContentErrorCode.appIdentity,
      );
    },
  );

  test(
    'asset timeout and typed read failure identify only the logical asset',
    () async {
      final timeout = await loaderFor(
        MemoryReader(validReaderData()),
        policy: ContentLoadPolicy(timeoutRunner: NthTimeoutRunner(2)),
      ).load();
      expect((timeout as ContentBlocked).error.code, ContentErrorCode.timeout);
      expect(timeout.error.contentId, 'pose-model-bytes');

      final data = validReaderData();
      final typedReader = SequenceReader([
        (path) => data[path]!,
        (_) => throw const ContentException(
          ContentError(
            code: ContentErrorCode.io,
            contentId: '/private/token-bearing-path',
            actualHashPrefix: 'secret',
          ),
        ),
      ]);
      final typed = await loaderFor(typedReader).load();
      expect((typed as ContentBlocked).error.code, ContentErrorCode.io);
      expect(typed.error.contentId, 'pose-model-bytes');
      expect(typed.error.actualHashPrefix, isNull);
    },
  );

  test('constructor rejects an unsafe manifest path without normalization', () {
    expect(
      () => ContentBundleLoader(
        reader: MemoryReader(validReaderData()),
        expectedAppId: 'com.example.motion',
        currentCoreContract: SemanticVersion.parse('1.2.0'),
        manifestPath: '../manifest.json',
      ),
      throwsA(isA<ContentException>()),
    );
  });
}
