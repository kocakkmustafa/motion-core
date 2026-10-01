/// Closed set of attribute value shapes. Deliberately excludes anything
/// that could carry a large free-form payload (no arbitrary lists/maps) —
/// see 00-AILE-MIMARISI.md §8.4: only app/config/version, coarse error
/// class and duration bucket belong in an event payload.
sealed class TelemetryValue {
  const TelemetryValue();
}

class TelemetryString extends TelemetryValue {
  const TelemetryString(this.value);
  final String value;
}

class TelemetryInt extends TelemetryValue {
  const TelemetryInt(this.value);
  final int value;
}

class TelemetryBool extends TelemetryValue {
  const TelemetryBool(this.value);
  final bool value;
}

/// A bucketed duration label (e.g. `"0-5s"`, `"60s+"`) — never a raw
/// millisecond/second value, so timing data stays coarse by construction.
class TelemetryDurationBucket extends TelemetryValue {
  const TelemetryDurationBucket(this.bucketLabel);

  static const allowedLabels = {'0-5s', '5-15s', '15-60s', '60s+'};

  final String bucketLabel;
}
