import '../geometry/vec3.dart';
import 'landmark_index.dart';

/// A single tracked body point.
final class PoseLandmark {
  const PoseLandmark(this.x, this.y, this.z, this.visibility);

  const PoseLandmark.invisible()
      : x = 0,
        y = 0,
        z = 0,
        visibility = 0;

  final double x;
  final double y;
  final double z;

  /// Model-reported confidence for this landmark, in `[0, 1]`.
  ///
  /// This is the raw material of the family's confidence gate — the single
  /// mechanism that lets the engine say "I cannot see your right wrist well
  /// enough to judge it" instead of inventing a verdict.
  final double visibility;

  Vec3 get position => Vec3(x, y, z);

  PoseLandmark copyWith({
    double? x,
    double? y,
    double? z,
    double? visibility,
  }) =>
      PoseLandmark(
        x ?? this.x,
        y ?? this.y,
        z ?? this.z,
        visibility ?? this.visibility,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x,
        'y': y,
        'z': z,
        'vis': visibility,
      };

  static PoseLandmark fromJson(Map<String, dynamic> json) => PoseLandmark(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['z'] as num? ?? 0).toDouble(),
        (json['vis'] as num? ?? json['visibility'] as num? ?? 0).toDouble(),
      );

  @override
  String toString() => 'PoseLandmark(${x.toStringAsFixed(3)}, '
      '${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)}, '
      'vis=${visibility.toStringAsFixed(2)})';
}

/// One inference result: 33 landmarks stamped on the shared monotonic clock.
///
/// [tUs] **must** come from the same monotonic source as the audio/beat clock
/// (see `MotionClock`). Mixing wall-clock and monotonic timestamps is the
/// classic way to get a beat-alignment engine that is subtly wrong only after
/// the device sleeps — which is exactly the kind of bug fixtures cannot catch.
final class PoseFrame {
  PoseFrame({
    required this.tUs,
    required this.landmarks,
    this.modelVersion = 'unknown',
  }) : assert(landmarks.length == Lm.count,
            'expected ${Lm.count} landmarks, got ${landmarks.length}');

  /// Monotonic timestamp in microseconds.
  final int tUs;

  final List<PoseLandmark> landmarks;

  /// Pinned pose model identifier, stored with every recording and every
  /// attempt so that a model upgrade can never silently reinterpret history
  /// (catalog §1: MediaPipe is still "Solutions Preview", no SLA).
  final String modelVersion;

  PoseLandmark operator [](int index) => landmarks[index];

  Vec3 point(int index) => landmarks[index].position;

  double visibility(int index) => landmarks[index].visibility;

  double get tSeconds => tUs / 1e6;

  PoseFrame copyWith({
    int? tUs,
    List<PoseLandmark>? landmarks,
    String? modelVersion,
  }) =>
      PoseFrame(
        tUs: tUs ?? this.tUs,
        landmarks: landmarks ?? this.landmarks,
        modelVersion: modelVersion ?? this.modelVersion,
      );

  /// Left/right swapped copy.
  ///
  /// Mirroring is done once, centrally, rather than by branching inside every
  /// rule: a rule written for "lead side" then works unchanged for either
  /// stance, and for mirror-mode teaching.
  PoseFrame mirrored() {
    final List<PoseLandmark> out = List<PoseLandmark>.generate(
      Lm.count,
      (int i) {
        final PoseLandmark src = landmarks[LmMirror.of(i)];
        return PoseLandmark(-src.x, src.y, src.z, src.visibility);
      },
      growable: false,
    );
    return PoseFrame(tUs: tUs, landmarks: out, modelVersion: modelVersion);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': tUs,
        'landmarks': landmarks.map((PoseLandmark l) => l.toJson()).toList(),
      };

  static PoseFrame fromJson(
    Map<String, dynamic> json, {
    String modelVersion = 'unknown',
  }) =>
      PoseFrame(
        tUs: (json['t'] as num).toInt(),
        landmarks: (json['landmarks'] as List<dynamic>)
            .map((dynamic e) =>
                PoseLandmark.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        modelVersion: modelVersion,
      );

  @override
  String toString() => 'PoseFrame(t=${tSeconds.toStringAsFixed(3)}s)';
}
