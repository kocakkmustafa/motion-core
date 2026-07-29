import 'dart:convert';

import '../pose/pose_frame.dart';

/// Conditions a fixture was recorded under.
///
/// Recorded in full because a fixture without provenance is worse than no
/// fixture: a threshold tuned on bright-room, tight-clothing, flagship-phone
/// footage will quietly fail in a dim living room, and without this metadata
/// nobody can tell that is what happened.
final class RecordingMeta {
  const RecordingMeta({
    this.device = 'unknown',
    this.fps = 30,
    this.lighting = 'unknown',
    this.bodyProfile = 'unknown',
    this.cameraSetup = 'unknown',
    this.notes = '',
    this.technique,
    this.resolution,
  });

  final String device;
  final int fps;

  /// e.g. `bright`, `dim`, `backlit`, `mixed`.
  final String lighting;

  /// e.g. `tall-slim`, `short-broad`, `child`, `loose-clothing`.
  final String bodyProfile;

  /// e.g. `phone-on-floor-2m`, `tripod-1.2m-3m`, `tilted`.
  final String cameraSetup;

  final String notes;

  /// v2 free-form sources (CLI / harvest) carry the technique here rather
  /// than at the top level.
  final String? technique;

  /// Source frame size as `"1920x1080"`, when the producer recorded it.
  ///
  /// Load-bearing, not decorative: normalized landmarks from a non-square
  /// frame are anisotropic, and every angle measured on them bends with the
  /// aspect ratio (J-028). A consumer that has this must go through
  /// [frameSize]/`toIsotropic` before measuring.
  final String? resolution;

  /// [resolution] parsed, or null when absent/unparseable.
  FrameSize? get frameSize {
    final String? r = resolution;
    if (r == null) return null;
    final List<String> parts = r.split('x');
    if (parts.length != 2) return null;
    final int? w = int.tryParse(parts[0]);
    final int? h = int.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return FrameSize(w, h);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'device': device,
        'fps': fps,
        'lighting': lighting,
        'bodyProfile': bodyProfile,
        'cameraSetup': cameraSetup,
        if (notes.isNotEmpty) 'notes': notes,
        if (technique != null) 'technique': technique,
        if (resolution != null) 'resolution': resolution,
      };

  /// Accepts both this writer's camelCase keys and the Python pipeline's
  /// snake_case dataclass dump — one schema, two producers (M-F-46 spirit:
  /// the reader bridges at the boundary so nothing downstream forks).
  static RecordingMeta fromJson(Map<String, dynamic> json) {
    String str(String camel, String snake, String fallback) =>
        (json[camel] ?? json[snake]) as String? ?? fallback;
    return RecordingMeta(
      device: json['device'] as String? ?? 'unknown',
      fps: (json['fps'] as num? ?? 30).round(),
      lighting: json['lighting'] as String? ?? 'unknown',
      bodyProfile: str('bodyProfile', 'body_profile', 'unknown'),
      cameraSetup: str('cameraSetup', 'camera_setup', 'unknown'),
      notes: json['notes'] as String? ?? '',
      technique: json['technique'] as String?,
      resolution: json['resolution'] as String?,
    );
  }
}

/// Where a harvested fixture came from (M-F-07/M-F-13, schema v2).
///
/// The reference pipeline's chain of custody starts here: `channel` (or
/// failing that `sourceUrl`) is what [ReferenceTake.source] and the
/// `minSources` instructor gate count as "one teacher".
final class ProvenanceInfo {
  const ProvenanceInfo({
    this.sourceUrl,
    this.license,
    this.channel,
    this.extractor,
    this.raw = const <String, dynamic>{},
  });

  final String? sourceUrl;
  final String? license;

  /// Publishing channel / instructor identity, when the harvester knew it.
  final String? channel;

  final String? extractor;

  /// The full block as written — forward-compatible with fields this
  /// version does not model yet.
  final Map<String, dynamic> raw;

  /// The identity the instructor-counting gates should use, best-first.
  String? get sourceIdentity => channel ?? sourceUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...raw,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (license != null) 'license': license,
        if (channel != null) 'channel': channel,
        if (extractor != null) 'extractor': extractor,
      };

  static ProvenanceInfo fromJson(Map<String, dynamic> json) => ProvenanceInfo(
        sourceUrl: json['sourceUrl'] as String?,
        license: json['license'] as String?,
        channel: json['channel'] as String?,
        extractor: json['extractor'] as String?,
        raw: json,
      );
}

