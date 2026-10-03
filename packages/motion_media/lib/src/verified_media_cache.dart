import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The byte caps are independent of a remote response's claimed MIME type.
enum MediaFileKind {
  mp4('mp4', 64 * 1024 * 1024),
  vtt('vtt', 1024 * 1024);

  const MediaFileKind(this.extension, this.maxBytes);

  final String extension;
  final int maxBytes;
}

/// Expected metadata must come from a separately authenticated release root.
class VerifiedMediaAsset {
  VerifiedMediaAsset({
    required this.key,
    required this.kind,
    required this.expectedBytes,
    required this.expectedSha256,
  }) {
    if (!_keyPattern.hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'Expected one safe path component');
    }
    if (!_shaPattern.hasMatch(expectedSha256)) {
      throw ArgumentError.value(
        expectedSha256,
        'expectedSha256',
        'Expected a lowercase 64-digit SHA-256',
      );
    }
    if (expectedBytes <= 0 || expectedBytes > kind.maxBytes) {
      throw ArgumentError.value(
        expectedBytes,
        'expectedBytes',
        'Outside the positive ${kind.extension} byte cap',
      );
    }
  }

  static final RegExp _keyPattern = RegExp(r'^[A-Za-z0-9_-]{1,80}$');
  static final RegExp _shaPattern = RegExp(r'^[0-9a-f]{64}$');

  final String key;
  final MediaFileKind kind;
  final int expectedBytes;
  final String expectedSha256;

  String get fileName =>
      '${kind.extension}--$key--$expectedSha256.${kind.extension}';
}

/// A caller-visible observation of one corrupt final file.
///
/// The receipt is bound to the cache instance and exact expected asset. It is
/// not a release approval or a substitute for a trusted expected SHA-256.
class CorruptMediaReceipt {
  const CorruptMediaReceipt._({
    required VerifiedMediaCache owner,
    required this.fileName,
    required this.expectedBytes,
    required this.expectedSha256,
    required this.observedBytes,
    required this.observedSha256,
    required this.observedModified,
    required this.observedChanged,
  }) : _owner = owner;

  final VerifiedMediaCache _owner;
  final String fileName;
  final int expectedBytes;
  final String expectedSha256;
  final int observedBytes;
  final String observedSha256;
  final DateTime observedModified;
  final DateTime observedChanged;
}

class MediaCancelled implements Exception {
  const MediaCancelled();

  @override
  String toString() => 'MediaCancelled: media acquisition was cancelled';
}

class MediaCacheFull implements Exception {
  const MediaCacheFull();

  @override
  String toString() => 'MediaCacheFull: all evictable space is exhausted';
}

/// An uncertain native close is sticky for this cache instance.
class MediaCloseUncertain implements Exception {
  const MediaCloseUncertain();

  @override
  String toString() =>
      'MediaCloseUncertain: native media closure was not confirmed';
}

/// The upstream stream did not confirm cancellation; no new cache work runs.
class MediaSourceCancelUncertain implements Exception {
  const MediaSourceCancelUncertain();

  @override
  String toString() =>
      'MediaSourceCancelUncertain: source cancellation was not confirmed';
}

/// Diagnostic checkpoints for deterministic cancellation tests.
///
/// The observer may delay or reject admission but cannot skip verification.
/// Production callers should leave the observer null.
enum MediaAdmissionCheckpoint { afterVerification, afterEviction, afterRename }

/// Can stop an idle stream without waiting for its next byte chunk.
class MediaCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void _add(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void _remove(void Function() listener) => _listeners.remove(listener);
}

/// A local, single-process cache rooted in an existing app-private directory.
///
/// Every [open] verifies an existing file again before native initialization.
/// Native disposal must close even a partially initialized player. This pure
/// Dart package cannot defend against a hostile *other process* swapping a
/// checked path after the check; the host app must own the private directory.
class VerifiedMediaCache {
  VerifiedMediaCache({
    required this.root,
    this.maxCacheBytes = defaultMaxCacheBytes,
    this.closeTimeout = const Duration(seconds: 15),
    this.admissionObserver,
  }) {
    if (maxCacheBytes <= 0 || maxCacheBytes > defaultMaxCacheBytes) {
      throw ArgumentError.value(maxCacheBytes, 'maxCacheBytes');
    }
    if (closeTimeout <= Duration.zero ||
        closeTimeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(closeTimeout, 'closeTimeout');
    }
  }

