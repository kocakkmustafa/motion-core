import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_camera/motion_camera.dart';
import 'package:motion_core/motion_core.dart';

Map<String, Object> _running(String owner, {int generation = 1}) => {
  'protocol': 1,
  'ownerId': owner,
  'generation': generation,
  'w': 720,
  'h': 1280,
  'clock': 'monotonic',
  'library': 'mp-ios-0.10.21',
};

Map<String, Object> _closed(
  String owner, {
  int nonce = 0,
  int generation = 1,
}) => {
  'protocol': 1,
  'ownerId': owner,
  'generation': generation,
  'state': 'closed',
  'captureClosed': true,
  'modelsClosed': true,
  'closeSequence': 1,
  'nonce': nonce,
};

Map<String, Object?> _frame(String owner, int generation) => {
  'ownerId': owner,
  'generation': generation,
  't': 1,
  'w': 720,
  'h': 1280,
  'model': 'mp-ios-0.10.21+model',
  'clock': 'monotonic',
  'infUs': 1,
  'dropped': 0,
  'up': null,
};

// Use the real EventChannel/StandardMethodCodec path. A broadcast stream
// override would conceal Flutter's discarded asynchronous onCancel Future.
final class _FrameChannel {
  _FrameChannel({
    this.listenGate,
    this.cancelGate,
    this.listenError = false,
    this.cancelError = false,
    this.binaryMessenger,
  }) : name = 'motion_camera/test/owned_frames/${_nextId++}' {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      if (call.method == 'listen') {
        listener = call.arguments as Map<Object?, Object?>;
        if (!listenEntered.isCompleted) listenEntered.complete();
        await listenGate?.future;
        if (listenError) throw PlatformException(code: 'listen-error');
      } else if (call.method == 'cancel') {
        if (!cancelEntered.isCompleted) cancelEntered.complete();
        await cancelGate?.future;
        if (cancelError) throw PlatformException(code: 'cancel-error');
        if (listener?['ownerId'] ==
            (call.arguments as Map<Object?, Object?>)['ownerId']) {
          listener = null;
        }
      }
      return null;
    });
    addTearDown(dispose);
  }

  static int _nextId = 0;
  final String name;
  final Completer<void>? listenGate;
  final Completer<void>? cancelGate;
  final bool listenError;
  final bool cancelError;
  final BinaryMessenger? binaryMessenger;
  final calls = <MethodCall>[];
  final leases = <CameraCaptureLease>[];
  final listenEntered = Completer<void>();
  final cancelEntered = Completer<void>();
  Map<Object?, Object?>? listener;

  TestDefaultBinaryMessenger get messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MethodChannel get methodChannel => MethodChannel(name);
  EventChannel get channel =>
      EventChannel(name, const StandardMethodCodec(), binaryMessenger);

  CameraCaptureLease track(CameraCaptureLease lease) {
    leases.add(lease);
    return lease;
  }

  Future<void> emit(Object? event) => messenger.handlePlatformMessage(
    name,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    (_) {},
  );

  Future<void> end() => messenger.handlePlatformMessage(name, null, (_) {});

  Future<void> emitError() => messenger.handlePlatformMessage(
    name,
    const StandardMethodCodec().encodeErrorEnvelope(code: 'capture-error'),
    (_) {},
  );

  Future<void> dispose() async {
    if (listenGate != null && !listenGate!.isCompleted) listenGate!.complete();
    if (cancelGate != null && !cancelGate!.isCompleted) cancelGate!.complete();
    for (final lease in leases) {
      try {
        await lease.close();
      } on CameraException {
        // The test explicitly observes uncertain closures.
      }
    }
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMessageHandler(name, null);
  }
}

