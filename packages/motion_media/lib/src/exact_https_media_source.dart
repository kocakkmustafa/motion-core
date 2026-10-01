import 'dart:async';
import 'dart:io';

import 'release_manifest.dart';
import 'verified_media_cache.dart';

/// Internal structural transport error. It never grants release authority.
final class ExactMediaTransportError implements Exception {
  const ExactMediaTransportError(this.code);

  final String code;

  @override
  String toString() => 'ExactMediaTransportError: $code';
}

/// Cancels both cache admission and an HTTP request waiting for headers/body.
final class TripletAbort {
  final MediaCancellation mediaCancellation = MediaCancellation();
  final Set<void Function()> _listeners = <void Function()>{};
  final Set<void Function()> _uncertainListeners = <void Function()>{};
  final Completer<void> _cancelledSignal = Completer<void>();
  bool _cancelled = false;
  bool _abortUncertain = false;
  int _pendingHeaders = 0;

  bool get isCancelled => _cancelled;
  bool get abortUncertain => _abortUncertain;
  Future<void> get whenCancelled => _cancelledSignal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    // A header future that has not settled cannot confirm socket closure.
    if (_pendingHeaders != 0) markUncertain();
    try {
      mediaCancellation.cancel();
    } catch (_) {
      markUncertain();
    }
    _cancelledSignal.complete();
    for (final listener in _listeners.toList()) {
      try {
        listener();
      } catch (_) {
        markUncertain();
      }
    }
    _listeners.clear();
  }

  /// Returns a remover; a late registration is aborted immediately.
  void Function() register(void Function() abort) {
    if (_cancelled) {
      try {
        abort();
      } catch (_) {
        markUncertain();
      }
      return () {};
    }
    _listeners.add(abort);
    return () => _listeners.remove(abort);
  }

  /// A late abort failure must still quarantine the session that started it.
  void onUncertain(void Function() listener) {
    if (_abortUncertain) {
      listener();
    } else {
      _uncertainListeners.add(listener);
    }
  }

  void markUncertain() {
    if (_abortUncertain) return;
    _abortUncertain = true;
    for (final listener in _uncertainListeners.toList()) {
      try {
        listener();
      } catch (_) {
        // A diagnostic callback cannot turn uncertainty into a clean close.
      }
    }
    _uncertainListeners.clear();
  }

  void headerStarted() {
    _pendingHeaders++;
    if (_cancelled) markUncertain();
  }

  void headerSettled() {
    if (_pendingHeaders > 0) _pendingHeaders--;
  }
}

/// A response port makes malformed headers and cancellation testable offline.
abstract interface class ExactMediaHttpPort {
  Future<ExactMediaResponse> get(Uri uri, TripletAbort abort);
}

final class ExactMediaResponse {
  const ExactMediaResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.abort,
  });

  final int statusCode;
  final Map<String, List<String>> headers;
  final Stream<List<int>> body;
  final void Function() abort;
}

/// Uses system TLS trust. Each request has its own client for exact abort.
final class DartIoExactMediaHttpPort implements ExactMediaHttpPort {
  const DartIoExactMediaHttpPort();

  @override
  Future<ExactMediaResponse> get(Uri uri, TripletAbort abort) async {
    if (uri.scheme != 'https' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ExactMediaTransportError('URI_POLICY');
    }
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);
    HttpClientRequest? request;
    var stopped = false;
    void Function() unregister = () {};
    void stop() {
      if (stopped) return;
      stopped = true;
      var closeFailed = false;
      try {
        request?.abort();
      } catch (_) {
        closeFailed = true;
      } finally {
        try {
          client.close(force: true);
        } catch (_) {
          closeFailed = true;
        }
        unregister();
      }
      if (closeFailed) {
        abort.markUncertain();
        throw const MediaSourceCancelUncertain();
      }
    }

    unregister = abort.register(stop);
    try {
      if (abort.isCancelled) throw const MediaCancelled();
      request = await client.getUrl(uri);
      if (abort.isCancelled) throw const MediaCancelled();
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (abort.isCancelled) throw const MediaCancelled();
      final headers = <String, List<String>>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = List<String>.unmodifiable(values);
      });
      final body = () async* {
        try {
          await for (final chunk in response) {
            yield chunk;
          }
        } finally {
          stop();
        }
      }();
      return ExactMediaResponse(
        statusCode: response.statusCode,
        headers: headers,
        body: body,
        abort: stop,
      );
    } catch (_) {
      stop();
      rethrow;
    }
  }
}

