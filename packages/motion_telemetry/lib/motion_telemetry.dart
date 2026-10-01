/// Domain-independent telemetry gate for the Yula Motion family. See
/// pubspec.yaml for scope and the explicit prohibition on raw sensor/
/// health/content payloads living in this package.
library;

export 'src/consent_gate.dart';
export 'src/diagnostic_exporter.dart';
export 'src/event_allowlist.dart';
export 'src/redactor.dart';
export 'src/telemetry_attribute_policy.dart';
export 'src/telemetry_emitter.dart';
export 'src/telemetry_event.dart';
export 'src/telemetry_value.dart';
