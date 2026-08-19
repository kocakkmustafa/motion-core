import 'telemetry_value.dart';

class TelemetryEvent {
  const TelemetryEvent({required this.name, required this.attributes});

  final String name;
  final Map<String, TelemetryValue> attributes;
}
