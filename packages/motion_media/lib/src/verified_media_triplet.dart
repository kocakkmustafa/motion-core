import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'bounded_webvtt.dart';
import 'exact_https_media_source.dart';
import 'release_manifest.dart';
import 'verified_media_cache.dart';

final class TripletContractError implements Exception {
  const TripletContractError(this.code);

  final String code;

  @override
  String toString() => 'TripletContractError: $code';
}

/// Native implementation must request platform video permission before create.
/// A failed or partial initialize must be safe to pass to dispose.
abstract interface class NativeTripletPlayerPort {
  Future<void> initialize(File video, File selectedCaption);
  Future<void> dispose();
}

/// Internal synthetic session. A verified catalog still grants no production
/// media availability, entitlement, or permission to instantiate a real player.
final class VerifiedMediaTripletSession {
  VerifiedMediaTripletSession({
    required this.release,
    required this.cache,
    required this.source,
  });

  final PinnedProjectionReleaseResult release;
  final VerifiedMediaCache cache;
  final ExactHttpsMediaSource source;
  bool _opening = false;
  bool _active = false;
  bool _quarantined = false;

  bool get isQuarantined => _quarantined || cache.isQuarantined;

  /// Exact tuple only. All three signed files remain pinned until close.
  /// [scopeCurrent] must be invalidated before an app lifecycle transition.
  Future<TripletPlaybackLease> open({
    required String lessonId,
    required String sceneId,
    required String variantStem,
    required String locale,
    required TripletAbort abort,
    required bool Function() scopeCurrent,
    required NativeTripletPlayerPort player,
  }) async {
    if (isQuarantined) throw const MediaCloseUncertain();
    if (_opening || _active) throw const TripletContractError('BUSY');
    final matches = release.catalog.entries.where(
      (entry) =>
          entry.lessonId == lessonId &&
          entry.sceneId == sceneId &&
          entry.variantStem == variantStem,
    );
    if (matches.length != 1) {
      throw const TripletContractError('ENTRY_NOT_FOUND');
    }
    if (locale != 'tr' && locale != 'en') {
      throw const TripletContractError('LOCALE');
    }
    _checkScope(abort, scopeCurrent);
    final entry = matches.single;
    _opening = true;
    abort.onUncertain(() => _quarantined = true);
    VerifiedPlaybackLease? tr;
    VerifiedPlaybackLease? en;
    VerifiedPlaybackLease? video;
    try {
      tr = await _openCaption(entry.trCaption, entry.durationMs, abort);
      _checkScope(abort, scopeCurrent);
      en = await _openCaption(entry.enCaption, entry.durationMs, abort);
      _checkScope(abort, scopeCurrent);
      final selectedCaption = locale == 'tr' ? tr.file : en.file;
      final videoFile = entry.video;
      video = await cache.open(
        asset: _asset(videoFile, MediaFileKind.mp4),
        source: () => source.streamFor(
          origin: release.origin,
          file: videoFile,
          kind: MediaFileKind.mp4,
          abort: abort,
        ),
        initialize: (file) async {
          _checkScope(abort, scopeCurrent);
          await player.initialize(file, selectedCaption);
          _checkScope(abort, scopeCurrent);
        },
        dispose: player.dispose,
        cancellation: abort.mediaCancellation,
      );
      _checkScope(abort, scopeCurrent);
      _active = true;
      return TripletPlaybackLease._(this, video, tr, en, abort);
    } catch (error, stackTrace) {
      abort.cancel();
      if (video != null) {
        try {
          await video.close();
        } catch (_) {
          _quarantined = true;
        }
      }
      if (error is MediaCloseUncertain ||
          error is MediaSourceCancelUncertain ||
          abort.abortUncertain) {
        _quarantined = true;
      }
      // Retain both caption pins if native or source closure is uncertain.
      if (!_quarantined && !cache.isQuarantined) {
        try {
          await en?.close();
          await tr?.close();
        } catch (_) {
          _quarantined = true;
        }
      }
      if (_quarantined) throw const MediaCloseUncertain();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _opening = false;
    }
  }

  Future<VerifiedPlaybackLease> _openCaption(
    ReleaseFileExpectation file,
    int durationMs,
    TripletAbort abort,
  ) async {
    final lease = await cache.open(
      asset: _asset(file, MediaFileKind.vtt),
      source: () => source.streamFor(
        origin: release.origin,
        file: file,
        kind: MediaFileKind.vtt,
        abort: abort,
      ),
      initialize: (_) async {},
      dispose: () async {},
      cancellation: abort.mediaCancellation,
    );
    try {
      await BoundedWebVtt.validate(lease.file, durationMs: durationMs);
      return lease;
    } catch (_) {
      await lease.close();
      rethrow;
    }
  }

  static VerifiedMediaAsset _asset(
    ReleaseFileExpectation file,
    MediaFileKind kind,
  ) => VerifiedMediaAsset(
    key: sha256.convert(utf8.encode(file.path)).toString(),
    kind: kind,
    expectedBytes: file.bytes,
    expectedSha256: file.sha256,
  );

  static void _checkScope(TripletAbort abort, bool Function() scopeCurrent) {
    if (abort.isCancelled || !scopeCurrent()) throw const MediaCancelled();
  }
}

/// Close native video first; only then release the two caption pins.
final class TripletPlaybackLease {
  TripletPlaybackLease._(
    this._owner,
    this._video,
    this._tr,
    this._en,
    this.abort,
  );

  final VerifiedMediaTripletSession _owner;
  final VerifiedPlaybackLease _video;
  final VerifiedPlaybackLease _tr;
  final VerifiedPlaybackLease _en;
  final TripletAbort abort;
  Future<void>? _closeFuture;

  File get videoFile => _video.file;
  File get trCaptionFile => _tr.file;
  File get enCaptionFile => _en.file;

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    abort.cancel();
    try {
      await _video.close();
    } catch (_) {
      _owner._quarantined = true;
      // Keep both caption leases pinned while native may still read them.
      throw const MediaCloseUncertain();
    }
    try {
      await _en.close();
      await _tr.close();
      _owner._active = false;
    } catch (_) {
      _owner._quarantined = true;
      throw const MediaCloseUncertain();
    }
  }
}
