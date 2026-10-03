import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import 'frame_envelope.dart';
import 'pass_plan.dart';

part 'capture_lease.dart';

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
    this.ownerId,
    this.generation,
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

  /// Present only in the owned protocol; legacy sessions have no lease identity.
  final String? ownerId;
  final int? generation;

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
      ownerId: map['ownerId'] as String?,
      generation: map['generation'] as int?,
    );
  }

  static CameraSessionInfo _decodeOwned(Object? raw, String ownerId) {
    if (raw is! Map<Object?, Object?> ||
        raw['protocol'] != 1 ||
        raw['ownerId'] != ownerId ||
        raw['generation'] is! int ||
        (raw['generation']! as int) <= 0 ||
        raw['w'] is! int ||
        (raw['w']! as int) <= 0 ||
        raw['h'] is! int ||
        (raw['h']! as int) <= 0 ||
        (raw['clock'] != 'monotonic' && raw['clock'] != 'unknown') ||
        raw['library'] is! String ||
        (raw['library']! as String).isEmpty) {
      throw const CameraException(
        CameraFailure.ownedProtocolUnavailable,
        'native start did not return exact owned session facts',
      );
    }
    return _decode(raw);
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

  /// A control call that requires a running session (`setPassPlan`) arrived
  /// while none exists. `stop` is deliberately idempotent.
  notRunning('not-running'),

  /// Android has no attached, started Activity implementing LifecycleOwner.
  /// The plugin refuses instead of manufacturing an always-resumed owner.
  lifecycleUnavailable('lifecycle-unavailable'),

  /// A pending `start` lost ownership because stop, stream cancellation,
  /// backgrounding, Activity detach, or engine detach tore the session down.
  sessionInterrupted('session-interrupted'),

  /// The plugin does not implement exact ownership/closure readback.
  ownedProtocolUnavailable('owned-protocol-unavailable'),

  /// Native closure, or its bounded response, could not be confirmed.
  closeUncertain('close-uncertain'),

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
    this.controlTimeout = const Duration(seconds: 15),
  }) : _control = control ?? const MethodChannel('motion_camera/control'),
       _frames = frames ?? const EventChannel('motion_camera/frames') {
    if (controlTimeout <= Duration.zero ||
        controlTimeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(controlTimeout, 'controlTimeout');
    }
  }

  final MethodChannel _control;
  final EventChannel _frames;
  final Duration controlTimeout;
  bool _ownedQuarantined = false;
  static int _readbackNonce = 0;

  /// Create before requesting permission or materializing the model. Retiring
  /// this lease invalidates late work and never invokes a global legacy stop.
  CameraCaptureLease createCaptureLease() => CameraCaptureLease._(this);

  Future<Object?> _invokeOwned(String method, Map<String, Object> args) async {
    try {
      return await _invoke<Object?>(method, args).timeout(controlTimeout);
    } on MissingPluginException {
      throw const CameraException(
        CameraFailure.ownedProtocolUnavailable,
        'the native plugin has no owned capture protocol',
      );
    } on TimeoutException {
      _ownedQuarantined = true;
      throw const CameraException(
        CameraFailure.closeUncertain,
        'owned native control did not settle within its bound',
      );
    }
  }

  /// Exact owner protocol. Applications normally call [CameraCaptureLease.start].
  Future<CameraSessionInfo> startOwned({
    required String ownerId,
    required String modelPath,
    required String modelId,
    CameraLens lens = CameraLens.front,
    PassPlan initialPlan = PassPlan.uprightOnly,
  }) async {
    if (_ownedQuarantined) {
      throw const CameraException(
        CameraFailure.closeUncertain,
        'an earlier owned closure remains uncertain',
      );
    }
    _checkOwnerId(ownerId);
    final raw = await _invokeOwned('startOwned', {
      'ownerId': ownerId,
      'modelPath': modelPath,
      'modelId': modelId,
      'lens': lens.name,
      'plan': initialPlan.wireName,
    });
    return CameraSessionInfo._decodeOwned(raw, ownerId);
  }

  /// Stops only this owner. ACK must be followed by a new [readback] request.
  Future<CameraNativeReadback> stopOwned({required String ownerId}) async {
    _checkOwnerId(ownerId);
    return CameraNativeReadback._decode(
      await _invokeOwned('stopOwned', {'ownerId': ownerId}),
    );
  }

  /// A new nonce makes an old ACK unusable as a fresh native observation.
  Future<CameraNativeReadback> readback({
    required String ownerId,
    required int nonce,
  }) async {
    _checkOwnerId(ownerId);
    if (nonce <= 0) throw ArgumentError.value(nonce, 'nonce');
    return CameraNativeReadback._decode(
      await _invokeOwned('readback', {'ownerId': ownerId, 'nonce': nonce}),
    );
  }

  Future<void> setPassPlanOwned({
    required String ownerId,
    required int generation,
    required PassPlan plan,
  }) async {
    _checkOwnerId(ownerId);
    final state = CameraNativeReadback._decode(
      await _invokeOwned('setPassPlanOwned', {
        'ownerId': ownerId,
        'generation': generation,
        'plan': plan.wireName,
      }),
    );
    if (state.ownerId != ownerId ||
        state.generation != generation ||
        state.state != CameraCaptureState.running) {
      throw const CameraException(
        CameraFailure.sessionInterrupted,
        'pass plan update lost its exact capture owner',
      );
    }
  }

  static void _checkOwnerId(String ownerId) {
    if (ownerId.isEmpty || ownerId.length > 128) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
  }

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

  /// Stops capture and invalidates queued native work. Idempotent: calling it
  /// while already stopped succeeds. If it interrupts a pending [start], that
  /// start completes with [CameraFailure.sessionInterrupted].
  Future<void> stop() => _invoke<void>('stop');

  /// Updates which orientation passes run on coming frames. Cheap; takes
  /// effect from the next captured frame.
  Future<void> setPassPlan(PassPlan plan) =>
      _invoke<void>('setPassPlan', <String, Object>{'plan': plan.wireName});

  /// The live envelope stream. Malformed events surface as
  /// [FormatException]s in the stream — they are protocol bugs, not frames
  /// to skip.
  Stream<CameraFrameEnvelope> frames() => _frames.receiveBroadcastStream().map(
    (Object? event) => CameraFrameEnvelope.decode(event),
  );

  Stream<CameraFrameEnvelope> _ownedFrames(String ownerId, int generation) =>
      _OwnedFrameTransport(_frames, controlTimeout, <String, Object>{
        'ownerId': ownerId,
        'generation': generation,
      }).stream;
}

