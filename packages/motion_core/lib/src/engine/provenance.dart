import '../pose/confidence_gate.dart';

/// Everything that must be pinned to a measurement for it to remain
/// interpretable later (family rule M-F-07, generalised from Gravita ADR-005).
///
/// A "12° improvement over four weeks" claim is only honest if week 1 and
/// week 4 were measured by the same instrument. The instrument here is not
/// the phone — it is the model variant, the exact model weights, the rule
/// set, the metric configuration and the calibration profile. Change any of
/// them and the number moves for reasons that have nothing to do with the
/// user's body. So every attempt/measurement record carries this block, and
/// longitudinal comparison **refuses** to run across records whose blocks are
/// not comparable.
final class AttemptProvenance {
  const AttemptProvenance({
    required this.modelVariant,
    required this.modelVersion,
    required this.modelSha256,
    required this.rulesetVersion,
    required this.metricConfigVersion,
    required this.calibrationProfileId,
    this.orientationStrategy,
    this.coreVersion,
  });

  /// Which model tier ran (lite/full/heavy). Confidence thresholds are
  /// calibrated per variant (M-020): a variant change is a threshold change,
  /// so cross-variant numbers are not the same measurement.
  final PoseModelVariant modelVariant;

  /// Pinned model identifier, e.g. `pose_landmarker_heavy/float16/1`.
  final String modelVersion;

  /// SHA-256 of the actual model file. The `latest` alias was *measured*
  /// serving different weights under an unchanged file size (M-L-01) — the
  /// hash is the only version statement we trust.
  final String modelSha256;

  /// Version of the technique rule set that judged the attempt.
  final String rulesetVersion;

  /// Version of the metric configuration (angles, projections, gates).
  final String metricConfigVersion;

  /// Identifier of the camera/latency calibration profile in effect.
  final String calibrationProfileId;

  /// Which orientation pass produced the accepted frames, when the
  /// orientation-aware source was in play (ADR-001/ADR-005).
  final String? orientationStrategy;

  /// motion_core package version, for forensic completeness.
  final String? coreVersion;

  /// Why [other] cannot be compared with this record over time.
  ///
  /// Empty list = comparable. Kept as reasons rather than a bare bool so the
  /// caller can tell the user *what* changed ("your first measurement used a
  /// different model") instead of silently dropping history.
  List<String> comparabilityIssues(AttemptProvenance other) {
    final List<String> issues = <String>[];
    if (modelVariant != other.modelVariant) {
      issues.add('model variant ${modelVariant.name} vs '
          '${other.modelVariant.name} (M-020: thresholds are per-variant)');
    }
    if (modelSha256 != other.modelSha256) {
      issues.add('model weights differ (sha256 mismatch, M-L-01)');
    }
    if (rulesetVersion != other.rulesetVersion) {
      issues.add('ruleset $rulesetVersion vs ${other.rulesetVersion}');
    }
    if (metricConfigVersion != other.metricConfigVersion) {
      issues.add('metric config $metricConfigVersion vs '
          '${other.metricConfigVersion}');
    }
    if (calibrationProfileId != other.calibrationProfileId) {
      issues.add('calibration profile $calibrationProfileId vs '
          '${other.calibrationProfileId}');
    }
    return issues;
  }

  /// Family rule M-F-07: progress charts and week-over-week deltas may only
  /// be computed across records for which this returns true.
  bool isLongitudinallyComparableWith(AttemptProvenance other) =>
      comparabilityIssues(other).isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'modelVariant': modelVariant.name,
        'modelVersion': modelVersion,
        'modelSha256': modelSha256,
        'rulesetVersion': rulesetVersion,
        'metricConfigVersion': metricConfigVersion,
        'calibrationProfileId': calibrationProfileId,
        if (orientationStrategy != null)
          'orientationStrategy': orientationStrategy,
        if (coreVersion != null) 'coreVersion': coreVersion,
      };

  static AttemptProvenance fromJson(Map<String, dynamic> json) =>
      AttemptProvenance(
        modelVariant: PoseModelVariant.values.firstWhere(
          (PoseModelVariant v) => v.name == json['modelVariant'],
          orElse: () => PoseModelVariant.full,
        ),
        modelVersion: json['modelVersion'] as String? ?? 'unknown',
        modelSha256: json['modelSha256'] as String? ?? '',
        rulesetVersion: json['rulesetVersion'] as String? ?? 'unknown',
        metricConfigVersion: json['metricConfigVersion'] as String? ?? 'unknown',
        calibrationProfileId:
            json['calibrationProfileId'] as String? ?? 'uncalibrated',
        orientationStrategy: json['orientationStrategy'] as String?,
        coreVersion: json['coreVersion'] as String?,
      );

  @override
  String toString() => 'AttemptProvenance(${modelVariant.name}, '
      'ruleset $rulesetVersion, metrics $metricConfigVersion)';
}
