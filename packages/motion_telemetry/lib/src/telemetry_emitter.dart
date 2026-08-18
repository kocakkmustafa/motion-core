import 'consent_gate.dart';
import 'event_allowlist.dart';
import 'redactor.dart';
import 'telemetry_event.dart';
import 'telemetry_value.dart';

enum RejectReason { notAllowlisted, noConsent, forbiddenKey, unsafeValueShape }

class EmitResult {
  const EmitResult.accepted()
      : rejected = false,
        reason = null;

  const EmitResult.rejected(RejectReason this.reason) : rejected = true;

  final bool rejected;
  final RejectReason? reason;
}

abstract class TelemetrySink {
  void send(TelemetryEvent event);
}

/// The single choke point every product-analytics event must pass through.
/// Fail-closed at every gate, checked in order: not on the allowlist, no
/// consent, a forbidden attribute key, or a value not shaped like a safe
/// token — any one of these silently drops the event before it ever
/// reaches [sink].
class TelemetryEmitter {
  TelemetryEmitter({
    required this.allowlist,
    required this.consentGate,
    required this.sink,
    Redactor? redactor,
  }) : redactor = redactor ?? Redactor();

  final EventAllowlist allowlist;
  final ConsentGate consentGate;
  final TelemetrySink sink;
  final Redactor redactor;

  EmitResult emit(TelemetryEvent event) {
    if (!allowlist.allows(event.name)) {
      return const EmitResult.rejected(RejectReason.notAllowlisted);
    }
    if (!consentGate.hasConsent(ConsentPurpose.productAnalytics)) {
      return const EmitResult.rejected(RejectReason.noConsent);
    }
    for (final entry in event.attributes.entries) {
      if (!redactor.allowsKey(entry.key)) {
        return const EmitResult.rejected(RejectReason.forbiddenKey);
      }
      final value = entry.value;
      if (value is TelemetryString && !redactor.allowsStringValue(value.value)) {
        return const EmitResult.rejected(RejectReason.unsafeValueShape);
      }
    }
    sink.send(event);
    return const EmitResult.accepted();
  }
}