final class _RecordingMessenger implements BinaryMessenger {
  final delegate =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sent = <String>[];
  final handlers = <String>[];

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent.add(channel);
    return delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    handlers.add('$channel:${handler == null ? 'clear' : 'install'}');
    delegate.setMessageHandler(channel, handler);
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    void Function(ByteData?)? callback,
  ) => delegate.handlePlatformMessage(channel, data, callback);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('motion_camera/test/owned_control');
  final calls = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  Map<Object?, Object?> args(MethodCall call) =>
      call.arguments! as Map<Object?, Object?>;

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, null);
  });

  test(
    'legacy global stop remains an explicit unsafe-adoption negative control',
    () async {
      var nativeRunning = false;
      mock((call) async {
        if (call.method == 'start') {
          nativeRunning = true;
          return {
            'w': 720,
            'h': 1280,
            'clock': 'monotonic',
            'library': 'legacy',
          };
        }
        nativeRunning = false;
        return null;
      });
      final retiredSource = MotionCameraController(control: control);
      final successor = MotionCameraController(control: control);
      await successor.start(modelPath: '/model.task', modelId: 'model');
      await retiredSource.stop();
      expect(nativeRunning, isFalse);
      expect(calls.map((call) => call.method), ['start', 'stop']);
    },
  );

  test(
    'retire before delayed permission prevents native start and stop',
    () async {
      mock((_) async => throw StateError('no native operation is permitted'));
      final lease = MotionCameraController(
        control: control,
      ).createCaptureLease();
      final permission = Completer<bool>();
      final pending = permission.future.then((granted) async {
        if (granted) {
          await lease.start(modelPath: '/model.task', modelId: 'model');
        }
      });
      final rejected = expectLater(
        pending,
        throwsA(
          isA<CameraException>().having(
            (e) => e.failure,
            'failure',
            CameraFailure.sessionInterrupted,
          ),
        ),
      );
      lease.retire();
      permission.complete(true);
      await rejected;
      await lease.close();
      expect(calls, isEmpty);
    },
  );

  test('retire during materialization also prevents native creation', () async {
    mock((_) async => throw StateError('no native operation is permitted'));
    final lease = MotionCameraController(control: control).createCaptureLease();
    final model = Completer<String>();
    final pending = model.future.then(
      (path) => lease.start(modelPath: path, modelId: 'model'),
    );
    final rejected = expectLater(pending, throwsA(isA<CameraException>()));
    lease.retire();
    model.complete('/model.task');
    await rejected;
    await lease.close();
    expect(calls, isEmpty);
  });

  test(
    'permission denial before start closes without global native stop',
    () async {
      final lease = MotionCameraController(
        control: control,
      ).createCaptureLease();
      await lease.close();
      await lease.close();
      expect(lease.isRetired, isTrue);
      expect(calls, isEmpty);
    },
  );

  test(
    'pending start is stopped by owner and fresh readback follows settlement',
    () async {
      final started = Completer<void>();
      final lateStart = Completer<Object?>();
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') {
          started.complete();
          return lateStart.future;
        }
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final lease = MotionCameraController(
        control: control,
      ).createCaptureLease();
      final pending = lease.start(modelPath: '/model.task', modelId: 'model');
      final interrupted = expectLater(pending, throwsA(isA<CameraException>()));
      await started.future;
      var closeFinished = false;
      final close = lease.close().then((_) => closeFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['startOwned', 'stopOwned']);
      expect(closeFinished, isFalse);
      lateStart.complete(_running(lease.ownerId));
      await interrupted;
      await close;
      expect(calls.map((call) => call.method), [
        'startOwned',
        'stopOwned',
        'readback',
      ]);
      expect(args(calls.last)['nonce'], greaterThan(0));
      expect(lease.isUncertain, isFalse);
    },
  );

  test('closing denied owner cannot stop a running successor', () async {
    String? current;
    mock((call) async {
      final owner = args(call)['ownerId']! as String;
      if (call.method == 'startOwned') {
        if (current != null) {
          throw PlatformException(code: 'camera-permission-denied');
        }
        current = owner;
        return _running(owner);
      }
      if (call.method == 'stopOwned' && current == owner) current = null;
      return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
    });
    final controller = MotionCameraController(control: control);
    final successor = controller.createCaptureLease();
    await successor.start(modelPath: '/model.task', modelId: 'model');
    final denied = controller.createCaptureLease();
    await expectLater(
      denied.start(modelPath: '/model.task', modelId: 'model'),
      throwsA(isA<CameraException>()),
    );
    await denied.close();
    expect(current, successor.ownerId);
    expect(calls.any((call) => call.method == 'stop'), isFalse);
    await successor.close();
  });

  test(
    'retiring a pending rejected owner preserves the running successor',
    () async {
      String? current;
      final rejectedStart = Completer<Object?>();
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') {
          if (current != null) return rejectedStart.future;
          current = owner;
          return _running(owner);
        }
        if (call.method == 'stopOwned' && current == owner) current = null;
        return _closed(
          owner,
          nonce: args(call)['nonce'] as int? ?? 0,
          generation: current == owner ? 1 : 0,
        );
      });
      final successor = MotionCameraController(
        control: control,
      ).createCaptureLease();
      await successor.start(modelPath: '/model.task', modelId: 'model');
      final rejected = MotionCameraController(
        control: control,
      ).createCaptureLease();
      final start = rejected.start(modelPath: '/model.task', modelId: 'model');
      final startFailure = expectLater(start, throwsA(isA<CameraException>()));
      final closed = rejected.close();
      await Future<void>.delayed(Duration.zero);
      expect(current, successor.ownerId);
      rejectedStart.completeError(PlatformException(code: 'already-running'));
      await startFailure;
      await closed;
      expect(current, successor.ownerId);
      expect(rejected.isUncertain, isFalse);
      await successor.close();
    },
  );

  test(
    'absent-owner ACK is reclosed after a delayed native start settles',
    () async {
      final response = Completer<Object?>();
      String? current;
      var stopCount = 0;
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return response.future;
        if (call.method == 'stopOwned') {
          stopCount++;
          final existed = current == owner;
          if (existed) current = null;
          return _closed(owner, generation: existed ? 1 : 0);
        }
        return _closed(owner, nonce: args(call)['nonce']! as int);
      });
      final lease = MotionCameraController(
        control: control,
      ).createCaptureLease();
      final start = lease.start(modelPath: '/model.task', modelId: 'model');
      final rejected = expectLater(start, throwsA(isA<CameraException>()));
      final closed = lease.close();
      await Future<void>.delayed(Duration.zero);
      expect(stopCount, 1);
      current = lease.ownerId;
      response.complete(_running(lease.ownerId));
      await rejected;
      await closed;
      expect(stopCount, 2);
      expect(current, isNull);
      expect(lease.isUncertain, isFalse);
    },
  );

  test('closed stale lease cannot issue a stop for its successor', () async {
    String? current;
    mock((call) async {
      final owner = args(call)['ownerId']! as String;
      if (call.method == 'startOwned') {
        current = owner;
        return _running(owner);
      }
      if (call.method == 'stopOwned' && current == owner) current = null;
      return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
    });
    final controller = MotionCameraController(control: control);
    final first = controller.createCaptureLease();
    await first.start(modelPath: '/model.task', modelId: 'model');
    await first.close();
    final successor = controller.createCaptureLease();
    await successor.start(modelPath: '/model.task', modelId: 'model');
    final before = calls.length;
    await first.close();
    expect(calls.length, before);
    expect(current, successor.ownerId);
    await successor.close();
  });

  for (final fault in [
    'ack-owner',
    'ack-generation',
    'readback-owner',
    'readback-generation',
    'readback-nonce',
    'readback-sequence',
    'readback-state',
    'readback-model',
  ]) {
    test(
      '$fault poisons owned controller rather than claiming closure',
      () async {
        mock((call) async {
          final owner = args(call)['ownerId']! as String;
          if (call.method == 'startOwned') return _running(owner);
          final response = _closed(
            owner,
            nonce: args(call)['nonce'] as int? ?? 0,
          );
          if (fault == 'ack-owner' && call.method == 'stopOwned') {
            response['ownerId'] = 'another-owner';
          }
          if (fault == 'ack-generation' && call.method == 'stopOwned') {
            response['generation'] = 2;
          }
          if (fault == 'readback-owner' && call.method == 'readback') {
            response['ownerId'] = 'another-owner';
          }
          if (fault == 'readback-generation' && call.method == 'readback') {
            response['generation'] = 2;
          }
          if (fault == 'readback-sequence' && call.method == 'stopOwned') {
            response['closeSequence'] = 99;
          }
          if (fault == 'readback-state' && call.method == 'readback') {
            response['state'] = 'closing';
          }
          if (fault == 'readback-nonce' && call.method == 'readback') {
            response['nonce'] = 0;
          }
          if (fault == 'readback-model' && call.method == 'readback') {
            response['modelsClosed'] = false;
          }
          return response;
        });
        final controller = MotionCameraController(control: control);
        final lease = controller.createCaptureLease();
        await lease.start(modelPath: '/model.task', modelId: 'model');
        await expectLater(lease.close(), throwsA(isA<CameraException>()));
        expect(lease.isUncertain, isTrue);
        final before = calls.length;
        await expectLater(
          controller.createCaptureLease().start(
            modelPath: '/model.task',
            modelId: 'model',
          ),
          throwsA(isA<CameraException>()),
        );
        expect(calls.length, before);
      },
    );
  }

  test(
    'older plugin does not fall back to legacy start or global stop',
    () async {
      mock((_) async => throw MissingPluginException('owned protocol absent'));
      final lease = MotionCameraController(
        control: control,
      ).createCaptureLease();
      await expectLater(
        lease.start(modelPath: '/model.task', modelId: 'model'),
        throwsA(
          isA<CameraException>().having(
            (e) => e.failure,
            'failure',
            CameraFailure.ownedProtocolUnavailable,
          ),
        ),
      );
      await expectLater(lease.close(), throwsA(isA<CameraException>()));
      expect(calls.every((call) => call.method.endsWith('Owned')), isTrue);
      expect(lease.isUncertain, isTrue);
    },
  );

  test(
    'owned frames reject old generations and stop immediately on retirement',
    () async {
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final frames = _FrameChannel();
      final lease = frames.track(
        MotionCameraController(
          control: control,
          frames: frames.channel,
        ).createCaptureLease(),
      );
      await lease.start(modelPath: '/model.task', modelId: 'model');
      final seen = <CameraFrameEnvelope>[];
      final sub = lease.frames().listen(seen.add);
      await frames.listenEntered.future;
      await frames.emit(_frame('retired-owner', 1));
      await frames.emit(_frame(lease.ownerId, 2));
      await frames.emit(_frame(lease.ownerId, 1));
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      expect(seen.single.ran(BodyOrientation.upright), isTrue);
      lease.retire();
      await frames.emit(_frame(lease.ownerId, 1));
      await lease.close();
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(1));
      await sub.cancel();
    },
  );

  test(
    'native close timeout is sticky and blocks another owned start',
    () async {
      final neverClosed = Completer<Object?>();
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        return neverClosed.future;
      });
      final controller = MotionCameraController(
        control: control,
        controlTimeout: const Duration(milliseconds: 25),
      );
      final lease = controller.createCaptureLease();
      await lease.start(modelPath: '/model.task', modelId: 'model');
      await expectLater(lease.close(), throwsA(isA<CameraException>()));
      expect(lease.isUncertain, isTrue);
      await expectLater(
        controller.createCaptureLease().start(
          modelPath: '/model.task',
          modelId: 'model',
        ),
        throwsA(isA<CameraException>()),
      );
      neverClosed.complete(_closed(lease.ownerId));
      expect(lease.isUncertain, isTrue);
    },
  );

  test(
    'owned transport waits for cancel ACK before readback and replacement',
    () async {
      final cancelGate = Completer<void>();
      final nativeClosed = Completer<void>();
      final frames = _FrameChannel(cancelGate: cancelGate);
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        if (call.method == 'stopOwned' && !nativeClosed.isCompleted) {
          nativeClosed.complete();
        }
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final controller = MotionCameraController(
        control: control,
        frames: frames.channel,
      );
      final first = frames.track(controller.createCaptureLease());
      final next = frames.track(controller.createCaptureLease());
      await first.start(modelPath: '/model.task', modelId: 'model');
      final sub = first.frames().listen((_) {});
      await frames.listenEntered.future;
      var closed = false;
      final closing = first.close().then((_) => closed = true);
      final opening = closing.then(
        (_) => next.start(modelPath: '/model.task', modelId: 'model'),
      );
      await nativeClosed.future;
      await frames.cancelEntered.future;
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      expect(calls.map((call) => call.method), ['startOwned', 'stopOwned']);
      expect(frames.calls.map((call) => call.method), ['listen', 'cancel']);
      expect(args(frames.calls.last), {
        'ownerId': first.ownerId,
        'generation': 1,
      });
      cancelGate.complete();
      await closing;
      await opening;
      expect(calls.map((call) => call.method), [
        'startOwned',
        'stopOwned',
        'readback',
        'startOwned',
      ]);
      await sub.cancel();
      await next.close();
    },
  );

  test('owned transport retires during listen and awaits both replies', () async {
    final listenGate = Completer<void>();
    final cancelGate = Completer<void>();
    final frames = _FrameChannel(
      listenGate: listenGate,
      cancelGate: cancelGate,
    );
    mock((call) async {
      final owner = args(call)['ownerId']! as String;
      if (call.method == 'startOwned') return _running(owner);
      return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
    });
    final lease = frames.track(
      MotionCameraController(
        control: control,
        frames: frames.channel,
      ).createCaptureLease(),
    );
    await lease.start(modelPath: '/model.task', modelId: 'model');
    final sub = lease.frames().listen((_) {});
    await frames.listenEntered.future;
    var closed = false;
    final closing = lease.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(frames.calls.map((call) => call.method), ['listen']);
    expect(closed, isFalse);
    expect(calls.any((call) => call.method == 'readback'), isFalse);
    listenGate.complete();
    await frames.cancelEntered.future;
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    cancelGate.complete();
    await closing;
    expect(lease.isUncertain, isFalse);
    expect(frames.calls.map((call) => call.method), ['listen', 'cancel']);
    await sub.cancel();
  });

  for (final fault in ['cancel-error', 'cancel-timeout']) {
    test('owned transport $fault quarantines after native close ACK', () async {
      final cancelGate = fault == 'cancel-timeout' ? Completer<void>() : null;
      final recording = _RecordingMessenger();
      final frames = _FrameChannel(
        cancelGate: cancelGate,
        cancelError: fault == 'cancel-error',
        binaryMessenger: recording,
      );
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final controller = MotionCameraController(
        control: control,
        frames: frames.channel,
        controlTimeout: const Duration(milliseconds: 25),
      );
      final lease = frames.track(controller.createCaptureLease());
      await lease.start(modelPath: '/model.task', modelId: 'model');
      final sub = lease.frames().listen((_) {});
      await frames.listenEntered.future;
      await expectLater(
        lease.close(),
        throwsA(
          isA<CameraException>().having(
            (e) => e.failure,
            'failure',
            CameraFailure.closeUncertain,
          ),
        ),
      );
      expect(lease.isUncertain, isTrue);
      expect(recording.handlers, [
        '${frames.name}:install',
        '${frames.name}:clear',
      ]);
      expect(calls.any((call) => call.method == 'readback'), isFalse);
      final before = calls.length;
      if (cancelGate != null) cancelGate.complete();
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        controller.createCaptureLease().start(
          modelPath: '/model.task',
          modelId: 'model',
        ),
        throwsA(isA<CameraException>()),
      );
      expect(calls, hasLength(before));
      expect(lease.isUncertain, isTrue);
      expect(recording.handlers, [
        '${frames.name}:install',
        '${frames.name}:clear',
      ], reason: 'a late cancel reply must not clear a successor handler');
      await sub.cancel();
    });
  }

  for (final fault in ['listen-error', 'listen-timeout']) {
    test('owned transport $fault retires and quarantines', () async {
      final listenGate = fault == 'listen-timeout' ? Completer<void>() : null;
      final frames = _FrameChannel(
        listenGate: listenGate,
        listenError: fault == 'listen-error',
      );
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final controller = MotionCameraController(
        control: control,
        frames: frames.channel,
        controlTimeout: const Duration(milliseconds: 25),
      );
      final lease = frames.track(controller.createCaptureLease());
      await lease.start(modelPath: '/model.task', modelId: 'model');
      final failed = Completer<void>();
      final sub = lease.frames().listen(
        (_) {},
        onError: (Object error) {
          expect(error, isA<CameraException>());
          if (!failed.isCompleted) failed.complete();
        },
      );
      await failed.future.timeout(const Duration(seconds: 1));
      expect(lease.isRetired, isTrue);
      expect(lease.isUncertain, isTrue);
      await expectLater(lease.close(), throwsA(isA<CameraException>()));
      expect(frames.calls.map((call) => call.method), ['listen', 'cancel']);
      expect(calls.any((call) => call.method == 'readback'), isFalse);
      final before = calls.length;
      if (listenGate != null) listenGate.complete();
      await expectLater(
        controller.createCaptureLease().start(
          modelPath: '/model.task',
          modelId: 'model',
        ),
        throwsA(isA<CameraException>()),
      );
      expect(calls, hasLength(before));
      await sub.cancel();
    });
  }

  for (final fault in ['end-of-stream', 'error-envelope', 'malformed-frame']) {
    test('owned transport $fault retires and quarantines', () async {
      final frames = _FrameChannel();
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') return _running(owner);
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      final controller = MotionCameraController(
        control: control,
        frames: frames.channel,
      );
      final lease = frames.track(controller.createCaptureLease());
      await lease.start(modelPath: '/model.task', modelId: 'model');
      final errors = <Object>[];
      final sub = lease.frames().listen((_) {}, onError: errors.add);
      await frames.listenEntered.future;
      if (fault == 'end-of-stream') {
        await frames.end();
      } else if (fault == 'error-envelope') {
        await frames.emitError();
      } else {
        await frames.emit({'invalid': true});
      }
      await Future<void>.delayed(Duration.zero);
      expect(lease.isRetired, isTrue);
      expect(lease.isUncertain, isTrue);
      expect(errors, hasLength(1));
      expect(errors.single, isA<CameraException>());
      await expectLater(lease.close(), throwsA(isA<CameraException>()));
      expect(calls.any((call) => call.method == 'readback'), isFalse);
      await sub.cancel();
    });
  }

  test('owned transport uses the exact EventChannel binaryMessenger', () async {
    final recording = _RecordingMessenger();
    final frames = _FrameChannel(binaryMessenger: recording);
    mock((call) async {
      final owner = args(call)['ownerId']! as String;
      if (call.method == 'startOwned') return _running(owner);
      return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
    });
    final lease = frames.track(
      MotionCameraController(
        control: control,
        frames: frames.channel,
      ).createCaptureLease(),
    );
    await lease.start(modelPath: '/model.task', modelId: 'model');
    final seen = <CameraFrameEnvelope>[];
    final sub = lease.frames().listen(seen.add);
    await frames.listenEntered.future;
    await frames.emit(_frame(lease.ownerId, 1));
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await lease.close();
    expect(recording.sent, [frames.name, frames.name]);
    expect(recording.handlers, [
      '${frames.name}:install',
      '${frames.name}:clear',
    ]);
    await sub.cancel();
  });

  test('owned transport denied or foreign lease preserves active A', () async {
    final frames = _FrameChannel();
    String? current;
    mock((call) async {
      final owner = args(call)['ownerId']! as String;
      if (call.method == 'startOwned') {
        if (current != null) throw PlatformException(code: 'already-running');
        current = owner;
        return _running(owner);
      }
      if (call.method == 'stopOwned' && current == owner) current = null;
      return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
    });
    final controller = MotionCameraController(
      control: control,
      frames: frames.channel,
    );
    final a = frames.track(controller.createCaptureLease());
    await a.start(modelPath: '/model.task', modelId: 'model');
    final seen = <CameraFrameEnvelope>[];
    final sub = a.frames().listen(seen.add);
    await frames.listenEntered.future;
    final denied = frames.track(controller.createCaptureLease());
    await denied.close();
    final foreign = frames.track(controller.createCaptureLease());
    await expectLater(
      foreign.start(modelPath: '/model.task', modelId: 'model'),
      throwsA(isA<CameraException>()),
    );
    await foreign.close();
    expect(frames.calls.map((call) => call.method), ['listen']);
    expect(frames.listener?['ownerId'], a.ownerId);
    expect(current, a.ownerId);
    await frames.emit(_frame(a.ownerId, 1));
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await a.close();
    await sub.cancel();
  });

  test(
    'old app subscription cancellation cannot remove successor native handler',
    () async {
      const frameName = 'motion_camera/test/owned_native_frames';
      const frameControl = MethodChannel(frameName);
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final streamCalls = <MethodCall>[];
      String? current;
      mock((call) async {
        final owner = args(call)['ownerId']! as String;
        if (call.method == 'startOwned') {
          current = owner;
          return _running(owner);
        }
        if (call.method == 'stopOwned' && current == owner) current = null;
        return _closed(owner, nonce: args(call)['nonce'] as int? ?? 0);
      });
      messenger.setMockMethodCallHandler(frameControl, (call) async {
        streamCalls.add(call);
        if (call.method == 'cancel') {
          // Mirrors the owner contract, with global nil cancel as the explicit
          // negative control. This also exercises real EventChannel handler
          // installation/removal, rather than a replacement stream fixture.
          final owner = (call.arguments as Map<Object?, Object?>?)?['ownerId'];
          if (owner == null || owner == current) current = null;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(frameControl, null));
      final controller = MotionCameraController(
        control: control,
        frames: const EventChannel(frameName),
      );
      final first = controller.createCaptureLease();
      await first.start(modelPath: '/model.task', modelId: 'model');
      final oldSub = first.frames().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      oldSub.pause();
      await first.close();
      expect(streamCalls.map((call) => call.method), ['listen', 'cancel']);
      expect(args(streamCalls.first), {
        'ownerId': first.ownerId,
        'generation': 1,
      });
      expect(args(streamCalls.last), args(streamCalls.first));

      final successor = controller.createCaptureLease();
      await successor.start(modelPath: '/model.task', modelId: 'model');
      final arrived = Completer<CameraFrameEnvelope>();
      final newSub = successor.frames().listen(arrived.complete);
      await Future<void>.delayed(Duration.zero);
      final beforeCancel = streamCalls.length;
      await oldSub.cancel();
      expect(streamCalls.length, beforeCancel);
      expect(current, successor.ownerId);
      await messenger.handlePlatformMessage(
        frameName,
        codec.encodeSuccessEnvelope({
          'ownerId': successor.ownerId,
          'generation': 1,
          't': 1,
          'w': 720,
          'h': 1280,
          'model': 'mp-ios-0.10.21+model',
          'clock': 'monotonic',
          'infUs': 1,
          'dropped': 0,
          'up': null,
        }),
        (_) {},
      );
      expect(
        (await arrived.future.timeout(const Duration(seconds: 1))).ownerId,
        successor.ownerId,
      );
      await successor.close();
      await newSub.cancel();
    },
  );
}
