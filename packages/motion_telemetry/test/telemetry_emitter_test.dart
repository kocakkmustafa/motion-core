import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

class _RecordingSink implements TelemetrySink {
  final sent = <TelemetryEvent>[];
  @override
  void send(TelemetryEvent event) => sent.add(event);
}

class _MutableTelemetryString extends TelemetryString {
  _MutableTelemetryString(this.current) : super(current);

  String current;

  @override
  String get value => current;
}

Object _plainValue(TelemetryValue value) => switch (value) {
  TelemetryString() => value.value,
  TelemetryInt() => value.value,
  TelemetryBool() => value.value,
  TelemetryDurationBucket() => value.bucketLabel,
};

Map<String, Object> _plainAttributes(Map<String, TelemetryValue> attributes) =>
    attributes.map((key, value) => MapEntry(key, _plainValue(value)));

Map<String, TelemetryValue> _contentValidationAttributes({
  String result = 'ready',
  Map<String, TelemetryValue> extra = const {},
}) => <String, TelemetryValue>{
  'appVersion': const TelemetryString('1.2.0'),
  'buildNumber': const TelemetryInt(42),
  'schemaVersion': const TelemetryInt(1),
  'contentVersion': const TelemetryString('1.0.0'),
  'result': TelemetryString(result),
  ...extra,
};

// Fixed independent policy: no field is derived from an emitted event.
const _approvedPolicy = TelemetryAttributePolicy(
  events: {
    'onboarding_complete': TelemetryEventAttributePolicy(fields: {}),
    'device_check_result': TelemetryEventAttributePolicy(fields: {}),
    'session_started': TelemetryEventAttributePolicy(fields: {}),
    'value_event': TelemetryEventAttributePolicy(fields: {}),
    'paywall_viewed': TelemetryEventAttributePolicy(fields: {}),
    'purchase_state_changed': TelemetryEventAttributePolicy(fields: {}),
    'restore_state_changed': TelemetryEventAttributePolicy(fields: {}),
    'custom_metric': TelemetryEventAttributePolicy(fields: {}),
    'session_completed': TelemetryEventAttributePolicy(
      fields: {
        'app_version': TelemetryTokenFieldPolicy(allowedValues: {'1.4.0'}),
        'is_first_session': TelemetryBoolFieldPolicy(),
        'duration_bucket': TelemetryDurationFieldPolicy(),
      },
    ),
    'content_validation_result': TelemetryEventAttributePolicy(
      fields: {
        'appVersion': TelemetryTokenFieldPolicy(allowedValues: {'1.2.0'}),
        'buildNumber': TelemetryIntFieldPolicy(min: 0, max: 999999),
        'schemaVersion': TelemetryIntFieldPolicy(min: 1, max: 999),
        'contentVersion': TelemetryTokenFieldPolicy(allowedValues: {'1.0.0'}),
        'result': TelemetryTokenFieldPolicy(
          allowedValues: {'ready', 'degraded', 'blocked'},
        ),
        'errorCode': TelemetryTokenFieldPolicy(
          allowedValues: {'hashMismatch', 'timeout', 'capability'},
        ),
        'contentId': TelemetryTokenFieldPolicy(allowedValues: {'lesson-one'}),
        'expectedHashPrefix': TelemetryTokenFieldPolicy(
          allowedValues: {'0123456789ab'},
        ),
        'actualHashPrefix': TelemetryTokenFieldPolicy(
          allowedValues: {'abcdef012345'},
        ),
      },
    ),
  },
);