/// A human-annotated interval: either a technique phase or a known error.
final class FixtureLabel {
  const FixtureLabel({
    required this.tStartUs,
    required this.tEndUs,
    this.phase,
    this.errorCode,
    this.confidence = 1.0,
    this.annotator = 'unknown',
    this.beatIndex,
  });

  final int tStartUs;
  final int tEndUs;

  /// Expected phase id, when this label asserts correct execution.
  final String? phase;

  /// Expected error code, when this label asserts a specific fault.
  final String? errorCode;

  /// Annotator's own confidence — low-confidence labels may be excluded from
  /// strict assertions while still being useful as regression canaries.
  final double confidence;

  final String annotator;

  /// Beat this interval belongs to, for rhythm-scored material.
  final int? beatIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tStart': tStartUs,
        'tEnd': tEndUs,
        if (phase != null) 'phase': phase,
        if (errorCode != null) 'errorCode': errorCode,
        'confidence': confidence,
        'annotator': annotator,
        if (beatIndex != null) 'beatIndex': beatIndex,
      };

  static FixtureLabel fromJson(Map<String, dynamic> json) => FixtureLabel(
        tStartUs: (json['tStart'] as num).toInt(),
        tEndUs: (json['tEnd'] as num).toInt(),
        phase: json['phase'] as String?,
        errorCode: json['errorCode'] as String?,
        confidence: (json['confidence'] as num? ?? 1.0).toDouble(),
        annotator: json['annotator'] as String? ?? 'unknown',
        beatIndex: (json['beatIndex'] as num?)?.toInt(),
      );
}

/// The family-wide fixture format (`10-ARAC-KATALOGU.md` §6).
///
/// One schema for all five apps means one replay harness, one annotation tool
/// and one migration path — an app that invents its own format also inherits
/// the cost of maintaining its own tooling forever.
final class Fixture {
  const Fixture({
    required this.app,
    required this.technique,
    required this.frames,
    this.schemaVersion = currentSchemaVersion,
    this.modelVersion = 'unknown',
    this.recordingMeta = const RecordingMeta(),
    this.labels = const <FixtureLabel>[],
    this.beatTimesUs = const <int>[],
    this.bpm,
    this.provenance,
    this.undetectedFrameCount = 0,
  });

  /// What this writer emits.
  static const int currentSchemaVersion = 1;

  /// What this reader accepts — kept in lockstep with the Python pipeline's
  /// `READABLE_SCHEMA_VERSIONS`. v2 adds free-form meta and the optional
  /// `provenance` block, and its frames arrive in the harvest pipeline's
  /// compact dialect (`t` in ms, `lm` rows) which the reader bridges.
  static const Set<int> readableSchemaVersions = <int>{1, 2};

  final int schemaVersion;

  /// Harvest chain-of-custody (schema v2); null for locally recorded takes.
  final ProvenanceInfo? provenance;

  /// v2 frames the decoder dropped because the model found no pose in them.
  ///
  /// Nonzero means [frames] has timestamp gaps — coverage math over
  /// `frames.length` alone would silently overstate the recording.
  final int undetectedFrameCount;

  /// Owning app (`choreia`, `lissom`, ...) or `motion-core` for shared ones.
  final String app;

  /// Technique/step identifier this recording exercises.
  final String technique;

  final String modelVersion;
  final RecordingMeta recordingMeta;
  final List<PoseFrame> frames;
  final List<FixtureLabel> labels;

  /// Annotated beat timestamps, when the recording was made to music or a
  /// metronome. Empty for rhythm-free material.
  final List<int> beatTimesUs;

  final double? bpm;

  int get durationUs =>
      frames.isEmpty ? 0 : frames.last.tUs - frames.first.tUs;

  double get measuredFps {
    if (frames.length < 2) return 0;
    return (frames.length - 1) * 1e6 / durationUs;
  }

  List<FixtureLabel> get errorLabels =>
      labels.where((FixtureLabel l) => l.errorCode != null).toList(growable: false);

