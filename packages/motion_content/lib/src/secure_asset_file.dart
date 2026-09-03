import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'content_error.dart';
import 'path_policy.dart';

/// A build-time, descriptor-bound asset opened beneath a trusted physical root.
///
/// POSIX `openat` walks every content-path component from an already-open root
/// descriptor. `O_NOFOLLOW` prevents a symlink swap from redirecting either an
/// intermediate directory or the final file between validation and use.
/// Unsupported hosts fail closed; runtime asset access remains pure Dart via
/// [ContentAssetReader].
final class SecureAssetFile {
  SecureAssetFile._(this._bindings, this._descriptor, this.length);

  final _PosixBindings _bindings;
  int _descriptor;
  final int length;

  /// Opens [logicalPath] without following any of its path components.
  ///
  /// [beforeFinalOpenForTesting] is intentionally available only from this
  /// non-barrel `src/` library so the race boundary can be tested
  /// deterministically. Production callers must leave it null.
  static SecureAssetFile open({
    required String rootPath,
    required String logicalPath,
    required String contentId,
    void Function()? beforeFinalOpenForTesting,
  }) {
    PathPolicy.validate(logicalPath);
    final bindings = _PosixBindings.current(contentId);
    final logicalSegments = logicalPath.split('/');
    if (_hasUnsafeRootSyntax(rootPath)) {
      failContent(ContentErrorCode.unsafePath, contentId: contentId);
    }

    // O_NOFOLLOW applies atomically to the supplied root's final component.
    // Ancestor symlinks remain valid host filesystem structure (for example,
    // macOS /var -> /private/var) and are outside the content-root boundary.
    var directoryDescriptor = bindings.openDirectory(rootPath);
    var fileDescriptor = -1;
    var succeeded = false;
    try {
      if (directoryDescriptor < 0) {
        failContent(ContentErrorCode.io, contentId: contentId);
      }
      for (final segment in logicalSegments.take(logicalSegments.length - 1)) {
        final next = bindings.openDirectoryAt(directoryDescriptor, segment);
        if (next < 0) {
          failContent(ContentErrorCode.unsafePath, contentId: contentId);
        }
        bindings.close(directoryDescriptor);
        directoryDescriptor = next;
      }

      beforeFinalOpenForTesting?.call();
      fileDescriptor = bindings.openFileAt(
        directoryDescriptor,
        logicalSegments.last,
      );
      if (fileDescriptor < 0) {
        failContent(ContentErrorCode.unsafePath, contentId: contentId);
      }
      // This same-descriptor seek is also the build boundary's non-regular
      // fail-closed gate: an unprivileged race to a FIFO or socket cannot block
      // (O_NONBLOCK above) and cannot pass lseek before any bytes are consumed.
      // The preceding pathname check separately requires a regular file in the
      // stable case, without relying on a platform-specific `struct stat` ABI.
      final length = bindings.seekToEnd(fileDescriptor);
      if (length < 0 || !bindings.seekToStart(fileDescriptor)) {
        failContent(ContentErrorCode.unsafePath, contentId: contentId);
      }
      succeeded = true;
      return SecureAssetFile._(bindings, fileDescriptor, length);
    } finally {
      if (directoryDescriptor >= 0) bindings.close(directoryDescriptor);
      if (!succeeded && fileDescriptor >= 0) bindings.close(fileDescriptor);
    }
  }

  Uint8List readBounded(int maximumBytes, String contentId) {
    if (length > maximumBytes) {
      failContent(ContentErrorCode.resourceLimit, contentId: contentId);
    }
    if (_descriptor < 0) {
      failContent(ContentErrorCode.io, contentId: contentId);
    }

    const chunkSize = 64 * 1024;
    final buffer = _bindings.allocate(chunkSize, contentId);
    final builder = BytesBuilder(copy: false);
    try {
      while (builder.length <= maximumBytes) {
        final remaining = maximumBytes + 1 - builder.length;
        final count = _bindings.read(
          _descriptor,
          buffer,
          math.min(chunkSize, remaining),
        );
        if (count < 0) {
          failContent(ContentErrorCode.io, contentId: contentId);
        }
        if (count == 0) break;
        builder.add(Uint8List.fromList(buffer.asTypedList(count)));
      }
    } finally {
      _bindings.free(buffer);
    }
    final bytes = builder.takeBytes();
    if (bytes.length > maximumBytes) {
      failContent(ContentErrorCode.resourceLimit, contentId: contentId);
    }
    if (bytes.length != length) {
      failContent(ContentErrorCode.sizeMismatch, contentId: contentId);
    }
    return bytes;
  }

  void close() {
    final descriptor = _descriptor;
    if (descriptor < 0) return;
    _descriptor = -1;
    _bindings.close(descriptor);
  }
}

