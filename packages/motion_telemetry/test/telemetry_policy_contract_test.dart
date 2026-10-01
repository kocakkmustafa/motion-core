import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

class _RecordingSink implements TelemetrySink {
  final sent = <TelemetryEvent>[];
  @override
  void send(TelemetryEvent event) => sent.add(event);
}

class _ChangingEvent extends TelemetryEvent {
  _ChangingEvent() : super(name: 'session_completed', attributes: const {});
  int reads = 0;
  @override
  String get name => reads++ < 3 ? 'session_completed' : 'unapproved-event';
}

const _sessionPolicy = TelemetryAttributePolicy(
  events: {
    'session_completed': TelemetryEventAttributePolicy(
      fields: {
        'app_version': TelemetryTokenFieldPolicy(allowedValues: {'1.4.0'}),
        'is_first_session': TelemetryBoolFieldPolicy(),
        'duration_bucket': TelemetryDurationFieldPolicy(),
      },
    ),
  },
);

TelemetryEmitter _emitter(
  _RecordingSink sink, {
  TelemetryAttributePolicy policy = _sessionPolicy,
  EventAllowlist allowlist = EventAllowlist.v2,
}) => TelemetryEmitter(
  allowlist: allowlist,
  attributePolicy: policy,
  consentGate: InMemoryConsentGate()..grant(ConsentPurpose.productAnalytics),
  sink: sink,
);

Map<String, TelemetryValue> _content({int build = 42}) => {
  'appVersion': const TelemetryString('1.2.0'),
  'buildNumber': TelemetryInt(build),
  'schemaVersion': const TelemetryInt(1),
  'contentVersion': const TelemetryString('1.0.0'),
  'result': const TelemetryString('ready'),
};
const _contentPolicy = TelemetryAttributePolicy(
  events: {
    'content_validation_result': TelemetryEventAttributePolicy(
      fields: {
        'appVersion': TelemetryTokenFieldPolicy(allowedValues: {'1.2.0'}),
        'buildNumber': TelemetryIntFieldPolicy(min: 0, max: 42),
        'schemaVersion': TelemetryIntFieldPolicy(min: 1, max: 1),
        'contentVersion': TelemetryTokenFieldPolicy(allowedValues: {'1.0.0'}),
        'result': TelemetryTokenFieldPolicy(allowedValues: {'ready'}),
      },
    ),
  },
);