  List<FixtureLabel> get phaseLabels =>
      labels.where((FixtureLabel l) => l.phase != null).toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'app': app,
        'technique': technique,
        'modelVersion': modelVersion,
        'recordingMeta': recordingMeta.toJson(),
        'frames': frames.map((PoseFrame f) => f.toJson()).toList(),
        'labels': labels.map((FixtureLabel l) => l.toJson()).toList(),
        if (beatTimesUs.isNotEmpty) 'beatTimesUs': beatTimesUs,
        if (bpm != null) 'bpm': bpm,
        if (provenance != null) 'provenance': provenance!.toJson(),
      };

  String encode({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  /// Decodes one frame of the v2 harvest dialect:
  /// `{t: <ms>, detected: bool, lm: [[x,y,z,visibility,presence], ...]}`.
  ///
  /// `presence` is dropped, deliberately: [PoseLandmark] carries one
  /// confidence channel and every gate threshold in the family was
  /// calibrated on `visibility` — folding presence in (e.g. multiplying)
  /// would silently shift all of them. Undetected frames return null and are
  /// dropped by the caller — inventing 33 zero-position landmarks to satisfy
  /// the frame contract would hand fake geometry to any consumer that
  /// forgets to check visibility; the gap stays visible as a timestamp jump
  /// plus [undetectedFrameCount].
  static PoseFrame? _frameFromCompact(
    Map<String, dynamic> json, {
    required String modelVersion,
  }) {
    final int tUs = ((json['t'] as num) * 1000).round();
    if (json['detected'] != true) return null;
    return PoseFrame(
      tUs: tUs,
      landmarks: ((json['lm'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic row) {
        final List<dynamic> p = row as List<dynamic>;
        return PoseLandmark(
          (p[0] as num).toDouble(),
          (p[1] as num).toDouble(),
          (p[2] as num).toDouble(),
          p.length > 3 ? (p[3] as num).toDouble() : 0,
        );
      }).toList(growable: false),
      modelVersion: modelVersion,
    );
  }

  static Fixture fromJson(Map<String, dynamic> json) {
    final int version = (json['schemaVersion'] as num? ?? 1).toInt();
    if (!readableSchemaVersions.contains(version)) {
      throw FormatException(
        'fixture schemaVersion $version is newer than supported '
        '${readableSchemaVersions.reduce((int a, int b) => a > b ? a : b)} '
        '— upgrade motion_core before replaying it',
      );
    }
    final String modelVersion = json['modelVersion'] as String? ?? 'unknown';
    final RecordingMeta meta = RecordingMeta.fromJson(
      (json['recordingMeta'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
    int undetected = 0;
    final List<PoseFrame> frames = <PoseFrame>[];
    for (final dynamic e in (json['frames'] as List<dynamic>?) ?? <dynamic>[]) {
      final Map<String, dynamic> f = e as Map<String, dynamic>;
      if (f.containsKey('landmarks')) {
        frames.add(PoseFrame.fromJson(f, modelVersion: modelVersion));
        continue;
      }
      final PoseFrame? decoded =
          _frameFromCompact(f, modelVersion: modelVersion);
      if (decoded == null) {
        undetected++;
      } else {
        frames.add(decoded);
      }
    }
    return Fixture(
      schemaVersion: version,
      app: json['app'] as String? ?? 'unknown',
      // v2 free-form sources carry technique inside the meta; the shot-list
      // convention put the test id there instead.
      technique: json['technique'] as String? ??
          meta.technique ??
          (json['recordingMeta'] is Map<String, dynamic>
              ? (json['recordingMeta'] as Map<String, dynamic>)['test']
                  as String?
              : null) ??
          'unknown',
      modelVersion: modelVersion,
      recordingMeta: meta,
      provenance: json['provenance'] is Map<String, dynamic>
          ? ProvenanceInfo.fromJson(json['provenance'] as Map<String, dynamic>)
          : null,
      undetectedFrameCount: undetected,
      frames: frames,
      labels: ((json['labels'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic e) => FixtureLabel.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      beatTimesUs: ((json['beatTimesUs'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic e) => (e as num).toInt())
          .toList(growable: false),
      bpm: (json['bpm'] as num?)?.toDouble(),
    );
  }

  static Fixture decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, dynamic>);
}
