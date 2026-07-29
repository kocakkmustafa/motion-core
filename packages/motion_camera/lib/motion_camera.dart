/// Native camera → MediaPipe pose bridge for the Yula Motion family.
///
/// Contract: `docs/70-KAMERA-KOPRUSU-SOZLESMESI.md` (repo root). The core
/// principle carried over from motion_core: the Dart side never sees images,
/// only landmark envelopes on a monotonic clock with measured rates —
/// orientation strategy stays in `OrientationAwarePoseSource`, and the native
/// layer is a dumb, pinned pipe (iOS MediaPipeTasksVision 0.10.21, Android
/// tasks-vision 0.10.29 — M-L-02).
library;

export 'src/controller.dart';
export 'src/envelope_driver.dart';
export 'src/frame_envelope.dart';
export 'src/pass_plan.dart';
export 'src/rate_meter.dart';