bool _hasUnsafeRootSyntax(String rootPath) {
  if (!rootPath.startsWith('/') ||
      rootPath.contains('\u0000') ||
      (rootPath.length > 1 && rootPath.endsWith('/'))) {
    return true;
  }
  if (rootPath == '/') return false;
  return rootPath
      .split('/')
      .skip(1)
      .any((segment) => segment.isEmpty || segment == '.' || segment == '..');
}

typedef _OpenNative = Int32 Function(Pointer<Uint8>, Int32);
typedef _OpenDart = int Function(Pointer<Uint8>, int);
typedef _OpenAtNative = Int32 Function(Int32, Pointer<Uint8>, Int32);
typedef _OpenAtDart = int Function(int, Pointer<Uint8>, int);
typedef _ReadNative = IntPtr Function(Int32, Pointer<Void>, UintPtr);
typedef _ReadDart = int Function(int, Pointer<Void>, int);
typedef _SeekNative = Int64 Function(Int32, Int64, Int32);
typedef _SeekDart = int Function(int, int, int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);
typedef _MallocNative = Pointer<Void> Function(UintPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

final class _PosixBindings {
  _PosixBindings._()
    : _library = DynamicLibrary.process(),
      _flags = _PosixOpenFlags.current() {
    _open = _library.lookupFunction<_OpenNative, _OpenDart>('open');
    _openAt = _library.lookupFunction<_OpenAtNative, _OpenAtDart>('openat');
    _read = _library.lookupFunction<_ReadNative, _ReadDart>('read');
    _seek = _library.lookupFunction<_SeekNative, _SeekDart>('lseek');
    _close = _library.lookupFunction<_CloseNative, _CloseDart>('close');
    _malloc = _library.lookupFunction<_MallocNative, _MallocDart>('malloc');
    _free = _library.lookupFunction<_FreeNative, _FreeDart>('free');
  }

  final DynamicLibrary _library;
  final _PosixOpenFlags _flags;
  late final _OpenDart _open;
  late final _OpenAtDart _openAt;
  late final _ReadDart _read;
  late final _SeekDart _seek;
  late final _CloseDart _close;
  late final _MallocDart _malloc;
  late final _FreeDart _free;

  static _PosixBindings current(String contentId) {
    if (!(Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isIOS)) {
      failContent(ContentErrorCode.io, contentId: contentId);
    }
    try {
      return _instance;
    } catch (_) {
      failContent(ContentErrorCode.io, contentId: contentId);
    }
  }

  static final _PosixBindings _instance = _PosixBindings._();

  int openDirectory(String path) =>
      _withCString(path, (pointer) => _open(pointer, _flags.directory));

  int openDirectoryAt(int descriptor, String path) => _withCString(
    path,
    (pointer) => _openAt(descriptor, pointer, _flags.directory),
  );

  int openFileAt(int descriptor, String path) => _withCString(
    path,
    (pointer) => _openAt(descriptor, pointer, _flags.file),
  );

  int seekToEnd(int descriptor) => _seek(descriptor, 0, 2);

  bool seekToStart(int descriptor) => _seek(descriptor, 0, 0) == 0;

  int read(int descriptor, Pointer<Uint8> buffer, int count) =>
      _read(descriptor, buffer.cast<Void>(), count);

  int close(int descriptor) => _close(descriptor);

  Pointer<Uint8> allocate(int count, String contentId) {
    final pointer = _malloc(count);
    if (pointer.address == 0) {
      failContent(ContentErrorCode.resourceLimit, contentId: contentId);
    }
    return pointer.cast<Uint8>();
  }

  void free(Pointer<Uint8> pointer) => _free(pointer.cast<Void>());

  T _withCString<T>(String value, T Function(Pointer<Uint8>) operation) {
    final bytes = utf8.encode(value);
    final pointer = _malloc(bytes.length + 1).cast<Uint8>();
    if (pointer.address == 0) {
      throw const OutOfMemoryError();
    }
    try {
      final target = pointer.asTypedList(bytes.length + 1);
      target.setRange(0, bytes.length, bytes);
      target[bytes.length] = 0;
      return operation(pointer);
    } finally {
      _free(pointer.cast<Void>());
    }
  }
}

final class _PosixOpenFlags {
  const _PosixOpenFlags({required this.directory, required this.file});

  final int directory;
  final int file;

  factory _PosixOpenFlags.current() {
    if (Platform.isLinux || Platform.isAndroid) {
      const noFollow = 0x20000;
      const directory = 0x10000;
      const closeOnExec = 0x80000;
      const nonBlocking = 0x800;
      return const _PosixOpenFlags(
        directory: noFollow | directory | closeOnExec,
        file: noFollow | closeOnExec | nonBlocking,
      );
    }
    const noFollow = 0x100;
    const directory = 0x100000;
    const closeOnExec = 0x1000000;
    const nonBlocking = 0x4;
    return const _PosixOpenFlags(
      directory: noFollow | directory | closeOnExec,
      file: noFollow | closeOnExec | nonBlocking,
    );
  }
}