void main() {
  test(
    'event identity is snapshotted with its attributes before validation',
    () {
      final sink = _RecordingSink();
      final event = _ChangingEvent();
      expect(_emitter(sink).emit(event).rejected, isFalse);
      expect(sink.sent.single.name, 'session_completed');
      expect(event.reads, 1);
    },
  );

  test('default policy denies even an allowlisted empty marker', () {
    final sink = _RecordingSink();
    final emitter = TelemetryEmitter(
      allowlist: EventAllowlist.v2,
      consentGate: InMemoryConsentGate()
        ..grant(ConsentPurpose.productAnalytics),
      sink: sink,
    );
    expect(
      emitter
          .emit(const TelemetryEvent(name: 'session_completed', attributes: {}))
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(sink.sent, isEmpty);
  });

  test('explicit policy preserves main semantic types and snapshots', () {
    final sink = _RecordingSink();
    final attributes = <String, TelemetryValue>{
      'app_version': const TelemetryString('1.4.0'),
      'is_first_session': const TelemetryBool(true),
      'duration_bucket': const TelemetryDurationBucket('15-60s'),
    };
    expect(
      _emitter(sink)
          .emit(
            TelemetryEvent(name: 'session_completed', attributes: attributes),
          )
          .rejected,
      isFalse,
    );
    attributes['app_version'] = const TelemetryString('9.9.9');
    expect(
      (sink.sent.single.attributes['app_version']! as TelemetryString).value,
      '1.4.0',
    );
  });

  test('a semantic version not in exact policy never reaches the sink', () {
    final sink = _RecordingSink();
    expect(
      _emitter(sink)
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'app_version': TelemetryString('9.9.9')},
            ),
          )
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(sink.sent, isEmpty);
  });

  test('explicit policy must include every emitted field', () {
    final sink = _RecordingSink();
    const policy = TelemetryAttributePolicy(
      events: {'session_completed': TelemetryEventAttributePolicy(fields: {})},
    );
    expect(
      _emitter(sink, policy: policy)
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'is_first_session': TelemetryBool(true)},
            ),
          )
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(sink.sent, isEmpty);
  });

  test('exact policy cannot widen main session or content schemas', () {
    final sink = _RecordingSink();
    const policy = TelemetryAttributePolicy(
      events: {
        'session_completed': TelemetryEventAttributePolicy(
          fields: {'opaque_metric': TelemetryIntFieldPolicy(min: 0, max: 3)},
        ),
      },
    );
    final allowlist = EventAllowlist(
      version: 99,
      eventNames: const {'session_completed'},
      attributeNamesByEvent: const {
        'session_completed': {'opaque_metric'},
      },
    );
    expect(
      _emitter(sink, policy: policy, allowlist: allowlist)
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'opaque_metric': TelemetryInt(2)},
            ),
          )
          .reason,
      RejectReason.invalidEventShape,
    );
    expect(sink.sent, isEmpty);
  });

  for (final label in ['0-5s', '5-15s', '15-60s', '60s+']) {
    test('closed duration label passes: $label', () {
      final sink = _RecordingSink();
      expect(
        _emitter(sink)
            .emit(
              TelemetryEvent(
                name: 'session_completed',
                attributes: {'duration_bucket': TelemetryDurationBucket(label)},
              ),
            )
            .rejected,
        isFalse,
      );
      expect(sink.sent, hasLength(1));
    });
  }
  for (final label in ['60-120s', '120s+', 'felt_long', '5s', '0-5sec']) {
    test('duration shape alone never authorizes a label: $label', () {
      final sink = _RecordingSink();
      expect(
        _emitter(sink)
            .emit(
              TelemetryEvent(
                name: 'session_completed',
                attributes: {'duration_bucket': TelemetryDurationBucket(label)},
              ),
            )
            .rejected,
        isTrue,
      );
      expect(sink.sent, isEmpty);
    });
  }

  test('content integers satisfy field-specific bounds and closed shapes', () {
    final sink = _RecordingSink();
    final emitter = _emitter(sink, policy: _contentPolicy);
    expect(
      emitter
          .emit(
            TelemetryEvent(
              name: 'content_validation_result',
              attributes: _content(),
            ),
          )
          .rejected,
      isFalse,
    );
    expect(
      emitter
          .emit(
            TelemetryEvent(
              name: 'content_validation_result',
              attributes: _content(build: 43),
            ),
          )
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(sink.sent, hasLength(1));
  });

  test('wrong policy value shape cannot authorize a semantic value', () {
    final sink = _RecordingSink();
    const policy = TelemetryAttributePolicy(
      events: {
        'session_completed': TelemetryEventAttributePolicy(
          fields: {'is_first_session': TelemetryIntFieldPolicy(min: 0, max: 1)},
        ),
      },
    );
    expect(
      _emitter(sink, policy: policy)
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'is_first_session': TelemetryBool(true)},
            ),
          )
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(sink.sent, isEmpty);
  });

  test('seventeen attributes and malformed keys fail before delivery', () {
    final sink = _RecordingSink();
    for (final attributes in [
      {for (var i = 0; i < 17; i++) 'flag_$i': const TelemetryBool(true)},
      for (final key in ['bad key', 'bad\nkey', '1leading', 'a' * 41])
        {key: const TelemetryBool(true)},
    ]) {
      expect(
        _emitter(sink)
            .emit(
              TelemetryEvent(name: 'session_completed', attributes: attributes),
            )
            .reason,
        RejectReason.unsafeValueShape,
      );
    }
    expect(sink.sent, isEmpty);
  });

  test('policy does not authorize forbidden content keys', () {
    final sink = _RecordingSink();
    const policy = TelemetryAttributePolicy(
      events: {
        'session_completed': TelemetryEventAttributePolicy(
          fields: {'audio_note': TelemetryBoolFieldPolicy()},
        ),
      },
    );
    final allowlist = EventAllowlist(
      version: 99,
      eventNames: const {'session_completed'},
      attributeNamesByEvent: const {
        'session_completed': {'audio_note'},
      },
    );
    expect(
      _emitter(sink, policy: policy, allowlist: allowlist)
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'audio_note': TelemetryBool(true)},
            ),
          )
          .reason,
      RejectReason.forbiddenKey,
    );
    expect(sink.sent, isEmpty);
  });

  test('emitter snapshots policy sets and maps at construction', () {
    final versions = {'1.4.0'};
    final fields = <String, TelemetryFieldPolicy>{
      'app_version': TelemetryTokenFieldPolicy(allowedValues: versions),
    };
    final events = {
      'session_completed': TelemetryEventAttributePolicy(fields: fields),
    };
    final sink = _RecordingSink();
    final emitter = _emitter(
      sink,
      policy: TelemetryAttributePolicy(events: events),
    );
    versions.add('9.9.9');
    fields.clear();
    events.clear();
    expect(
      emitter
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'app_version': TelemetryString('9.9.9')},
            ),
          )
          .reason,
      RejectReason.unsafeValueShape,
    );
    expect(
      emitter
          .emit(
            const TelemetryEvent(
              name: 'session_completed',
              attributes: {'app_version': TelemetryString('1.4.0')},
            ),
          )
          .rejected,
      isFalse,
    );
    expect(sink.sent, hasLength(1));
  });
}
