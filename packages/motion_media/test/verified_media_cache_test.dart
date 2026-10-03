import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:motion_media/src/verified_media_cache.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('motion-media-cache-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('exact bytes are reused offline and disposed once per lease', () async {
    final cache = VerifiedMediaCache(root: root);
    final bytes = utf8.encode('synthetic silent video bytes');
    final asset = _asset('scene_1', bytes);
    var sourceCalls = 0;
    var closeCalls = 0;
    final first = await cache.open(
      asset: asset,
      source: () {
        sourceCalls++;
        return Stream<List<int>>.value(bytes);
      },
      initialize: (file) async => expect(await file.readAsBytes(), bytes),
      dispose: () async => closeCalls++,
    );
    expect(await first.file.exists(), isTrue);
    await first.close();
    await first.close();

    final second = await cache.open(
      asset: asset,
      source: () => throw StateError('cached media should work offline'),
      initialize: (file) async => expect(await file.readAsBytes(), bytes),
      dispose: () async => closeCalls++,
    );
    await second.close();
    expect(sourceCalls, 1);
    expect(closeCalls, 2);
    expect(cache.isQuarantined, isFalse);
  });

  test('non-byte integers cannot alias verified bytes', () async {
    final cache = VerifiedMediaCache(root: root);
    final good = <int>[0, 255];
    final asset = _asset('integer_alias', good);
    var initialized = false;
    for (final malformed in <List<int>>[
      <int>[256, 255],
      <int>[0, -1],
      <int>[0, 511],
    ]) {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      controller.add(malformed);
      await expectLater(
        cache.open(
          asset: asset,
          source: () => controller.stream,
          initialize: (_) async => initialized = true,
          dispose: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(initialized, isFalse);
      expect(cancelled, isTrue);
      await controller.close();
      expect(await root.list().toList(), isEmpty);
      expect(cache.isQuarantined, isFalse);
    }
    final lease = await _open(cache, asset, good);
    expect(await lease.file.readAsBytes(), good);
    await lease.close();
  });

  test('boundary bytes accept typed, empty and split chunks', () async {
    final cache = VerifiedMediaCache(root: root);
    final good = <int>[0, 255];
    final lease = await cache.open(
      asset: _asset('boundary_bytes', good),
      source: () => Stream<List<int>>.fromIterable(<List<int>>[
        <int>[],
        Uint8List.fromList(<int>[0]),
        <int>[255],
      ]),
      initialize: (file) async => expect(await file.readAsBytes(), good),
      dispose: () async {},
    );
    await lease.close();
    expect(cache.isQuarantined, isFalse);
  });

  test('path traversal and invalid digest are rejected before I/O', () {
    final digest = sha256.convert(<int>[1]).toString();
    expect(
      () => VerifiedMediaAsset(
        key: '../outside',
        kind: MediaFileKind.mp4,
        expectedBytes: 1,
        expectedSha256: digest,
      ),
      throwsArgumentError,
    );
    expect(
      () => VerifiedMediaAsset(
        key: 'scene',
        kind: MediaFileKind.vtt,
        expectedBytes: 1,
        expectedSha256: 'not-a-sha',
      ),
      throwsArgumentError,
    );
    expect(
      () => VerifiedMediaAsset(
        key: 'scene',
        kind: MediaFileKind.vtt,
        expectedBytes: MediaFileKind.vtt.maxBytes + 1,
        expectedSha256: digest,
      ),
      throwsArgumentError,
    );
  });

  test(
    'a symlinked cache target cannot read or overwrite its destination',
    () async {
      final outside = await File(
        '${root.parent.path}/outside-${root.uri.pathSegments.last}',
      ).writeAsString('outside');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete();
      });
      final asset = _asset('scene', utf8.encode('inside'));
      await Link('${root.path}/${asset.fileName}').create(outside.path);
      final cache = VerifiedMediaCache(root: root);
      await expectLater(
        _open(cache, asset, utf8.encode('inside')),
        throwsA(isA<StateError>()),
      );
      expect(await outside.readAsString(), 'outside');
    },
  );

  test('a symlinked root is rejected', () async {
    final link = Link(
      '${root.parent.path}/root-link-${root.uri.pathSegments.last}',
    );
    await link.create(root.path);
    addTearDown(() async {
      if (await link.exists()) await link.delete();
    });
    final bytes = utf8.encode('clip');
    await expectLater(
      _open(
        VerifiedMediaCache(root: Directory(link.path)),
        _asset('a', bytes),
        bytes,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'an orphan stage rejects a cache miss before opening its source',
    () async {
      final orphan = await Directory(
        '${root.path}/.motion-stage-orphan',
      ).create();
      await File('${orphan.path}/payload.mp4').writeAsBytes(<int>[1, 2, 3]);
      var sourceCalls = 0;
      final bytes = utf8.encode('clip');
      final cache = VerifiedMediaCache(root: root);
      await expectLater(
        cache.open(
          asset: _asset('scene', bytes),
          source: () {
            sourceCalls++;
            return Stream<List<int>>.value(bytes);
          },
          initialize: (_) async {},
          dispose: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(sourceCalls, 0);
      expect(await orphan.exists(), isTrue);
      expect(await root.list().toList(), hasLength(1));
    },
  );

  test(
    'wrong SHA, truncated and overflow streams leave no final file',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final good = utf8.encode('good');
      final asset = _asset('scene', good);
      for (final bytes in <List<int>>[
        utf8.encode('evil'),
        utf8.encode('sho'),
        utf8.encode('extra'),
      ]) {
        await expectLater(
          _open(cache, asset, bytes),
          throwsA(isA<StateError>()),
        );
        expect(await root.list().toList(), isEmpty);
      }
    },
  );

  test(
    'corrupt final requires explicit invalidation before verified retry',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final good = utf8.encode('good');
      final asset = _asset('retry', good);
      final initial = await _open(cache, asset, good);
      await initial.close();
      await initial.file.writeAsBytes(utf8.encode('evil'), flush: true);
      var sourceCalls = 0;
      await expectLater(
        cache.open(
          asset: asset,
          source: () {
            sourceCalls++;
            return Stream<List<int>>.value(good);
          },
          initialize: (_) async {},
          dispose: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(sourceCalls, 0);
      final receipt = await cache.inspectCorrupt(asset);
      expect(receipt, isNotNull);
      expect(
        receipt!.observedSha256,
        sha256.convert(utf8.encode('evil')).toString(),
      );
      await cache.invalidateCorrupt(asset, receipt);
      expect(await initial.file.exists(), isFalse);
      final recovered = await cache.open(
        asset: asset,
        source: () {
          sourceCalls++;
          return Stream<List<int>>.value(good);
        },
        initialize: (file) async => expect(await file.readAsBytes(), good),
        dispose: () async {},
      );
      expect(sourceCalls, 1);
      expect(await recovered.file.readAsBytes(), good);
      await recovered.close();
    },
  );

  test('live pin and healthy restoration block corrupt invalidation', () async {
    final cache = VerifiedMediaCache(root: root);
    final good = utf8.encode('good');
    final asset = _asset('pinned', good);
    final lease = await _open(cache, asset, good);
    await lease.file.writeAsBytes(utf8.encode('evil'), flush: true);
    final receipt = (await cache.inspectCorrupt(asset))!;
    await expectLater(
      cache.invalidateCorrupt(asset, receipt),
      throwsA(isA<StateError>()),
    );
    expect(await lease.file.exists(), isTrue);
    await lease.close();
    await lease.file.writeAsBytes(good, flush: true);
    expect(await cache.inspectCorrupt(asset), isNull);
    await expectLater(
      cache.invalidateCorrupt(asset, receipt),
      throwsA(isA<StateError>()),
    );
    expect(await lease.file.readAsBytes(), good);
  });

  test(
    'receipt is exact and a replacement symlink or directory is rejected',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final good = utf8.encode('good');
      final asset = _asset('exact', good);
      final other = _asset('other', good);
      final lease = await _open(cache, asset, good);
      await lease.close();
      await lease.file.writeAsBytes(utf8.encode('evil'), flush: true);
      final receipt = (await cache.inspectCorrupt(asset))!;
      await expectLater(
        cache.invalidateCorrupt(other, receipt),
        throwsArgumentError,
      );
      final outside = await File(
        '${root.parent.path}/outside-${root.uri.pathSegments.last}',
      ).writeAsString('outside');
      addTearDown(() async {
        if (await outside.exists()) await outside.delete();
      });
      await lease.file.delete();
      final link = Link(lease.file.path);
      await link.create(outside.path);
      await expectLater(
        cache.invalidateCorrupt(asset, receipt),
        throwsA(isA<StateError>()),
      );
      expect(await outside.readAsString(), 'outside');
      await link.delete();
      final directory = await Directory(lease.file.path).create();
      await expectLater(
        cache.invalidateCorrupt(asset, receipt),
        throwsA(isA<StateError>()),
      );
      await directory.delete();
    },
  );

  test(
    'cancelled recovery rolls back final and permits a fresh verified retry',
    () async {
      final token = MediaCancellation();
      var cancelNext = false;
      final cache = VerifiedMediaCache(
        root: root,
        admissionObserver: (phase) async {
          if (cancelNext && phase == MediaAdmissionCheckpoint.afterRename) {
            token.cancel();
          }
        },
      );
      final good = utf8.encode('good');
      final asset = _asset('cancel_retry', good);
      final first = await _open(cache, asset, good);
      await first.close();
      await first.file.writeAsBytes(utf8.encode('evil'), flush: true);
      final receipt = (await cache.inspectCorrupt(asset))!;
      await cache.invalidateCorrupt(asset, receipt);
      cancelNext = true;
      await expectLater(
        cache.open(
          asset: asset,
          source: () => Stream<List<int>>.value(good),
          initialize: (_) async {},
          dispose: () async {},
          cancellation: token,
        ),
        throwsA(isA<MediaCancelled>()),
      );
      expect(await first.file.exists(), isFalse);
      cancelNext = false;
      final recovered = await _open(cache, asset, good);
      expect(await recovered.file.readAsBytes(), good);
      await recovered.close();
    },
  );

  test(
    'invalidation and immediate new open serialize before verified source',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final good = utf8.encode('good');
      final asset = _asset('serial_retry', good);
      final first = await _open(cache, asset, good);
      await first.close();
      await first.file.writeAsBytes(utf8.encode('evil'), flush: true);
      final receipt = (await cache.inspectCorrupt(asset))!;
      final invalidation = cache.invalidateCorrupt(asset, receipt);
      var sourceCalls = 0;
      final opening = cache.open(
        asset: asset,
        source: () {
          sourceCalls++;
          return Stream<List<int>>.value(good);
        },
        initialize: (file) async => expect(await file.readAsBytes(), good),
        dispose: () async {},
      );
      await invalidation;
      final recovered = await opening;
      expect(sourceCalls, 1);
      expect(await recovered.file.readAsBytes(), good);
      await recovered.close();
    },
  );

  test(
    'source construction failure cleans the stage and permits retry',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final bytes = utf8.encode('clip');
      final asset = _asset('source_error', bytes);
      await expectLater(
        cache.open(
          asset: asset,
          source: () => throw StateError('transport unavailable'),
          initialize: (_) async {},
          dispose: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(await root.list().toList(), isEmpty);
      final lease = await _open(cache, asset, bytes);
      expect(await lease.file.readAsBytes(), bytes);
      await lease.close();
    },
  );

  test(
    'same-key concurrent requests download once and hold separate pins',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final bytes = utf8.encode('clip');
      final asset = _asset('same_key', bytes);
      final releaseSource = Completer<void>();
      var sourceCalls = 0;
      Stream<List<int>> source() {
        sourceCalls++;
        return Stream<List<int>>.fromFuture(
          releaseSource.future.then((_) => bytes),
        );
      }

      final firstFuture = cache.open(
        asset: asset,
        source: source,
        initialize: (_) async {},
        dispose: () async {},
      );
      final secondFuture = cache.open(
        asset: asset,
        source: source,
        initialize: (_) async {},
        dispose: () async {},
      );
      releaseSource.complete();
      final leases = await Future.wait(<Future<VerifiedPlaybackLease>>[
        firstFuture,
        secondFuture,
      ]);
      expect(sourceCalls, 1);
      expect(leases[0].file.path, leases[1].file.path);
      await leases[0].close();
      expect(await leases[1].file.exists(), isTrue);
      await leases[1].close();
    },
  );

  test(
    'a second cache instance cannot evict the first instance live lease',
    () async {
      final first = VerifiedMediaCache(root: root, maxCacheBytes: 4);
      final bytes = utf8.encode('aaaa');
      final lease = await _open(first, _asset('a', bytes), bytes);
      var secondSourceCalls = 0;
      final second = VerifiedMediaCache(root: root, maxCacheBytes: 4);
      final otherBytes = utf8.encode('bbbb');
      await expectLater(
        second.open(
          asset: _asset('b', otherBytes),
          source: () {
            secondSourceCalls++;
            return Stream<List<int>>.value(otherBytes);
          },
          initialize: (_) async {},
          dispose: () async {},
        ),
        throwsA(isA<StateError>()),
      );
      expect(secondSourceCalls, 0);
      expect(await lease.file.exists(), isTrue);
      await lease.close();
    },
  );

  test(
    'LRU cannot delete a file during pending native initialization',
    () async {
      final cache = VerifiedMediaCache(root: root, maxCacheBytes: 8);
      final a = _asset('a', utf8.encode('aaaa'));
      final b = _asset('b', utf8.encode('bbbb'));
      final c = _asset('c', utf8.encode('cccc'));
      final initStarted = Completer<File>();
      final finishInit = Completer<void>();
      final pendingA = cache.open(
        asset: a,
        source: () => Stream<List<int>>.value(utf8.encode('aaaa')),
        initialize: (file) async {
          initStarted.complete(file);
          await finishInit.future;
        },
        dispose: () async {},
      );
      final aFile = await initStarted.future;
      final bLease = await _open(cache, b, utf8.encode('bbbb'));
      final bFile = bLease.file;
      await bLease.close();
      final cLease = await _open(cache, c, utf8.encode('cccc'));
      expect(await aFile.exists(), isTrue);
      expect(await bFile.exists(), isFalse);
      expect(await cLease.file.exists(), isTrue);
      finishInit.complete();
      final aLease = await pendingA;
      await aLease.close();
      await cLease.close();
    },
  );

  test(
    'a pinned file blocks admission when no other space is evictable',
    () async {
      final cache = VerifiedMediaCache(root: root, maxCacheBytes: 4);
      final a = _asset('a', utf8.encode('aaaa'));
      final b = _asset('b', utf8.encode('bbbb'));
      final lease = await _open(cache, a, utf8.encode('aaaa'));
      await expectLater(
        _open(cache, b, utf8.encode('bbbb')),
        throwsA(isA<MediaCacheFull>()),
      );
      expect(await lease.file.exists(), isTrue);
      await lease.close();
    },
  );

  test('cancellation stops an idle stream and removes the stage', () async {
    final cache = VerifiedMediaCache(root: root);
    final bytes = utf8.encode('clip');
    final token = MediaCancellation();
    final subscribed = Completer<void>();
    var streamCancelled = false;
    final stream = StreamController<List<int>>(
      onListen: subscribed.complete,
      onCancel: () => streamCancelled = true,
    );
    final future = cache.open(
      asset: _asset('idle', bytes),
      source: () => stream.stream,
      initialize: (_) async {},
      dispose: () async {},
      cancellation: token,
    );
    await subscribed.future;
    token.cancel();
    await expectLater(future, throwsA(isA<MediaCancelled>()));
    expect(streamCancelled, isTrue);
    expect(await root.list().toList(), isEmpty);
    await stream.close();
  });

  test('late cancellation never leaves a newly published file', () async {
    final bytes = utf8.encode('clip');
    for (final checkpoint in MediaAdmissionCheckpoint.values) {
      final phaseRoot = await Directory(
        '${root.path}/${checkpoint.name}',
      ).create();
      final token = MediaCancellation();
      final cache = VerifiedMediaCache(
        root: phaseRoot,
        admissionObserver: (phase) async {
          if (phase == checkpoint) token.cancel();
        },
      );
      await expectLater(
        cache.open(
          asset: _asset('scene', bytes),
          source: () => Stream<List<int>>.value(bytes),
          initialize: (_) async {},
          dispose: () async {},
          cancellation: token,
        ),
        throwsA(isA<MediaCancelled>()),
      );
      expect(await phaseRoot.list().toList(), isEmpty, reason: checkpoint.name);
    }
  });

  test(
    'an asynchronous source cancellation error is observed and quarantined',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final bytes = utf8.encode('clip');
      final token = MediaCancellation();
      final subscribed = Completer<void>();
      final stream = StreamController<List<int>>(
        onListen: subscribed.complete,
        onCancel: () async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          throw StateError('upstream cancellation failed');
        },
      );
      final future = cache.open(
        asset: _asset('scene', bytes),
        source: () => stream.stream,
        initialize: (_) async {},
        dispose: () async {},
        cancellation: token,
      );
      await subscribed.future;
      token.cancel();
      await expectLater(future, throwsA(isA<MediaSourceCancelUncertain>()));
      expect(cache.isQuarantined, isTrue);
      expect(await root.list().toList(), isEmpty);
      await stream.close();
    },
  );

  test('a source cancellation timeout cannot strand cache admission', () async {
    final cache = VerifiedMediaCache(
      root: root,
      closeTimeout: const Duration(milliseconds: 50),
    );
    final bytes = utf8.encode('clip');
    final token = MediaCancellation();
    final subscribed = Completer<void>();
    final finishCancellation = Completer<void>();
    final stream = StreamController<List<int>>(
      onListen: subscribed.complete,
      onCancel: () => finishCancellation.future,
    );
    final future = cache.open(
      asset: _asset('scene', bytes),
      source: () => stream.stream,
      initialize: (_) async {},
      dispose: () async {},
      cancellation: token,
    );
    await subscribed.future;
    token.cancel();
    await expectLater(future, throwsA(isA<MediaSourceCancelUncertain>()));
    expect(cache.isQuarantined, isTrue);
    expect(await root.list().toList(), isEmpty);
    finishCancellation.complete();
    await stream.close();
  });

  test(
    'uncertain native disposal keeps the pin and quarantines the cache',
    () async {
      final cache = VerifiedMediaCache(root: root, maxCacheBytes: 4);
      final bytes = utf8.encode('clip');
      final asset = _asset('scene', bytes);
      final lease = await cache.open(
        asset: asset,
        source: () => Stream<List<int>>.value(bytes),
        initialize: (_) async {},
        dispose: () async => throw StateError('native timeout'),
      );
      await expectLater(lease.close(), throwsA(isA<MediaCloseUncertain>()));
      expect(cache.isQuarantined, isTrue);
      expect(await lease.file.exists(), isTrue);
      await expectLater(
        _open(cache, asset, bytes),
        throwsA(isA<MediaCloseUncertain>()),
      );
    },
  );

  test(
    'pending native close blocks opens and timeout stays quarantined',
    () async {
      final cache = VerifiedMediaCache(
        root: root,
        maxCacheBytes: 4,
        closeTimeout: const Duration(milliseconds: 50),
      );
      final bytes = utf8.encode('clip');
      final asset = _asset('scene', bytes);
      final finishNativeClose = Completer<void>();
      final lease = await cache.open(
        asset: asset,
        source: () => Stream<List<int>>.value(bytes),
        initialize: (_) async {},
        dispose: () => finishNativeClose.future,
      );
      final close = lease.close();
      await expectLater(
        _open(cache, asset, bytes),
        throwsA(isA<MediaCloseUncertain>()),
      );
      await expectLater(close, throwsA(isA<MediaCloseUncertain>()));
      finishNativeClose.complete();
      await Future<void>.delayed(Duration.zero);
      expect(cache.isQuarantined, isTrue);
      expect(await lease.file.exists(), isTrue);
      await expectLater(
        _open(cache, asset, bytes),
        throwsA(isA<MediaCloseUncertain>()),
      );
    },
  );

  test(
    'pending initialization cannot return after another close poisons cache',
    () async {
      final cache = VerifiedMediaCache(root: root, maxCacheBytes: 8);
      final aBytes = utf8.encode('aaaa');
      final bBytes = utf8.encode('bbbb');
      final aLease = await cache.open(
        asset: _asset('a', aBytes),
        source: () => Stream<List<int>>.value(aBytes),
        initialize: (_) async {},
        dispose: () async => throw StateError('native close unknown'),
      );
      final bStarted = Completer<void>();
      final finishB = Completer<void>();
      var bCloses = 0;
      final pendingB = cache.open(
        asset: _asset('b', bBytes),
        source: () => Stream<List<int>>.value(bBytes),
        initialize: (_) async {
          bStarted.complete();
          await finishB.future;
        },
        dispose: () async => bCloses++,
      );
      await bStarted.future;
      await expectLater(aLease.close(), throwsA(isA<MediaCloseUncertain>()));
      finishB.complete();
      await expectLater(pendingB, throwsA(isA<MediaCloseUncertain>()));
      expect(bCloses, 1);
      expect(cache.isQuarantined, isTrue);
    },
  );

  test(
    'an initialization error closes partial native state before release',
    () async {
      final cache = VerifiedMediaCache(root: root);
      final bytes = utf8.encode('clip');
      var closes = 0;
      await expectLater(
        cache.open(
          asset: _asset('scene', bytes),
          source: () => Stream<List<int>>.value(bytes),
          initialize: (_) async => throw StateError('decoder rejected'),
          dispose: () async => closes++,
        ),
        throwsA(isA<StateError>()),
      );
      expect(closes, 1);
      expect(cache.isQuarantined, isFalse);
    },
  );
}

VerifiedMediaAsset _asset(String key, List<int> bytes) => VerifiedMediaAsset(
  key: key,
  kind: MediaFileKind.mp4,
  expectedBytes: bytes.length,
  expectedSha256: sha256.convert(bytes).toString(),
);

Future<VerifiedPlaybackLease> _open(
  VerifiedMediaCache cache,
  VerifiedMediaAsset asset,
  List<int> bytes,
) => cache.open(
  asset: asset,
  source: () => Stream<List<int>>.value(bytes),
  initialize: (_) async {},
  dispose: () async {},
);
