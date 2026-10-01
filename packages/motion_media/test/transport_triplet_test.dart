import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:motion_media/motion_media.dart';
import 'package:motion_media/src/bounded_webvtt.dart';
import 'package:motion_media/src/canonical_release_json.dart';
import 'package:motion_media/src/exact_https_media_source.dart';
import 'package:motion_media/src/release_manifest.dart';
import 'package:motion_media/src/verified_media_cache.dart';
import 'package:motion_media/src/verified_media_triplet.dart';
import 'package:test/test.dart';

const _catalogSha =
    '87854b777591afc1b5c20b2a27db44bcd9a5e502453ec161f601ad5d94e9f906';
const _sourceManifestSha =
    '2c0a7630fca46508a34480ac3b0145664fa270ce6d92494e7b2aba6644d29b9c';
const _reviewRootSha =
    '08fa03b963cb26aaef1a958eb6c5f7806ce31419ae9b2eb2a60b7e23619ed571';

String _digest(List<int> bytes) => hashes.sha256.convert(bytes).toString();

final class _Case {
  _Case(this.release, this.bytes);

  final PinnedProjectionReleaseResult release;
  final Map<String, List<int>> bytes;
}

Future<_Case> _signedCase({String? tr, String? en, int? durationMs}) async {
  final fixture = Directory('test/fixtures');
  final catalog =
      jsonDecode(
            await File(
              '${fixture.path}/v2l_synthetic_source_catalog.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  final source = SourceMembershipIndex.fromPreverifiedCatalog(
    catalog.cast<String, Object?>(),
    'ostinato',
  );
  final projection = CanonicalReleaseJson.encode(<String, Object?>{
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
  final pin = SourceProjectionPin(
    appId: 'ostinato',
    projectionSha256: _digest(projection),
    sourceCatalogSha256: _catalogSha,
    sourceManifestSha256: _sourceManifestSha,
    courseSourceSha256: source.courseSourceSha256,
    variantCount: 2,
    heldCount: 1,
  );
  final manifest =
      jsonDecode(
            await File(
              '${fixture.path}/v2l_synthetic_release.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  final entry = (manifest['entries'] as List).single as Map<String, dynamic>;
  if (durationMs != null) entry['durationMs'] = durationMs;
  final payloads = <String, List<int>>{};
  void setFile(Map<String, dynamic> file, String content, String extension) {
    final bytes = utf8.encode(content);
    final digest = _digest(bytes);
    final path = 'motion-media/v1/ostinato/$digest.$extension';
    file['path'] = path;
    file['bytes'] = bytes.length;
    file['sha256'] = digest;
    payloads['/$path'] = bytes;
  }

  setFile(
    entry['video'] as Map<String, dynamic>,
    'synthetic-mp4-bytes-for-cache',
    'mp4',
  );
  setFile(
    (entry['captions'] as Map<String, dynamic>)['tr'] as Map<String, dynamic>,
    tr ?? 'WEBVTT\n\n00:00:00.000 --> 00:00:04.000\nMerhaba\n',
    'vtt',
  );
  setFile(
    (entry['captions'] as Map<String, dynamic>)['en'] as Map<String, dynamic>,
    en ?? 'WEBVTT\n\n00:00:00.000 --> 00:00:04.000\nHello\n',
    'vtt',
  );
  final rawManifest = CanonicalReleaseJson.encode(manifest);
  final rawCoverage = await File(
    '${fixture.path}/v2l_synthetic_coverage.json',
  ).readAsBytes();
  final key = await Ed25519().newKeyPairFromSeed(
    List<int>.generate(32, (index) => index),
  );
  final signed = await Ed25519().sign(<int>[
    ...utf8.encode('motion-media-release-v1'),
    0,
    ...rawManifest,
  ], keyPair: key);
  final public = await key.extractPublicKey();
  final root = ReleaseTrustRoot(
    keyId: 'synthetic-key-never-ship',
    ed25519PublicKey: public.bytes,
    assetHost: 'media.example.org',
    reviewTrustRootSha256: _reviewRootSha,
    expectedManifestSha256: _digest(rawManifest),
  );
  return _Case(
    await StructuralReleaseVerifier.verifyWithProjection(
      rawManifest: rawManifest,
      rawSignature: signed.bytes,
      rawCoverage: rawCoverage,
      rawProjection: projection,
      projectionPin: pin,
      root: root,
    ),
    payloads,
  );
}

final class _HttpPort implements ExactMediaHttpPort {
  _HttpPort(this.bytes);

  final Map<String, List<int>> bytes;
  final List<Uri> requests = <Uri>[];
  int aborts = 0;
  int statusCode = 200;
  String? badHeader;
  String? badValue;
  Completer<ExactMediaResponse>? pendingHeader;
  Stream<List<int>>? bodyOverride;
  bool throwOnAbort = false;

  @override
  Future<ExactMediaResponse> get(Uri uri, TripletAbort abort) {
    requests.add(uri);
    final data = bytes[uri.path] ?? <int>[];
    final headers = <String, List<String>>{
      'content-type': <String>[
        uri.path.endsWith('.mp4') ? 'video/mp4' : 'text/vtt',
      ],
      'content-length': <String>['${data.length}'],
    };
    if (badHeader != null) headers[badHeader!] = <String>[badValue!];
    final response = ExactMediaResponse(
      statusCode: statusCode,
      headers: headers,
      body: bodyOverride ?? Stream<List<int>>.value(data),
      abort: () {
        aborts++;
        if (throwOnAbort) throw StateError('socket close unconfirmed');
      },
    );
    return pendingHeader?.future ?? Future<ExactMediaResponse>.value(response);
  }
}

final class _Player implements NativeTripletPlayerPort {
  int initialized = 0;
  int disposed = 0;
  File? caption;
  Future<void> Function()? onInitialize;
  Future<void> Function()? onDispose;

  @override
  Future<void> initialize(File video, File selectedCaption) async {
    initialized++;
    caption = selectedCaption;
    await onInitialize?.call();
  }

  @override
  Future<void> dispose() async {
    disposed++;
    await onDispose?.call();
  }
}

void main() {
  late Directory directory;
  late _Case signed;
  late _HttpPort port;
  late _Player player;
  late VerifiedMediaTripletSession session;

  Future<TripletPlaybackLease> open({
    String lesson = 'synthetic.lesson',
    String scene = 'ostinato:synthetic.lesson:orientation',
    String stem = 'synthetic/active-master',
    String locale = 'tr',
    TripletAbort? abort,
    bool Function()? scopeCurrent,
  }) => session.open(
    lessonId: lesson,
    sceneId: scene,
    variantStem: stem,
    locale: locale,
    abort: abort ?? TripletAbort(),
    scopeCurrent: scopeCurrent ?? () => true,
    player: player,
  );

  setUp(() async {
    signed = await _signedCase();
    directory = await Directory.systemTemp.createTemp('motion-triplet-');
    port = _HttpPort(signed.bytes);
    player = _Player();
    session = VerifiedMediaTripletSession(
      release: signed.release,
      cache: VerifiedMediaCache(root: directory),
      source: ExactHttpsMediaSource(port: port),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'signed triplet parses both captions, pins, closes, then opens offline',
    () async {
      final lease = await open();
      expect(port.requests, hasLength(3));
      expect(
        port.requests.every(
          (uri) =>
              uri.scheme == 'https' &&
              uri.host == 'media.example.org' &&
              uri.port == 443 &&
              uri.query.isEmpty &&
              uri.fragment.isEmpty,
        ),
        isTrue,
      );
      expect(player.caption!.path, lease.trCaptionFile.path);
      expect(lease.videoFile.existsSync(), isTrue);
      await lease.close();
      expect(player.disposed, 1);
      port.bytes.clear();
      final offline = await open(locale: 'en');
      expect(port.requests, hasLength(3));
      expect(player.caption!.path, offline.enCaptionFile.path);
      await offline.close();
    },
  );

  test('unknown or held tuple reaches no transport or native player', () async {
    await expectLater(
      open(stem: 'synthetic/held-master'),
      throwsA(isA<TripletContractError>()),
    );
    await expectLater(
      open(scene: 'missing'),
      throwsA(isA<TripletContractError>()),
    );
    expect(port.requests, isEmpty);
    expect(player.initialized, 0);
  });

  test(
    'real HTTP port rejects non-HTTPS and alternate port before connect',
    () async {
      const real = DartIoExactMediaHttpPort();
      for (final uri in <Uri>[
        Uri.parse('http://media.example.org/file'),
        Uri.parse('https://media.example.org:8443/file'),
        Uri.parse('https://user@media.example.org/file'),
        Uri.parse('https://media.example.org/file?x=1'),
      ]) {
        await expectLater(
          real.get(uri, TripletAbort()),
          throwsA(isA<ExactMediaTransportError>()),
        );
      }
    },
  );

  test('all three live leases block eviction until confirmed close', () async {
    final entry = signed.release.catalog.entries.single;
    final cap =
        entry.video.bytes + entry.trCaption.bytes + entry.enCaption.bytes;
    final cache = VerifiedMediaCache(root: directory, maxCacheBytes: cap);
    session = VerifiedMediaTripletSession(
      release: signed.release,
      cache: cache,
      source: ExactHttpsMediaSource(port: port),
    );
    final lease = await open();
    final extra = VerifiedMediaAsset(
      key: 'extra',
      kind: MediaFileKind.vtt,
      expectedBytes: 1,
      expectedSha256: _digest(<int>[65]),
    );
    Future<VerifiedPlaybackLease> openExtra() => cache.open(
      asset: extra,
      source: () => Stream<List<int>>.value(<int>[65]),
      initialize: (_) async {},
      dispose: () async {},
    );
    await expectLater(openExtra(), throwsA(isA<MediaCacheFull>()));
    await lease.close();
    final extraLease = await openExtra();
    await extraLease.close();
  });

  test(
    'redirect, partial status, wrong MIME, encoding, and length fail closed',
    () async {
      for (final failure in <(int, String?, String?)>[
        (302, 'location', 'https://other.example/path'),
        (206, 'content-range', 'bytes 0-1/10'),
        (200, 'content-type', 'application/octet-stream'),
        (200, 'content-encoding', 'gzip'),
        (200, 'content-length', '999'),
      ]) {
        port.statusCode = failure.$1;
        port.badHeader = failure.$2;
        port.badValue = failure.$3;
        await expectLater(open(), throwsA(isA<ExactMediaTransportError>()));
        expect(player.initialized, 0);
      }
      expect(port.requests, hasLength(5));
    },
  );

  test(
    'wrong body digest rejects staging and a corrected retry succeeds',
    () async {
      final trPath = '/${signed.release.catalog.entries.single.trCaption.path}';
      final original = port.bytes[trPath]!;
      port.bytes[trPath] = <int>[...original]..[original.length - 1] ^= 1;
      await expectLater(open(), throwsA(isA<StateError>()));
      expect(player.initialized, 0);
      port.bytes[trPath] = original;
      final lease = await open();
      expect(player.initialized, 1);
      await lease.close();
    },
  );

  test(
    'invalid signed EN VTT blocks video without a language fallback',
    () async {
      signed = await _signedCase(
        en: 'WEBVTT\n\n00:00:04.000 --> 00:00:06.000\nLate\n',
      );
      port = _HttpPort(signed.bytes);
      session = VerifiedMediaTripletSession(
        release: signed.release,
        cache: session.cache,
        source: ExactHttpsMediaSource(port: port),
      );
      await expectLater(
        open(),
        throwsA(
          isA<WebVttContractError>().having(
            (error) => error.code,
            'code',
            'CUE_RANGE',
          ),
        ),
      );
      expect(port.requests, hasLength(2));
      expect(player.initialized, 0);
    },
  );

  test(
    'signed mixed CRLF and lone CR cannot hide an over-duration cue',
    () async {
      signed = await _signedCase(
        durationMs: 4000,
        en:
            'WEBVTT\r\n\r\n'
            '00:00:00.000 --> 00:00:04.000\r\n'
            'OK\r\r00:00:05.000 --> 00:00:06.000\rLate\r\n',
      );
      port = _HttpPort(signed.bytes);
      session = VerifiedMediaTripletSession(
        release: signed.release,
        cache: session.cache,
        source: ExactHttpsMediaSource(port: port),
      );
      await expectLater(
        open(),
        throwsA(
          isA<WebVttContractError>().having(
            (error) => error.code,
            'code',
            'LINE_ENDING',
          ),
        ),
      );
      expect(player.initialized, 0);
      expect(port.requests, hasLength(2));
    },
  );

  test('completed body with throwing abort quarantines before retry', () async {
    port.throwOnAbort = true;
    await expectLater(open(), throwsA(isA<MediaCloseUncertain>()));
    expect(session.isQuarantined, isTrue);
    final calls = port.requests.length;
    port.throwOnAbort = false;
    await expectLater(open(), throwsA(isA<MediaCloseUncertain>()));
    expect(port.requests.length, calls);
    expect(player.initialized, 0);
  });

  test(
    'unconfirmed header abort quarantines and closes a late response',
    () async {
      final pending = Completer<ExactMediaResponse>();
      port.pendingHeader = pending;
      final abort = TripletAbort();
      final attempt = open(abort: abort);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      abort.cancel();
      await expectLater(attempt, throwsA(isA<MediaCloseUncertain>()));
      expect(session.isQuarantined, isTrue);
      final calls = port.requests.length;
      await expectLater(open(), throwsA(isA<MediaCloseUncertain>()));
      expect(port.requests.length, calls);
      pending.complete(
        ExactMediaResponse(
          statusCode: 200,
          headers: const <String, List<String>>{},
          body: const Stream<List<int>>.empty(),
          abort: () {
            port.aborts++;
            throw StateError('late socket close unconfirmed');
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(port.aborts, greaterThan(0));
      expect(abort.abortUncertain, isTrue);
      await expectLater(open(), throwsA(isA<MediaCloseUncertain>()));
      expect(port.requests.length, calls);
      expect(player.initialized, 0);
    },
  );

  test(
    'stale scope during partial native initialization disposes and retries',
    () async {
      var current = true;
      player.onInitialize = () async => current = false;
      await expectLater(
        open(scopeCurrent: () => current),
        throwsA(isA<MediaCancelled>()),
      );
      expect(player.initialized, 1);
      expect(player.disposed, 1);
      current = true;
      player.onInitialize = null;
      final lease = await open(scopeCurrent: () => current);
      await lease.close();
    },
  );

  test(
    'native initialize exception disposes partial state before retry',
    () async {
      player.onInitialize = () async => throw StateError('partial create');
      await expectLater(open(), throwsA(isA<StateError>()));
      expect(player.initialized, 1);
      expect(player.disposed, 1);
      player.onInitialize = null;
      final lease = await open();
      expect(player.initialized, 2);
      await lease.close();
    },
  );

  test('idle response body aborts without native initialization', () async {
    final body = StreamController<List<int>>();
    port.bodyOverride = body.stream;
    session = VerifiedMediaTripletSession(
      release: signed.release,
      cache: session.cache,
      source: ExactHttpsMediaSource(
        port: port,
        bodyIdleTimeout: const Duration(milliseconds: 20),
      ),
    );
    await expectLater(open(), throwsA(anything));
    expect(player.initialized, 0);
    expect(port.aborts, greaterThan(0));
    await body.close();
  });

  test(
    'uncertain native close quarantines and prevents a second admission',
    () async {
      final lease = await open();
      final calls = port.requests.length;
      player.onDispose = () async => throw StateError('native close uncertain');
      await expectLater(lease.close(), throwsA(isA<MediaCloseUncertain>()));
      expect(session.isQuarantined, isTrue);
      await expectLater(open(), throwsA(isA<MediaCloseUncertain>()));
      expect(port.requests.length, calls);
    },
  );
}