  static const int defaultMaxCacheBytes = 256 * 1024 * 1024;
  static final Map<String, VerifiedMediaCache> _rootOwners =
      <String, VerifiedMediaCache>{};
  static final RegExp _cacheNamePattern = RegExp(
    r'^(mp4|vtt)--[A-Za-z0-9_-]{1,80}--[0-9a-f]{64}\.(mp4|vtt)$',
  );

  final Directory root;
  final int maxCacheBytes;
  final Duration closeTimeout;
  final Future<void> Function(MediaAdmissionCheckpoint)? admissionObserver;
  Future<void> _tail = Future<void>.value();
  final Map<String, int> _pins = <String, int>{};
  String? _canonicalRoot;
  String? _activeStage;
  bool _quarantined = false;
  int _closingCount = 0;

  bool get isQuarantined => _quarantined;

  /// Observes an existing corrupt final file without deleting or repairing it.
  ///
  /// Returns null if the exact expected file is absent or still healthy. Links
  /// and directories always fail closed. The app must explicitly pass the
  /// returned receipt to [invalidateCorrupt] before a fresh [open] can fetch.
  Future<CorruptMediaReceipt?> inspectCorrupt(VerifiedMediaAsset asset) =>
      _serial(() async {
        _requireUsable();
        await _ensureRoot();
        final file = File(_childPath(asset.fileName));
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type == FileSystemEntityType.notFound) return null;
        if (type != FileSystemEntityType.file) {
          throw StateError('Cache target is not a regular file');
        }
        final observed = await _fingerprint(file);
        if (observed.bytes == asset.expectedBytes &&
            observed.sha256 == asset.expectedSha256) {
          return null;
        }
        return CorruptMediaReceipt._(
          owner: this,
          fileName: asset.fileName,
          expectedBytes: asset.expectedBytes,
          expectedSha256: asset.expectedSha256,
          observedBytes: observed.bytes,
          observedSha256: observed.sha256,
          observedModified: observed.modified,
          observedChanged: observed.changed,
        );
      });

  /// Deletes only the same corrupt, unpinned file observed by [inspectCorrupt].
  ///
  /// This method never downloads. A subsequent [open] still verifies exact
  /// bytes and SHA-256 before its new file is visible to native playback.
  Future<void> invalidateCorrupt(
    VerifiedMediaAsset asset,
    CorruptMediaReceipt receipt,
  ) => _serial(() async {
    _requireUsable();
    await _ensureRoot();
    if (!identical(receipt._owner, this) ||
        receipt.fileName != asset.fileName ||
        receipt.expectedBytes != asset.expectedBytes ||
        receipt.expectedSha256 != asset.expectedSha256) {
      throw ArgumentError('Receipt does not match this exact cache asset');
    }
    final file = File(_childPath(asset.fileName));
    if ((_pins[file.path] ?? 0) != 0) {
      throw StateError('A live lease pins this cache file');
    }
    await _verifyDirectRegularFile(file);
    final observed = await _fingerprint(file);
    if (observed.bytes == asset.expectedBytes &&
        observed.sha256 == asset.expectedSha256) {
      throw StateError('A healthy cache file cannot be invalidated');
    }
    if (observed.bytes != receipt.observedBytes ||
        observed.sha256 != receipt.observedSha256 ||
        observed.modified != receipt.observedModified ||
        observed.changed != receipt.observedChanged) {
      throw StateError('Corrupt cache file changed after inspection');
    }
    await _verifyDirectRegularFile(file);
    final finalStat = await file.stat();
    if (finalStat.size != receipt.observedBytes ||
        finalStat.modified != receipt.observedModified ||
        finalStat.changed != receipt.observedChanged ||
        (_pins[file.path] ?? 0) != 0) {
      throw StateError('Corrupt cache file changed before invalidation');
    }
    await file.delete();
  });

  /// Opens only an exact verified file, with its pin installed before [initialize].
  ///
  /// [source] is invoked only on cache miss and may be backed by any stream.
  /// The caller must enforce release identity, transport policy and native
  /// player behavior separately. [dispose] must close partial initialization.
  Future<VerifiedPlaybackLease> open({
    required VerifiedMediaAsset asset,
    required Stream<List<int>> Function() source,
    required Future<void> Function(File verifiedFile) initialize,
    required Future<void> Function() dispose,
    MediaCancellation? cancellation,
  }) async {
    final acquisition = await _serial(() async {
      _requireUsable();
      _checkCancellation(cancellation);
      await _ensureRoot();
      if (asset.expectedBytes > maxCacheBytes) {
        throw const MediaCacheFull();
      }
      final target = File(_childPath(asset.fileName));
      var created = false;
      try {
        final type = await FileSystemEntity.type(
          target.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          await _verifyFile(target, asset);
        } else if (type == FileSystemEntityType.notFound) {
          await _admit(target, asset, source, cancellation);
          created = true;
        } else {
          throw StateError('Cache target is not a regular file');
        }
        _requireUsable();
        _checkCancellation(cancellation);
        await target.setLastModified(DateTime.now().toUtc());
        _checkCancellation(cancellation);
        _pins.update(target.path, (count) => count + 1, ifAbsent: () => 1);
        return (file: target, created: created);
      } catch (error, stackTrace) {
        if (created) {
          try {
            await _deletePublished(target);
          } catch (_) {
            _quarantined = true;
            throw StateError('Failed admission could not be rolled back');
          }
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    final file = acquisition.file;

    // A late cancellation before native initialization has no native state.
    if (cancellation?.isCancelled ?? false) {
      _release(file.path);
      if (acquisition.created) await _removeCreatedIfUnpinned(file);
      throw const MediaCancelled();
    }
    // A close may have begun while acquisition was awaiting the serial gate.
    if (_quarantined || _closingCount != 0) {
      _release(file.path);
      throw const MediaCloseUncertain();
    }
    try {
      await initialize(file);
    } catch (error, stackTrace) {
      await _disposeOrQuarantine(dispose, file.path);
      Error.throwWithStackTrace(error, stackTrace);
    }
    // Another lease may have entered quarantine while initialization waited.
    if (_quarantined || _closingCount != 0) {
      await _disposeOrQuarantine(dispose, file.path);
      throw const MediaCloseUncertain();
    }
    if (cancellation?.isCancelled ?? false) {
      await _disposeOrQuarantine(dispose, file.path);
      throw const MediaCancelled();
    }
    return VerifiedPlaybackLease._(this, file, dispose);
  }

  Future<void> _disposeOrQuarantine(
    Future<void> Function() dispose,
    String path,
  ) async {
    _closingCount++;
    try {
      await dispose().timeout(closeTimeout);
      _release(path);
    } catch (_) {
      _quarantined = true;
      throw const MediaCloseUncertain();
    } finally {
      _closingCount--;
    }
  }

  void _requireUsable() {
    if (_quarantined || _closingCount != 0) {
      throw const MediaCloseUncertain();
    }
  }

  void _checkCancellation(MediaCancellation? cancellation) {
    if (cancellation?.isCancelled ?? false) throw const MediaCancelled();
  }

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  Future<void> _ensureRoot() async {
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw StateError('Cache root must be an existing real directory');
    }
    final canonical = await root.resolveSymbolicLinks();
    final owner = _rootOwners[canonical];
    if (owner != null && !identical(owner, this)) {
      throw StateError('Cache root is already owned by another instance');
    }
    if (_canonicalRoot == null) {
      _canonicalRoot = canonical;
      _rootOwners[canonical] = this;
    } else if (_canonicalRoot != canonical) {
      throw StateError('Cache root changed after initialization');
    }
  }

  String _childPath(String name) =>
      '${root.path}${Platform.pathSeparator}$name';

  Future<void> _preflightForAdmission() async {
    await _ensureRoot();
    var used = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('Orphan stage, link, or directory in media cache');
      }
      final match = _cacheNamePattern.firstMatch(entity.uri.pathSegments.last);
      if (match == null || match.group(1) != match.group(2)) {
        throw StateError('Unexpected file in media cache');
      }
      final file = File(entity.path);
      await _verifyDirectRegularFile(file);
      final size = await file.length();
      final cap = match.group(1) == 'mp4'
          ? MediaFileKind.mp4.maxBytes
          : MediaFileKind.vtt.maxBytes;
      if (size <= 0 || size > cap) {
        throw StateError('Cache file violates its kind byte cap');
      }
      used += size;
      if (used > maxCacheBytes) throw const MediaCacheFull();
    }
  }

  Future<void> _verifyDirectRegularFile(File file) async {
    await _ensureRoot();
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Cache file is missing or a link');
    }
    if (await file.parent.resolveSymbolicLinks() != _canonicalRoot) {
      throw StateError('Cache file is outside the root');
    }
  }

  Future<void> _verifyFile(File file, VerifiedMediaAsset asset) async {
    await _verifyDirectRegularFile(file);
    if (await file.length() != asset.expectedBytes) {
      throw StateError('Cached media byte count differs from release metadata');
    }
    if ((await sha256.bind(file.openRead()).first).toString() !=
        asset.expectedSha256) {
      throw StateError('Cached media SHA-256 differs from release metadata');
    }
  }

  Future<_FileFingerprint> _fingerprint(File file) async {
    await _verifyDirectRegularFile(file);
    final before = await file.stat();
    final digest = (await sha256.bind(file.openRead()).first).toString();
    await _verifyDirectRegularFile(file);
    final after = await file.stat();
    if (before.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw StateError('Cache file changed during inspection');
    }
    return _FileFingerprint(
      before.size,
      digest,
      before.modified,
      before.changed,
    );
  }

  Future<void> _admit(
    File target,
    VerifiedMediaAsset asset,
    Stream<List<int>> Function() source,
    MediaCancellation? cancellation,
  ) async {
    await _preflightForAdmission();
    _checkCancellation(cancellation);
    final stage = await root.createTemp('.motion-stage-');
    _activeStage = stage.path;
    var published = false;
    final stagedFile = File(
      '${stage.path}${Platform.pathSeparator}payload.${asset.kind.extension}',
    );
    try {
      if (await stage.parent.resolveSymbolicLinks() != _canonicalRoot) {
        throw StateError('Staging directory is outside the cache root');
      }
      await stagedFile.create(exclusive: true);
      await _copyExact(stagedFile, asset, source, cancellation);
      _checkCancellation(cancellation);
      await _verifyFileInStage(stagedFile, asset);
      await _admissionCheckpoint(
        MediaAdmissionCheckpoint.afterVerification,
        cancellation,
      );
      await _evictFor(asset.expectedBytes, cancellation);
      await _admissionCheckpoint(
        MediaAdmissionCheckpoint.afterEviction,
        cancellation,
      );
      await _ensureRoot();
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Cache target appeared during admission');
      }
      _checkCancellation(cancellation);
      await stagedFile.rename(target.path);
      published = true;
      await _admissionCheckpoint(
        MediaAdmissionCheckpoint.afterRename,
        cancellation,
      );
    } catch (error, stackTrace) {
      if (published) {
        try {
          await _deletePublished(target);
        } catch (_) {
          _quarantined = true;
          throw StateError('Published canceled media could not be removed');
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _activeStage = null;
      if (await stagedFile.exists()) await stagedFile.delete();
      await stage.delete();
    }
  }

  Future<void> _admissionCheckpoint(
    MediaAdmissionCheckpoint phase,
    MediaCancellation? cancellation,
  ) async {
    await admissionObserver?.call(phase);
    _checkCancellation(cancellation);
  }

  Future<void> _deletePublished(File target) async {
    await _verifyDirectRegularFile(target);
    await target.delete();
  }

  Future<void> _removeCreatedIfUnpinned(File target) => _serial(() async {
    if ((_pins[target.path] ?? 0) != 0) return;
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    try {
      await _deletePublished(target);
    } catch (_) {
      _quarantined = true;
      throw StateError('Canceled media could not be rolled back');
    }
  });

  Future<void> _copyExact(
    File stagedFile,
    VerifiedMediaAsset asset,
    Stream<List<int>> Function() source,
    MediaCancellation? cancellation,
  ) async {
    _checkCancellation(cancellation);
    final output = await stagedFile.open(mode: FileMode.writeOnly);
    StreamIterator<List<int>>? iterator;
    Future<void>? cancelFuture;
    Object? cancelError;
    var received = 0;
    void stop() {
      if (cancelFuture != null) return;
      final active = iterator;
      if (active == null) return;
      try {
        // Attach the error handler immediately, then await this same Future
        // in finally. An upstream onCancel error must never be unobserved.
        cancelFuture = active.cancel().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) => cancelError = error,
        );
      } catch (error) {
        cancelError = error;
        cancelFuture = Future<void>.value();
      }
    }

    try {
      final active = StreamIterator<List<int>>(source());
      iterator = active;
      cancellation?._add(stop);
      while (await active.moveNext()) {
        _checkCancellation(cancellation);
        final chunk = active.current;
        if (chunk.length > asset.expectedBytes - received ||
            chunk.length > asset.kind.maxBytes - received) {
          throw StateError('Media stream exceeded its declared byte count');
        }
        // Snapshot validated values so caller-owned lists cannot change during
        // the asynchronous write. Uint8List conversion alone would truncate.
        final bytes = Uint8List(chunk.length);
        for (var i = 0; i < bytes.length; i++) {
          final value = chunk[i];
          if (value < 0 || value > 255) {
            throw StateError('Media stream contained a non-byte integer');
          }
          bytes[i] = value;
        }
        await output.writeFrom(bytes);
        received += bytes.length;
      }
      _checkCancellation(cancellation);
      if (received != asset.expectedBytes) {
        throw StateError('Media stream ended before its declared byte count');
      }
      await output.flush();
    } finally {
      cancellation?._remove(stop);
      stop();
      try {
        final pendingCancellation = cancelFuture;
        if (pendingCancellation != null) {
          await pendingCancellation.timeout(closeTimeout);
        }
      } catch (error) {
        cancelError ??= error;
      } finally {
        await output.close();
      }
      if (cancelError != null) {
        _quarantined = true;
        throw const MediaSourceCancelUncertain();
      }
    }
  }

  Future<void> _verifyFileInStage(
    File stagedFile,
    VerifiedMediaAsset asset,
  ) async {
    if (await FileSystemEntity.type(stagedFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Staging file is no longer regular');
    }
    if (await stagedFile.length() != asset.expectedBytes ||
        (await sha256.bind(stagedFile.openRead()).first).toString() !=
            asset.expectedSha256) {
      throw StateError('Staged media failed byte or SHA-256 verification');
    }
  }

  Future<void> _evictFor(
    int incomingBytes,
    MediaCancellation? cancellation,
  ) async {
    _checkCancellation(cancellation);
    final candidates = <_CacheEntry>[];
    var used = 0;
    await for (final entity in root.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory &&
          entity.path == _activeStage) {
        continue;
      }
      if (type != FileSystemEntityType.file) {
        throw StateError('Unexpected link or directory inside media cache');
      }
      final name = entity.uri.pathSegments.last;
      final match = _cacheNamePattern.firstMatch(name);
      if (match == null || match.group(1) != match.group(2)) {
        throw StateError('Unexpected file inside media cache');
      }
      final file = File(entity.path);
      await _verifyDirectRegularFile(file);
      final stat = await file.stat();
      final cap = match.group(1) == 'mp4'
          ? MediaFileKind.mp4.maxBytes
          : MediaFileKind.vtt.maxBytes;
      if (stat.size <= 0 || stat.size > cap) {
        throw StateError('Cache file violates its kind byte cap');
      }
      used += stat.size;
      if ((_pins[file.path] ?? 0) == 0) {
        candidates.add(_CacheEntry(file, stat.size, stat.modified));
      }
    }
    candidates.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final entry in candidates) {
      if (used + incomingBytes <= maxCacheBytes) break;
      _checkCancellation(cancellation);
      await _verifyDirectRegularFile(entry.file);
      _checkCancellation(cancellation);
      await entry.file.delete();
      used -= entry.bytes;
    }
    _checkCancellation(cancellation);
    if (used + incomingBytes > maxCacheBytes) throw const MediaCacheFull();
  }

  void _release(String path) {
    final count = _pins[path];
    if (count == null || count <= 0) {
      _quarantined = true;
      throw const MediaCloseUncertain();
    }
    if (count == 1) {
      _pins.remove(path);
    } else {
      _pins[path] = count - 1;
    }
  }
}

class _CacheEntry {
  const _CacheEntry(this.file, this.bytes, this.lastUsed);

  final File file;
  final int bytes;
  final DateTime lastUsed;
}

class _FileFingerprint {
  const _FileFingerprint(this.bytes, this.sha256, this.modified, this.changed);

  final int bytes;
  final String sha256;
  final DateTime modified;
  final DateTime changed;
}

/// The native player owns this verified file until [close] confirms disposal.
class VerifiedPlaybackLease {
  VerifiedPlaybackLease._(this._cache, this.file, this._dispose);

  final VerifiedMediaCache _cache;
  final File file;
  final Future<void> Function() _dispose;
  Future<void>? _closeFuture;

  Future<void> close() =>
      _closeFuture ??= _cache._disposeOrQuarantine(_dispose, file.path);
}
