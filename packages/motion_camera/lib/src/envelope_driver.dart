import 'package:motion_core/motion_core.dart';

import 'frame_envelope.dart';

/// The seam between the push-based camera stream and motion_core's pull-based
/// [PoseSourceDriver].
///
/// The engine loop is one envelope wide:
/// ```dart
/// await for (final envelope in controller.frames()) {
///   driver.load(envelope);
///   final resolution = source.next(envelope.tUs, expectation);
///   ...
/// }
/// ```
/// `detectAs` answers ONLY for the loaded envelope's timestamp. A mismatched
/// timestamp or an unplanned pass throws instead of returning null: null
/// already carries the meaning "the model saw no person", and overloading it
/// with "you asked the wrong question" would let a plumbing bug wear a
/// measurement's clothes (the J-056 lesson, one layer up).
final class EnvelopeDriver implements PoseSourceDriver {
  CameraFrameEnvelope? _current;

  CameraFrameEnvelope? get current => _current;

  void load(CameraFrameEnvelope envelope) => _current = envelope;

  @override
  PoseFrame? detectAs(int tUs, BodyOrientation orientation) {
    final CameraFrameEnvelope? envelope = _current;
    if (envelope == null) {
      throw StateError('detectAs before any envelope was loaded');
    }
    if (envelope.tUs != tUs) {
      throw StateError(
          'detectAs asked for t=$tUs but the loaded envelope is '
          't=${envelope.tUs} — the engine loop and the camera stream have '
          'desynchronized');
    }
    return envelope.pass(orientation);
  }
}
