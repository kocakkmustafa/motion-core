import 'package:flutter/services.dart';

import 'frame_envelope.dart';
import 'pass_plan.dart';

/// Which physical camera to open.
enum CameraLens { front, back }

/// What the native layer reports once the session is actually running —
/// facts about the opened device, not requests ("bağlandı ≠ canlı": these
/// values describe the session that exists, and are the only place they
/// come from).
final class CameraSessionInfo {
  const CameraSessionInfo({
    required this.width,
    required this.height,
    required this.clockDomain,
    required this.libraryTag,
  });

  /// Capture size after sensor-rotation normalization — the same `w×h`
  /// every envelope of this session will carry.
  final int width;
  final int height;

  final ClockDomain clockDomain;

  /// Native MediaPipe library identifier, e.g. `mp-ios-0.10.21` /
  /// `mp-android-0.10.29` (M-L-02 pins). Combined with the app-declared
  /// modelId into each envelope's `model` string.
  final String libraryTag;

  static CameraSessionInfo _decode(Object? raw) {
    final Map<Object?, Object?> map = raw as Map<Object?, Object?>;
    final String clock = map['clock'] as String;
    return CameraSessionInfo(
      width: map['w'] as int,
      height: map['h'] as int,
      clockDomain: switch (clock) {
        'monotonic' => ClockDomain.monotonic,
        'unknown' => ClockDomain.unknown,
        _ => throw FormatException('unrecognized clock domain "$clock"'),
      },
      libraryTag: map['library'] as String,
    );
  }
}

/// Named, typed failures of the control surface. Every refusal has a name
/// and a reason — a `PlatformException` with an unrecognized code is
/// re-thrown untranslated rather than absorbed into a catch-all.
enum CameraFailure {
  /// The user has not granted (or has revoked) camera permission. The
  /// plugin never asks — asking is an app-level UX decision; the plugin's
  /// job is to refuse with a name the app can route to its permission flow.
  permissionDenied('camera-permission-denied'),

  /// The pose model asset could not be loaded at the given path.
  modelLoadFailed('model-load-failed'),

  /// `start` while a session is already running.
  alreadyRunning('already-running'),

  /// A control call that requires a running session (`stop`, `setPassPlan`)
  /// arrived while none exists.
  notRunning('not-running'),

  /// The device has no camera matching the requested lens.
  noSuchCamera('no-such-camera');

  const CameraFailure(this.code);
  final String code;

  static CameraFailure? fromCode(String code) {
    for (final CameraFailure f in values) {
      if (f.code == code) return f;
    }
    return null;
  }
}

/// Thrown by [MotionCameraController] methods for recognized native
/// refusals; carries the native message as [detail].
final class CameraException implements Exception {
  const CameraException(this.failure, this.detail);

  final CameraFailure failure;
  final String? detail;

  @override
  String toString() =>
      'CameraException(${failure.code}${detail == null ? '' : ': $detail'})';
}

/// Control + data surface of the native bridge.
///
/// One session at a time, by design: the pose model is the scarce resource,
/// and "two silent half-sessions" is a worse failure mode than a named
/// [CameraFailure.alreadyRunning].
class MotionCameraController {
  MotionCameraController({
    MethodChannel? control,
    EventChannel? frames,
  })  : _control = control ?? const MethodChannel('motion_camera/control'),
        _frames = frames ?? const EventChannel('motion_camera/frames');

  final MethodChannel _control;
  final EventChannel _frames;

  Future<T> _invoke<T>(String method, [Object? args]) async {
    try {
      return (await _control.invokeMethod<T>(method, args)) as T;
    } on PlatformException catch (e) {
      final CameraFailure? failure = CameraFailure.fromCode(e.code);
      if (failure == null) rethrow;
      throw CameraException(failure, e.message);
    }
  }

  /// Opens the camera and loads the pose model. Returns facts about the
  /// running session.
  ///
  /// [modelPath] is an absolute filesystem path to the `.task` model asset —
  /// the plugin deliberately bundles no model (apps pin their own and ship
  /// it as an asset). [modelId] is the app's declared identity for that file
  /// (e.g. `pose_landmarker_full`); it is stamped into every envelope's
  /// provenance string, so a model swap can never silently reinterpret a
  /// session.
  Future<CameraSessionInfo> start({
    required String modelPath,
    required String modelId,
    CameraLens lens = CameraLens.front,
    PassPlan initialPlan = PassPlan.uprightOnly,
  }) async {
    final Object? raw = await _invoke<Object?>('start', <String, Object>{
      'modelPath': modelPath,
      'modelId': modelId,
      'lens': lens.name,
      'plan': initialPlan.wireName,
    });
    return CameraSessionInfo._decode(raw);
  }

  Future<void> stop() => _invoke<void>('stop');

  /// Updates which orientation passes run on coming frames. Cheap; takes
  /// effect from the next captured frame.
  Future<void> setPassPlan(PassPlan plan) =>
      _invoke<void>('setPassPlan', <String, Object>{'plan': plan.wireName});

  /// The live envelope stream. Malformed events surface as
  /// [FormatException]s in the stream — they are protocol bugs, not frames
  /// to skip.
  Stream<CameraFrameEnvelope> frames() => _frames
      .receiveBroadcastStream()
      .map((Object? event) => CameraFrameEnvelope.decode(event));
}
