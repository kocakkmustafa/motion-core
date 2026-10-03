part of 'controller.dart';

enum CameraCaptureState { closed, opening, running, closing, uncertain }

/// An observation of one requested owner, rather than a global capture flag.
final class CameraNativeReadback {
  const CameraNativeReadback._({
    required this.ownerId,
    required this.generation,
    required this.state,
    required this.captureClosed,
    required this.modelsClosed,
    required this.closeSequence,
    required this.nonce,
  });

  final String ownerId;
  final int generation;
  final CameraCaptureState state;
  final bool captureClosed;
  final bool modelsClosed;
  final int closeSequence;
  final int nonce;

  bool get isClosed =>
      state == CameraCaptureState.closed && captureClosed && modelsClosed;

  static CameraNativeReadback _decode(Object? raw) {
    if (raw is! Map<Object?, Object?> ||
        raw['protocol'] != 1 ||
        raw['ownerId'] is! String ||
        (raw['ownerId']! as String).isEmpty ||
        raw['generation'] is! int ||
        (raw['generation']! as int) < 0 ||
        raw['closeSequence'] is! int ||
        (raw['closeSequence']! as int) < 0 ||
        raw['nonce'] is! int ||
        (raw['nonce']! as int) < 0 ||
        raw['captureClosed'] is! bool ||
        raw['modelsClosed'] is! bool) {
      throw const CameraException(
        CameraFailure.ownedProtocolUnavailable,
        'native closure response has no exact owner/readback facts',
      );
    }
    final CameraCaptureState state;
    switch (raw['state']) {
      case 'closed':
        state = CameraCaptureState.closed;
      case 'opening':
        state = CameraCaptureState.opening;
      case 'running':
        state = CameraCaptureState.running;
      case 'closing':
        state = CameraCaptureState.closing;
      case 'uncertain':
        state = CameraCaptureState.uncertain;
      default:
        throw const CameraException(
          CameraFailure.ownedProtocolUnavailable,
          'native capture state is unknown',
        );
    }
    return CameraNativeReadback._(
      ownerId: raw['ownerId']! as String,
      generation: raw['generation']! as int,
      state: state,
      captureClosed: raw['captureClosed']! as bool,
      modelsClosed: raw['modelsClosed']! as bool,
      closeSequence: raw['closeSequence']! as int,
      nonce: raw['nonce']! as int,
    );
  }
}

/// Owns permission-delayed setup and the complete native closure handshake.
/// [retire] invalidates immediately; [close] exposes the same bounded completion.
final class CameraCaptureLease {
  CameraCaptureLease._(this._controller) : ownerId = _newOwnerId();

  static final Random _random = Random.secure();
  static String _newOwnerId() =>
      'capture-${List.generate(4, (_) => _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join()}';

  final MotionCameraController _controller;
  final String ownerId;
  bool _retired = false;
  bool _nativeAttempted = false;
  bool _uncertain = false;
  CameraSessionInfo? _session;
  Future<CameraSessionInfo>? _startFuture;
  Future<void>? _startSettled;
  Future<void>? _closeFuture;
  StreamController<CameraFrameEnvelope>? _frameEvents;
  StreamSubscription<CameraFrameEnvelope>? _nativeFrames;

  bool get isRetired => _retired;
  bool get isUncertain => _uncertain;
  CameraSessionInfo? get sessionInfo => _session;

  Future<CameraSessionInfo> start({
    required String modelPath,
    required String modelId,
    CameraLens lens = CameraLens.front,
    PassPlan initialPlan = PassPlan.uprightOnly,
  }) {
    if (_retired) {
      return Future.error(
        const CameraException(
          CameraFailure.sessionInterrupted,
          'retired capture lease cannot start',
        ),
      );
    }
    if (_startFuture != null) {
      return Future.error(
        const CameraException(
          CameraFailure.alreadyRunning,
          'capture lease already attempted a start',
        ),
      );
    }
    if (_controller._ownedQuarantined) {
      return Future.error(
        const CameraException(
          CameraFailure.closeUncertain,
          'owned controller remains quarantined',
        ),
      );
    }
    _nativeAttempted = true;
    final pending = _start(modelPath, modelId, lens, initialPlan);
    _startFuture = pending;
    // Observe a failed start immediately; retirement can begin before a caller
    // attaches its await. Closure then waits for this same settlement.
    _startSettled = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return pending;
  }

  Future<CameraSessionInfo> _start(
    String path,
    String modelId,
    CameraLens lens,
    PassPlan plan,
  ) async {
    try {
      final info = await _controller.startOwned(
        ownerId: ownerId,
        modelPath: path,
        modelId: modelId,
        lens: lens,
        initialPlan: plan,
      );
      _session = info;
      if (_retired) {
        throw const CameraException(
          CameraFailure.sessionInterrupted,
          'native start settled after capture retirement',
        );
      }
      return info;
    } catch (_) {
      retire();
      rethrow;
    }
  }

