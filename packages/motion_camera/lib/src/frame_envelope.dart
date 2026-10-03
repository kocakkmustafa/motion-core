import 'dart:typed_data';

import 'package:motion_core/motion_core.dart';

/// Which clock the native layer stamped [CameraFrameEnvelope.tUs] with.
///
/// `monotonic` means the platform guaranteed the camera timestamps share the
/// device's monotonic timebase (iOS host clock; Android
/// `SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME`). `unknown` means the platform
/// could not guarantee it (Android `TIMESTAMP_SOURCE_UNKNOWN` — the vendor
/// picked its own zero). An `unknown` stream is still internally consistent
/// (Δt between frames is real), but it must NOT be fused with the audio/beat
/// clock without a measured offset — declaring it monotonic anyway is exactly
/// the "subtly wrong after the device sleeps" bug class `PoseFrame.tUs` warns
/// about. Beyan ≠ canlı: the domain is reported, never assumed.
enum ClockDomain { monotonic, unknown }

/// One camera frame's worth of inference results, exactly as the native layer
/// emitted it over the event channel.
///
/// Wire format (StandardMessageCodec map):
/// ```
/// {
///   't': int,          // monotonic timestamp, µs (see 'clock')
///   'w': int, 'h': int, // capture size AFTER sensor-rotation normalization
///   'model': String,    // '<libraryTag>+<modelId>', e.g.
///                       // 'mp-ios-0.10.21+pose_landmarker_full'
///   'clock': String,    // 'monotonic' | 'unknown'
///   'infUs': int,       // measured inference latency for this frame (all passes)
///   'dropped': int,     // camera frames discarded since the previous envelope
///                       // because inference was still busy (latest-wins)
///   'up':  Float32List(132)?,  // upright pass; ABSENT = pass not planned,
///   'inv': Float32List(132)?,  // null = pass ran, model saw no person
/// }
/// ```
/// Landmarks are packed `[x, y, z, visibility] × 33` in `Lm` index order,
/// in normalized image space of the emitted `w×h` frame. The inverted pass is
/// already mapped back to the original frame of reference by the native layer
/// (`x→1-x, y→1-y`, no index swap — in-plane rotation is not a reflection),
/// so both passes speak one coordinate language.
final class CameraFrameEnvelope {
  CameraFrameEnvelope({
    required this.tUs,
    required this.size,
    required this.modelVersion,
    required this.clockDomain,
    required this.inferenceUs,
    required this.dropped,
    this.ownerId,
    this.generation,
    required Map<BodyOrientation, PoseFrame?> passes,
  }) : _passes = passes;

  final int tUs;
  final FrameSize size;
  final String modelVersion;
  final ClockDomain clockDomain;
  final String? ownerId;
  final int? generation;

  /// Measured wall time spent in inference for this frame, µs (sum over the
  /// passes that ran). Measured on the native side, never estimated here.
  final int inferenceUs;

  /// Camera frames that arrived while inference was busy and were discarded
  /// under the latest-wins policy. Nonzero values are the honest record of
  /// "the camera outran the model" — the engine's judged-frame ratio derives
  /// from this, not from a declared fps.
  final int dropped;

  final Map<BodyOrientation, PoseFrame?> _passes;

  /// Whether [orientation]'s pass was run for this frame at all.
  bool ran(BodyOrientation orientation) => _passes.containsKey(orientation);

  /// Result of [orientation]'s pass. Throws if the pass was not planned —
  /// asking for a pass that never ran is a planning bug upstream, and
  /// answering it with `null` would disguise it as "no person".
  PoseFrame? pass(BodyOrientation orientation) {
    if (!_passes.containsKey(orientation)) {
      throw StateError(
        'pass ${orientation.name} was not run for frame t=$tUs — '
        'the pass plan and the engine expectation have diverged',
      );
    }
    return _passes[orientation];
  }

  static const int _floatsPerFrame = 132; // 33 landmarks × (x, y, z, vis)

  static PoseFrame _unpack(Float32List data, int tUs, String modelVersion) {
    if (data.length != _floatsPerFrame) {
      throw FormatException(
        'landmark buffer has ${data.length} floats, expected '
        '$_floatsPerFrame (33 × [x, y, z, vis])',
      );
    }
    final List<PoseLandmark> landmarks = List<PoseLandmark>.generate(
      Lm.count,
      (int i) => PoseLandmark(
        data[i * 4],
        data[i * 4 + 1],
        data[i * 4 + 2],
        data[i * 4 + 3],
      ),
      growable: false,
    );
    return PoseFrame(
      tUs: tUs,
      landmarks: landmarks,
      modelVersion: modelVersion,
    );
  }

  /// Decodes one event-channel payload. Fails loudly on malformed input:
  /// a half-decoded envelope fed to the engine would be a measurement lie.
  static CameraFrameEnvelope decode(Object? event) {
    if (event is! Map<Object?, Object?>) {
      throw FormatException('envelope is not a map: ${event.runtimeType}');
    }
    final int tUs = event['t'] as int;
    final String model = event['model'] as String;
    final String clock = event['clock'] as String;
    final ClockDomain domain = switch (clock) {
      'monotonic' => ClockDomain.monotonic,
      'unknown' => ClockDomain.unknown,
      _ => throw FormatException('unrecognized clock domain "$clock"'),
    };
    final Map<BodyOrientation, PoseFrame?> passes =
        <BodyOrientation, PoseFrame?>{};
    for (final (String key, BodyOrientation o) in <(String, BodyOrientation)>[
      ('up', BodyOrientation.upright),
      ('inv', BodyOrientation.inverted),
    ]) {
      if (!event.containsKey(key)) continue;
      final Object? raw = event[key];
      passes[o] = raw == null ? null : _unpack(raw as Float32List, tUs, model);
    }
    if (passes.isEmpty) {
      throw const FormatException(
        'envelope carries no passes — the native layer must run at least '
        'one orientation per emitted frame',
      );
    }
    return CameraFrameEnvelope(
      tUs: tUs,
      size: FrameSize(event['w'] as int, event['h'] as int),
      modelVersion: model,
      clockDomain: domain,
      inferenceUs: event['infUs'] as int,
      dropped: event['dropped'] as int,
      ownerId: event['ownerId'] as String?,
      generation: event['generation'] as int?,
      passes: passes,
    );
  }
}
