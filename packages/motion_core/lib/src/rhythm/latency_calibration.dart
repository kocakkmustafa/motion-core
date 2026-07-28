import 'audio_timeline.dart';

/// Per-route store of measured latency profiles (family module M-F-08).
///
/// Latency is a property of the audio *route*, not the device: a profile
/// calibrated on the speaker is worthless the moment the user pairs
/// headphones. So profiles are stored per route, the active route decides
/// which profile is in effect, and a route change with no stored profile
/// means "re-prompt the tap test", never "reuse the old number".
final class LatencyCalibrationStore {
  LatencyCalibrationStore({Map<AudioRoute, AudioLatencyProfile>? profiles})
      : _profiles = Map<AudioRoute, AudioLatencyProfile>.of(
            profiles ?? const <AudioRoute, AudioLatencyProfile>{});

  final Map<AudioRoute, AudioLatencyProfile> _profiles;

  AudioLatencyProfile? profileFor(AudioRoute route) => _profiles[route];

  /// Whether timing-scored work on [route] must be preceded by calibration.
  ///
  /// Mirrors the family's assessment-mode hard gate (M-F-09): measurement
  /// contexts refuse to start uncalibrated; free-practice modes may proceed
  /// with a visible warning band instead.
  bool needsCalibration(AudioRoute route) =>
      !(_profiles[route]?.isCalibrated ?? false);

  void store(AudioLatencyProfile profile) {
    _profiles[profile.route] = profile;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        for (final MapEntry<AudioRoute, AudioLatencyProfile> e
            in _profiles.entries)
          e.key.name: e.value.toJson(),
      };

  static LatencyCalibrationStore fromJson(Map<String, dynamic> json) =>
      LatencyCalibrationStore(profiles: <AudioRoute, AudioLatencyProfile>{
        for (final MapEntry<String, dynamic> e in json.entries)
          AudioRoute.values.firstWhere(
            (AudioRoute r) => r.name == e.key,
            orElse: () => AudioRoute.unknown,
          ): AudioLatencyProfile.fromJson(e.value as Map<String, dynamic>),
      });
}

/// Result of one tap-test calibration run.
final class TapTestResult {
  const TapTestResult({
    required this.accepted,
    required this.offsetUs,
    required this.sampleCount,
    required this.rejectedCount,
    required this.spreadUs,
    required this.reason,
  });

  /// Whether the run produced a trustworthy offset.
  final bool accepted;

  /// Robust end-to-end residual offset (median of clean samples). Positive
  /// means the user's taps land after the scheduled click times — i.e. the
  /// audio path is late by this much.
  final int offsetUs;

  final int sampleCount;
  final int rejectedCount;

  /// Median absolute deviation of the clean samples — the honesty number. A
  /// tight spread means a real constant latency was measured; a wide one
  /// means the user was not really tapping along.
  final int spreadUs;

  final String reason;
}

/// The measurement half of the calibration wizard, as pure logic.
///
/// The platform plays clicks at known scheduled times and reports the user's
/// tap timestamps; both sides are stamped on the shared monotonic clock. This
/// class matches taps to clicks and produces a robust offset estimate. It
/// deliberately uses median + MAD rather than mean + stddev: one distracted
/// tap must not shift every timing judgement in the product.
final class TapTestCalibrator {
  const TapTestCalibrator({
    this.minSamples = 8,
    this.maxMatchWindowUs = 350000,
    this.outlierFactor = 3.0,
    this.maxAcceptableSpreadUs = 60000,
  });

  /// Fewer clean samples than this and the run is rejected outright.
  final int minSamples;

  /// A tap farther than this from every click matches nothing (missed tap or
  /// double tap) and is dropped before estimation.
  final int maxMatchWindowUs;

  /// Samples farther than this many MADs from the median are rejected.
  final double outlierFactor;

  /// A clean-sample spread above this rejects the whole run: the number
  /// would be *a* number, but not a latency measurement.
  final int maxAcceptableSpreadUs;

  TapTestResult evaluate({
    required List<int> scheduledClickUs,
    required List<int> tapUs,
  }) {
    // 1. Pair every tap with its nearest click, inside the match window.
    final List<int> offsets = <int>[];
    for (final int tap in tapUs) {
      int? best;
      for (final int click in scheduledClickUs) {
        final int d = tap - click;
        if (d.abs() <= maxMatchWindowUs &&
            (best == null || d.abs() < best.abs())) {
          best = d;
        }
      }
      if (best != null) offsets.add(best);
    }
    if (offsets.length < minSamples) {
      return TapTestResult(
        accepted: false,
        offsetUs: 0,
        sampleCount: offsets.length,
        rejectedCount: tapUs.length - offsets.length,
        spreadUs: 0,
        reason: 'only ${offsets.length}/$minSamples usable taps',
      );
    }

    // 2. Robust centre + spread, then one outlier-rejection pass.
    final int median = _median(offsets);
    final List<int> deviations =
        offsets.map((int o) => (o - median).abs()).toList();
    final int mad = _median(deviations);
    final int cutoff = (outlierFactor * (mad == 0 ? 1 : mad)).round();
    final List<int> clean =
        offsets.where((int o) => (o - median).abs() <= cutoff).toList();
    final int rejected = tapUs.length - clean.length;

    if (clean.length < minSamples) {
      return TapTestResult(
        accepted: false,
        offsetUs: 0,
        sampleCount: clean.length,
        rejectedCount: rejected,
        spreadUs: mad,
        reason: 'too many outliers (${clean.length}/$minSamples clean)',
      );
    }

    final int offset = _median(clean);
    final int spread = _median(
        clean.map((int o) => (o - offset).abs()).toList());
    if (spread > maxAcceptableSpreadUs) {
      return TapTestResult(
        accepted: false,
        offsetUs: offset,
        sampleCount: clean.length,
        rejectedCount: rejected,
        spreadUs: spread,
        reason: 'spread ${spread ~/ 1000}ms exceeds '
            '${maxAcceptableSpreadUs ~/ 1000}ms — taps were not consistent',
      );
    }

    return TapTestResult(
      accepted: true,
      offsetUs: offset,
      sampleCount: clean.length,
      rejectedCount: rejected,
      spreadUs: spread,
      reason: 'ok',
    );
  }

  /// Fold an accepted result into a profile for [route].
  AudioLatencyProfile profileFrom(
    TapTestResult result, {
    required AudioRoute route,
    int platformReportedLatencyUs = 0,
  }) {
    assert(result.accepted, 'only accepted results become profiles');
    return AudioLatencyProfile(
      outputLatencyUs: platformReportedLatencyUs,
      // The tap test measures end-to-end; what we store as the user offset is
      // the residual beyond what the platform already claims.
      userOffsetUs: result.offsetUs - platformReportedLatencyUs,
      route: route,
    );
  }

  static int _median(List<int> values) {
    final List<int> sorted = List<int>.of(values)..sort();
    final int n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
  }
}