void main() {
  late _RecordingSink sink;
  late InMemoryConsentGate consentGate;
  late TelemetryEmitter emitter;

  setUp(() {
    sink = _RecordingSink();
    consentGate = InMemoryConsentGate();
    emitter = TelemetryEmitter(
      allowlist: EventAllowlist.v2,
      attributePolicy: _approvedPolicy,
      consentGate: consentGate,
      sink: sink,
    );
  });

  group('TelemetryEmitter.emit — every gate is fail-closed', () {
    test(
      'an allowlisted event with consent and safe attributes reaches the sink',
      () {
        consentGate.grant(ConsentPurpose.productAnalytics);
        final event = TelemetryEvent(
          name: 'session_completed',
          attributes: {
            'app_version': const TelemetryString('1.4.0'),
            'is_first_session': const TelemetryBool(true),
            'duration_bucket': const TelemetryDurationBucket('0-5s'),
          },
        );
        final result = emitter.emit(event);
        expect(result.rejected, isFalse);
        expect(sink.sent.single.name, event.name);
        expect(
          _plainAttributes(sink.sent.single.attributes),
          _plainAttributes(event.attributes),
        );
      },
    );

    test('session completed preserves the legacy empty-event contract', () {
      consentGate.grant(ConsentPurpose.productAnalytics);

      final result = emitter.emit(
        const TelemetryEvent(name: 'session_completed', attributes: {}),
      );

      expect(result.rejected, isFalse);
      expect(sink.sent.single.attributes, isEmpty);
    });

    test('session completed enforces semantic field types and values', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final invalidAttributes = <Map<String, TelemetryValue>>[
        const {'app_version': TelemetryInt(33)},
        const {'app_version': TelemetryString('33')},
        const {'is_first_session': TelemetryInt(1)},
        const {'duration_bucket': TelemetryInt(87)},
        const {'duration_bucket': TelemetryDurationBucket('10-5s')},
      ];

      for (final attributes in invalidAttributes) {
        final result = emitter.emit(
          TelemetryEvent(name: 'session_completed', attributes: attributes),
        );
        expect(result.reason, RejectReason.invalidEventShape);
      }
      expect(sink.sent, isEmpty);
    });

    test('custom allowlist cannot widen the session completed schema', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final customEmitter = TelemetryEmitter(
        allowlist: EventAllowlist(
          version: 99,
          eventNames: const {'session_completed'},
          attributeNamesByEvent: const {
            'session_completed': {
              'app_version',
              'is_first_session',
              'duration_bucket',
              'opaque_metric',
            },
          },
        ),
        attributePolicy: _approvedPolicy,
        consentGate: consentGate,
        sink: sink,
      );

      const invalidEvents = [
        TelemetryEvent(
          name: 'session_completed',
          attributes: {'opaque_metric': TelemetryInt(123456)},
        ),
        TelemetryEvent(
          name: 'session_completed',
          attributes: {'app_version': TelemetryInt(123456)},
        ),
      ];

      for (final event in invalidEvents) {
        final result = customEmitter.emit(event);
        expect(result.reason, RejectReason.invalidEventShape);
      }
      expect(sink.sent, isEmpty);
    });

    test('schema-less built-in events preserve their empty-event contract', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      const eventNames = {
        'onboarding_complete',
        'device_check_result',
        'session_started',
        'value_event',
        'paywall_viewed',
        'purchase_state_changed',
        'restore_state_changed',
      };

      for (final eventName in eventNames) {
        final result = emitter.emit(
          TelemetryEvent(name: eventName, attributes: const {}),
        );
        expect(result.rejected, isFalse, reason: eventName);
      }

      expect(sink.sent.map((event) => event.name), eventNames);
      expect(sink.sent.every((event) => event.attributes.isEmpty), isTrue);
    });

    test(
      'custom allowlist cannot add attributes without a semantic schema',
      () {
        consentGate.grant(ConsentPurpose.productAnalytics);
        final customEmitter = TelemetryEmitter(
          allowlist: EventAllowlist(
            version: 99,
            eventNames: const {'session_started', 'custom_metric'},
            attributeNamesByEvent: const {
              'session_started': {'opaque_metric'},
              'custom_metric': {'opaque_metric'},
            },
          ),
          attributePolicy: _approvedPolicy,
          consentGate: consentGate,
          sink: sink,
        );

        for (final eventName in const ['session_started', 'custom_metric']) {
          final markerResult = customEmitter.emit(
            TelemetryEvent(name: eventName, attributes: const {}),
          );
          expect(markerResult.rejected, isFalse, reason: eventName);
        }

        for (final eventName in const ['session_started', 'custom_metric']) {
          final result = customEmitter.emit(
            TelemetryEvent(
              name: eventName,
              attributes: const {'opaque_metric': TelemetryInt(123456)},
            ),
          );
          expect(
            result.reason,
            RejectReason.invalidEventShape,
            reason: eventName,
          );
        }

        expect(sink.sent, hasLength(2));
        expect(sink.sent.every((event) => event.attributes.isEmpty), isTrue);
      },
    );

    test(
      'fail-closed: an event not in the allowlist never reaches the sink',
      () {
        consentGate.grant(ConsentPurpose.productAnalytics);
        final result = emitter.emit(
          const TelemetryEvent(name: 'pose_frame_captured', attributes: {}),
        );
        expect(result.rejected, isTrue);
        expect(result.reason, RejectReason.notAllowlisted);
        expect(sink.sent, isEmpty);
      },
    );

    test(
      'fail-closed: an allowlisted event without consent never reaches the sink',
      () {
        final result = emitter.emit(
          const TelemetryEvent(name: 'session_completed', attributes: {}),
        );
        expect(result.rejected, isTrue);
        expect(result.reason, RejectReason.noConsent);
        expect(sink.sent, isEmpty);
      },
    );

    test(
      'fail-closed: a forbidden-content attribute key never reaches the sink',
      () {
        consentGate.grant(ConsentPurpose.productAnalytics);
        final redactorEmitter = TelemetryEmitter(
          allowlist: EventAllowlist(
            version: 99,
            eventNames: const {'session_completed'},
            attributeNamesByEvent: const {
              'session_completed': {'landmarkSnapshot'},
            },
          ),
          attributePolicy: _approvedPolicy,
          consentGate: consentGate,
          sink: sink,
        );
        final result = redactorEmitter.emit(
          TelemetryEvent(
            name: 'session_completed',
            attributes: {'landmarkSnapshot': const TelemetryString('ok')},
          ),
        );
        expect(result.rejected, isTrue);
        expect(result.reason, RejectReason.forbiddenKey);
        expect(sink.sent, isEmpty);
      },
    );

    test(
      'fail-closed: a free-text-shaped string value never reaches the sink',
      () {
        consentGate.grant(ConsentPurpose.productAnalytics);
        final result = emitter.emit(
          TelemetryEvent(
            name: 'session_completed',
            attributes: {
              'app_version': const TelemetryString(
                'felt great during this session',
              ),
            },
          ),
        );
        expect(result.rejected, isTrue);
        expect(result.reason, RejectReason.unsafeValueShape);
        expect(sink.sent, isEmpty);
      },
    );

    test('fail-closed: an invalid duration bucket never reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final result = emitter.emit(
        const TelemetryEvent(
          name: 'session_completed',
          attributes: {
            'duration_bucket': TelemetryDurationBucket(
              '/private/token-bearing-path',
            ),
          },
        ),
      );
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.unsafeValueShape);
      expect(sink.sent, isEmpty);
    });

    test('revoking consent after a grant closes the gate again', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      consentGate.revoke(ConsentPurpose.productAnalytics);
      final result = emitter.emit(
        const TelemetryEvent(name: 'session_completed', attributes: {}),
      );
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.noConsent);
    });

    test('content validation rejects a safe-shaped but non-contract field', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final result = emitter.emit(
        const TelemetryEvent(
          name: 'content_validation_result',
          attributes: {'debugValue': TelemetryString('safe_token')},
        ),
      );
      expect(result.rejected, isTrue);
      expect(result.reason, RejectReason.attributeNotAllowlisted);
      expect(sink.sent, isEmpty);
    });

    test('content validation exact privacy-safe payload reaches the sink', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final event = TelemetryEvent(
        name: 'content_validation_result',
        attributes: _contentValidationAttributes(
          result: 'blocked',
          extra: const {
            'errorCode': TelemetryString('hashMismatch'),
            'contentId': TelemetryString('lesson-one'),
            'expectedHashPrefix': TelemetryString('0123456789ab'),
            'actualHashPrefix': TelemetryString('abcdef012345'),
          },
        ),
      );
      final result = emitter.emit(event);
      expect(result.rejected, isFalse);
      expect(sink.sent.single.name, event.name);
      expect(
        _plainAttributes(sink.sent.single.attributes),
        _plainAttributes(event.attributes),
      );
    });

    test('accepted payload is snapshotted before the caller can mutate it', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final attributes = <String, TelemetryValue>{
        ..._contentValidationAttributes(),
      };
      final result = emitter.emit(
        TelemetryEvent(
          name: 'content_validation_result',
          attributes: attributes,
        ),
      );
      attributes['contentId'] = const TelemetryString('secret_token_value');

      expect(result.rejected, isFalse);
      expect(_plainAttributes(sink.sent.single.attributes), {
        'appVersion': '1.2.0',
        'buildNumber': 42,
        'schemaVersion': 1,
        'contentVersion': '1.0.0',
        'result': 'ready',
      });
      expect(
        () => sink.sent.single.attributes['contentId'] = const TelemetryString(
          'later_mutation',
        ),
        throwsUnsupportedError,
      );
    });

    test('accepted value wrappers are copied at the privacy boundary', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final value = _MutableTelemetryString('ready');
      final result = emitter.emit(
        TelemetryEvent(
          name: 'content_validation_result',
          attributes: {..._contentValidationAttributes(), 'result': value},
        ),
      );
      value.current = '/private/token-bearing-path';

      expect(result.rejected, isFalse);
      expect(
        (sink.sent.single.attributes['result']! as TelemetryString).value,
        'ready',
      );
    });

    test('content validation requires its complete typed base envelope', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final missing = _contentValidationAttributes()..remove('appVersion');
      final wrongType = _contentValidationAttributes()
        ..['schemaVersion'] = const TelemetryString('1');
      final negativeBuild = _contentValidationAttributes()
        ..['buildNumber'] = const TelemetryInt(-1);

      for (final attributes in [missing, wrongType, negativeBuild]) {
        final result = emitter.emit(
          TelemetryEvent(
            name: 'content_validation_result',
            attributes: attributes,
          ),
        );
        expect(result.reason, RejectReason.invalidEventShape);
      }
      expect(sink.sent, isEmpty);
    });

    test('content validation closes value domains and error relationships', () {
      consentGate.grant(ConsentPurpose.productAnalytics);
      final invalidVersion = _contentValidationAttributes()
        ..['appVersion'] = const TelemetryString('AKIA1234567890ABCDEF');
      final invalidResult = _contentValidationAttributes(result: 'anything');
      final readyWithError = _contentValidationAttributes(
        extra: const {'errorCode': TelemetryString('timeout')},
      );
      final degradedWithoutFallbackId = _contentValidationAttributes(
        result: 'degraded',
        extra: const {'errorCode': TelemetryString('capability')},
      );
      final hashWithoutPrefixes = _contentValidationAttributes(
        result: 'blocked',
        extra: const {'errorCode': TelemetryString('hashMismatch')},
      );

      for (final attributes in [
        invalidVersion,
        invalidResult,
        readyWithError,
        degradedWithoutFallbackId,
        hashWithoutPrefixes,
      ]) {
        final result = emitter.emit(
          TelemetryEvent(
            name: 'content_validation_result',
            attributes: attributes,
          ),
        );
        expect(result.rejected, isTrue);
      }
      expect(sink.sent, isEmpty);
    });
  });
}