/// EventChannel's convenience broadcast stream discards the Future returned by
/// its async onCancel callback and reports listen/cancel errors to FlutterError.
/// Owned closure needs both RPC replies and their failures, so its one raw
/// subscription uses an explicitly awaitable single-subscription controller.
final class _OwnedFrameTransport {
  _OwnedFrameTransport(this._channel, this._timeout, this._arguments) {
    _methods = MethodChannel(
      _channel.name,
      _channel.codec,
      _channel.binaryMessenger,
    );
    _events = StreamController<CameraFrameEnvelope>(
      onListen: _listen,
      onCancel: _cancel,
    );
  }

  final EventChannel _channel;
  final Duration _timeout;
  final Map<String, Object> _arguments;
  late final MethodChannel _methods;
  late final StreamController<CameraFrameEnvelope> _events;
  Future<void>? _listenReply;
  bool _cancelled = false;

  Stream<CameraFrameEnvelope> get stream => _events.stream;

  void _listen() {
    _channel.binaryMessenger.setMessageHandler(_channel.name, (data) async {
      if (_cancelled) return null;
      try {
        if (data == null) {
          throw const CameraException(
            CameraFailure.closeUncertain,
            'owned frame stream ended before lease retirement',
          );
        }
        _events.add(
          CameraFrameEnvelope.decode(_channel.codec.decodeEnvelope(data)),
        );
      } catch (error, stack) {
        _events.addError(error, stack);
      }
      return null;
    });
    final reply = _methods
        .invokeMethod<void>('listen', _arguments)
        .timeout(_timeout);
    _listenReply = reply;
    // Observe failure immediately, while retaining the same failed reply for
    // cancellation. A failed/timed-out listen still needs an exact cancel.
    unawaited(
      reply.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (!_cancelled) _events.addError(error, stack);
        },
      ),
    );
  }

  Future<void> _cancel() async {
    _cancelled = true;
    // Clear only at cancellation entry. A late reply/error continuation must
    // never clear a successor's Dart handler after this lease timed out.
    _channel.binaryMessenger.setMessageHandler(_channel.name, null);
    Object? listenFailure;
    StackTrace? listenStack;
    try {
      await _listenReply;
    } catch (error, stack) {
      listenFailure = error;
      listenStack = stack;
    }
    await _methods.invokeMethod<void>('cancel', _arguments).timeout(_timeout);
    if (listenFailure != null) {
      Error.throwWithStackTrace(listenFailure, listenStack!);
    }
  }
}