/// Builds the request only from a structurally verified origin and file.
final class ExactHttpsMediaSource {
  const ExactHttpsMediaSource({
    required this.port,
    this.headerTimeout = const Duration(seconds: 20),
    this.bodyIdleTimeout = const Duration(seconds: 30),
    this.totalTimeout = const Duration(minutes: 5),
  });

  final ExactMediaHttpPort port;
  final Duration headerTimeout;
  final Duration bodyIdleTimeout;
  final Duration totalTimeout;

  Uri uriFor(
    VerifiedReleaseOrigin origin,
    ReleaseFileExpectation file,
    MediaFileKind kind,
  ) {
    final path =
        'motion-media/v1/${origin.appId}/'
        '${file.sha256}.${kind.extension}';
    final mime = kind == MediaFileKind.mp4 ? 'video/mp4' : 'text/vtt';
    if (file.path != path || file.mime != mime) {
      throw const ExactMediaTransportError('FILE_EXPECTATION');
    }
    final uri = Uri(
      scheme: 'https',
      host: origin.assetHost,
      port: 443,
      path: '/$path',
    );
    if (uri.scheme != 'https' ||
        uri.host != origin.assetHost ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != '/$path') {
      throw const ExactMediaTransportError('URI_POLICY');
    }
    return uri;
  }

  Stream<List<int>> streamFor({
    required VerifiedReleaseOrigin origin,
    required ReleaseFileExpectation file,
    required MediaFileKind kind,
    required TripletAbort abort,
  }) async* {
    final uri = uriFor(origin, file, kind);
    if (abort.isCancelled) throw const MediaCancelled();
    final deadline = Timer(totalTimeout, abort.cancel);
    try {
      abort.headerStarted();
      late Future<ExactMediaResponse> pending;
      try {
        pending = port.get(uri, abort);
      } catch (_) {
        abort.headerSettled();
        rethrow;
      }
      // A response arriving after cancellation must not keep its socket alive.
      unawaited(
        pending.then<void>(
          (response) {
            try {
              if (abort.isCancelled) response.abort();
            } catch (_) {
              abort.markUncertain();
            } finally {
              abort.headerSettled();
            }
          },
          onError: (Object _, StackTrace __) {
            abort.headerSettled();
          },
        ),
      );
      final boundedPending = pending.timeout(
        headerTimeout,
        onTimeout: () {
          abort.cancel();
          throw const ExactMediaTransportError('HEADER_TIMEOUT');
        },
      );
      final response =
          await Future.any<ExactMediaResponse>(<Future<ExactMediaResponse>>[
            boundedPending,
            abort.whenCancelled.then((_) => throw const MediaCancelled()),
          ]);
      final unregister = abort.register(response.abort);
      try {
        if (abort.isCancelled) throw const MediaCancelled();
        _checkResponse(response, file);
        await for (final chunk in response.body.timeout(
          bodyIdleTimeout,
          onTimeout: (sink) {
            abort.cancel();
            sink.addError(const ExactMediaTransportError('BODY_IDLE'));
            sink.close();
          },
        )) {
          if (abort.isCancelled) throw const MediaCancelled();
          yield chunk;
        }
      } finally {
        unregister();
        try {
          response.abort();
        } catch (_) {
          abort.markUncertain();
          throw const MediaSourceCancelUncertain();
        }
      }
    } finally {
      deadline.cancel();
    }
  }

  static void _checkResponse(
    ExactMediaResponse response,
    ReleaseFileExpectation file,
  ) {
    if (response.statusCode != HttpStatus.ok) {
      throw const ExactMediaTransportError('HTTP_STATUS');
    }
    String? single(String name) {
      final values = <String>[
        for (final entry in response.headers.entries)
          if (entry.key.toLowerCase() == name) ...entry.value,
      ];
      if (values.isEmpty) return null;
      if (values.length != 1) {
        throw const ExactMediaTransportError('HTTP_HEADERS');
      }
      return values.single.trim();
    }

    if (single('location') != null || single('content-range') != null) {
      throw const ExactMediaTransportError('HTTP_HEADERS');
    }
    if (single('content-type')?.toLowerCase() != file.mime) {
      throw const ExactMediaTransportError('HTTP_MIME');
    }
    final encoding = single('content-encoding');
    if (encoding != null && encoding.toLowerCase() != 'identity') {
      throw const ExactMediaTransportError('HTTP_ENCODING');
    }
    final length = single('content-length');
    if (length != null &&
        (!RegExp(r'^[0-9]+$').hasMatch(length) ||
            int.tryParse(length) != file.bytes)) {
      throw const ExactMediaTransportError('HTTP_LENGTH');
    }
  }
}