  /// Call at route/logout/background retirement, before awaiting permission,
  /// materialization, stream cancellation, or another queued operation.
  void retire() {
    if (_retired) return;
    _retired = true;
    final closing = _close();
    _closeFuture = closing;
    // Keep the original failing Future available to close() while preventing
    // an unhandled error if retirement happened in a synchronous callback.
    unawaited(closing.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  Future<void> close() {
    retire();
    return _closeFuture!;
  }

  Future<void> _close() async {
    if (!_nativeAttempted) return;
    try {
      // App subscriptions only see the local broadcast bus. Drain the one raw
      // EventChannel subscription during this closure, before replacement can
      // rely on the native ACK/readback. Cancelling an old app subscription
      // later must never clear the global native channel's successor handler.
      final closed = await Future.wait<Object?>([
        _controller.stopOwned(ownerId: ownerId),
        _cancelNativeFrames(),
      ]);
      var ack = closed.first! as CameraNativeReadback;
      if (ack.ownerId != ownerId || !ack.isClosed) {
        throw const CameraException(
          CameraFailure.closeUncertain,
          'native ACK did not confirm this owner closed',
        );
      }
      // A late start response must settle before the observation that permits
      // replacement. It cannot be recycled as a successful retired start.
      await _startSettled?.timeout(_controller.controlTimeout);
      // An absent-owner ACK can precede a delayed native start response.
      // Re-close that exact owner after settlement before fresh readback.
      if (ack.generation == 0 && _session != null) {
        ack = await _controller.stopOwned(ownerId: ownerId);
        if (ack.ownerId != ownerId || !ack.isClosed) {
          throw const CameraException(
            CameraFailure.closeUncertain,
            'late native start did not close under its exact owner',
          );
        }
      }
      if (_uncertain || _controller._ownedQuarantined) {
        throw const CameraException(
          CameraFailure.closeUncertain,
          'owned frame transport did not settle safely',
        );
      }
      final nonce = ++MotionCameraController._readbackNonce;
      final state = await _controller.readback(ownerId: ownerId, nonce: nonce);
      final generation = _session?.generation;
      if (state.ownerId != ownerId ||
          state.nonce != nonce ||
          !state.isClosed ||
          state.closeSequence < ack.closeSequence ||
          (generation != null &&
              ack.generation != 0 &&
              ack.generation != generation) ||
          (generation != null &&
              state.generation != 0 &&
              state.generation != generation) ||
          _controller._ownedQuarantined) {
        throw const CameraException(
          CameraFailure.closeUncertain,
          'fresh native readback did not confirm exact owner closure',
        );
      }
    } catch (_, stack) {
      _uncertain = true;
      _controller._ownedQuarantined = true;
      Error.throwWithStackTrace(
        const CameraException(
          CameraFailure.closeUncertain,
          'capture closure is uncertain; replacement remains blocked',
        ),
        stack,
      );
    }
  }

  Future<void> _cancelNativeFrames() async {
    final nativeFrames = _nativeFrames;
    _nativeFrames = null;
    final bus = _frameEvents;
    if (bus != null && !bus.isClosed) {
      // A paused app listener can delay its local done event indefinitely.
      // It holds no native subscription and must not delay resource closure.
      unawaited(bus.close());
    }
    await nativeFrames?.cancel().timeout(_controller.controlTimeout);
  }

  void _failNativeFrames(Object error, StackTrace stack) {
    if (_retired || _uncertain) return;
    _uncertain = true;
    _controller._ownedQuarantined = true;
    _frameEvents?.addError(
      const CameraException(
        CameraFailure.closeUncertain,
        'owned frame transport failed; capture closure must be confirmed',
      ),
      stack,
    );
    retire();
  }

  Stream<CameraFrameEnvelope> frames() {
    final info = _session;
    if (_retired || info == null) {
      throw const CameraException(
        CameraFailure.sessionInterrupted,
        'frame stream has no active owned capture',
      );
    }
    final events = _frameEvents ??=
        StreamController<CameraFrameEnvelope>.broadcast(
          onListen: () {
            if (_retired || _uncertain || _nativeFrames != null) return;
            _nativeFrames = _controller
                ._ownedFrames(ownerId, info.generation!)
                .listen(
                  (frame) {
                    if (!_retired &&
                        !_uncertain &&
                        frame.ownerId == ownerId &&
                        frame.generation == info.generation) {
                      _frameEvents!.add(frame);
                    }
                  },
                  onError: _failNativeFrames,
                  onDone: () => _failNativeFrames(
                    StateError('owned frame subscription ended'),
                    StackTrace.current,
                  ),
                );
          },
        );
    return events.stream.where((_) => !_retired && !_uncertain);
  }

  Future<void> setPassPlan(PassPlan plan) async {
    final info = _session;
    if (_retired || info == null) {
      throw const CameraException(
        CameraFailure.sessionInterrupted,
        'pass plan has no active owned capture',
      );
    }
    await _controller.setPassPlanOwned(
      ownerId: ownerId,
      generation: info.generation!,
      plan: plan,
    );
  }
}
