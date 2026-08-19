import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

class _RecordingSink implements TelemetrySink {
  final sent = <TelemetryEvent>[];
  @override
  void send(TelemetryEvent event) => sent.add(event);
}

void main() {
  late _RecordingSink sink;
  late InMemoryConsentGate consentGate;
  late TelemetryEmitter emitter;

  setUp(() {
    sink = _RecordingSink();
    consentGate = InMemoryConsentGate();
    emitter = TelemetryEmitter(allowlist: EventAllowlist.v1, consentGate: consentGate, sink: sink);
  });

  group('TelemetryEmitter.emit — every gate is fail-closed', () {
    test('an allowlisted event with consent and safe attributes reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final event = TelemetryEvent(
        name: 'session_completed',
        attributes: {'app_version': const TelemetryString('1.4.0')},
      );
      final result = emitter.emit(event);
      expect(result.rejected, isFalse);
      expect(sink.sent, [event]);
    });

    test('fail-closed: an event not in the allowlist never reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final result = emitter.emit(const TelemetryEvent(name: 'pose_frame_captured', attributes: {}));
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.notAllowlisted);
      expect(sink.sent, isEmpty);
    });

    test('fail-closed: an allowlisted event without consent never reaches the sink', () {
      final result = emitter.emit(const TelemetryEvent(name: 'session_completed', attributes: {}));
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.noConsent);
      expect(sink.sent, isEmpty);
    });

    test('fail-closed: a forbidden-content attribute key never reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final result = emitter.emit(TelemetryEvent(
        name: 'session_completed',
        attributes: {'landmarkSnapshot': const TelemetryString('ok')},
      ));
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.forbiddenKey);
      expect(sink.sent, isEmpty);
    });

    test('fail-closed: a free-text-shaped string value never reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final result = emitter.emit(TelemetryEvent(
        name: 'session_completed',
        attributes: {'app_version': const TelemetryString('felt great during this session')},
      ));
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.unsafeValueShape);
      expect(sink.sent, isEmpty);
    });

    test('revoking consent after a grant closes the gate again', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      consentGate.revoke(ConsentPurpose.productAnalytics);
      final result = emitter.emit(const TelemetryEvent(name: 'session_completed', attributes: {}));
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.noConsent);
    });
  });
}
