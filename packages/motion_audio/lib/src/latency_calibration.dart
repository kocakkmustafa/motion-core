/// A single per-route latency measurement. Audio routes (wired, built-in,
/// Bluetooth) drift over a session — a Bluetooth route's reported latency
/// has been observed to move ~70ms within one minute — so a calibration is
/// only trusted for the exact [routeId] it was measured on, never assumed
/// to generalize.
class LatencyCalibration {
  const LatencyCalibration({
    required this.measuredLatency,
    required this.calibratedAt,
    required this.routeId,
  });

  final Duration measuredLatency;
  final DateTime calibratedAt;
  final String routeId;
}

/// Per-route calibration cache. Fail-closed: a route that has never been
/// measured returns `null` — this store never guesses or defaults to zero
/// latency, since an uncalibrated route silently scored at zero latency
/// would tell every user on time they are "late".
class LatencyCalibrationStore {
  final _byRoute = <String, LatencyCalibration>{};

  LatencyCalibration? calibrationFor(String routeId) => _byRoute[routeId];

  /// Records a calibration, replacing any prior value for the same route.
  void record(LatencyCalibration calibration) {
    _byRoute[calibration.routeId] = calibration;
  }
}
