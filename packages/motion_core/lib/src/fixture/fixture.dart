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

  Map<String, dynamic> toJson() => <String, dynamic>{
        'device': device,
        'fps': fps,
        'lighting': lighting,
        'bodyProfile': bodyProfile,
        'cameraSetup': cameraSetup,
        if (notes.isNotEmpty) 'notes': notes,
      };

  static RecordingMeta fromJson(Map<String, dynamic> json) => RecordingMeta(
        device: json['device'] as String? ?? 'unknown',
        fps: (json['fps'] as num? ?? 30).toInt(),
        lighting: json['lighting'] as String? ?? 'unknown',
        bodyProfile: json['bodyProfile'] as String? ?? 'unknown',
        cameraSetup: json['cameraSetup'] as String? ?? 'unknown',
        notes: json['notes'] as String? ?? '',
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
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;

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
      };

  String encode({bool pretty = false}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  static Fixture fromJson(Map<String, dynamic> json) {
    final int version = (json['schemaVersion'] as num? ?? 1).toInt();
    if (version > currentSchemaVersion) {
      throw FormatException(
        'fixture schemaVersion $version is newer than supported '
        '$currentSchemaVersion — upgrade motion_core before replaying it',
      );
    }
    final String modelVersion = json['modelVersion'] as String? ?? 'unknown';
    return Fixture(
      schemaVersion: version,
      app: json['app'] as String? ?? 'unknown',
      technique: json['technique'] as String? ?? 'unknown',
      modelVersion: modelVersion,
      recordingMeta: RecordingMeta.fromJson(
        (json['recordingMeta'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      frames: ((json['frames'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic e) => PoseFrame.fromJson(
                e as Map<String, dynamic>,
                modelVersion: modelVersion,
              ))
          .toList(growable: false),
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
