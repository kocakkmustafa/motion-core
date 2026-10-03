import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_telemetry/motion_telemetry.dart';

class _WideningAllowlist implements EventAllowlist {
  @override
  int get version => 2;
  @override
  Set<String> get eventNames => {'content_validation_result'};
  @override
  bool allows(String eventName) => eventNames.contains(eventName);
  @override
  bool allowsAttribute(String eventName, String attributeName) => true;
  @override
  Set<String>? attributeNamesFor(String eventName) => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements TelemetrySink {
  final sent = <TelemetryEvent>[];
  @override
  void send(TelemetryEvent event) => sent.add(event);
}

class _RevokingTelemetryBool extends TelemetryBool {
  _RevokingTelemetryBool(this.gate) : super(true);
  final InMemoryConsentGate gate;
  @override
  bool get value {
    gate.revoke(ConsentPurpose.productAnalytics);
    return true;
  }
}

class _OversizedPolicyMap extends MapBase<String, DiagnosticFieldShape> {
  @override
  int get length => 1000000;
  @override
  Iterable<String> get keys => throw StateError('sensitive-policy-detail');
  @override
  DiagnosticFieldShape? operator [](Object? key) => null;
  @override
  void operator []=(String key, DiagnosticFieldShape value) =>
      throw UnsupportedError('read-only');
  @override
  void clear() => throw UnsupportedError('read-only');
  @override
  DiagnosticFieldShape? remove(Object? key) =>
      throw UnsupportedError('read-only');
}

class _FailingPolicyMap extends _OversizedPolicyMap {
  @override
  int get length => 4;
  @override
  DiagnosticFieldShape? operator [](Object? key) =>
      throw StateError('sensitive-policy-detail');
}

class _MutableDiagnosticExporter extends DiagnosticExporter {
  _MutableDiagnosticExporter() : super(maxEncodedBytes: 0);
  int currentBytes = 0;
  @override
  int get maxEncodedBytes => currentBytes;
}

class _WideningCodeSet extends SetBase<String> {
  @override
  int get length => 1;
  @override
  Iterator<String> get iterator => const {'network_timeout'}.iterator;
  @override
  bool contains(Object? element) => true;
  @override
  bool add(String value) => throw UnsupportedError('read-only');
  @override
  String? lookup(Object? element) => null;
  @override
  bool remove(Object? value) => throw UnsupportedError('read-only');
  @override
  Set<String> toSet() => {'network_timeout'};
}

class _OversizedCodeSet extends _WideningCodeSet {
  @override
  int get length => 1000000;
  @override
  Iterator<String> get iterator => throw StateError('sensitive-policy-detail');
}

class _UndercountedCodeSet extends _WideningCodeSet {
  @override
  Iterator<String> get iterator => Iterable<String>.generate(
    1000000,
    (index) => index == 0 ? 'network_timeout' : 'code_$index',
  ).iterator;
}

const _request = DiagnosticExportRequest(
  userPreviewed: true,
  userConfirmed: true,
);
const _fields = {
  'buildMode': DiagnosticFieldShape.buildMode,
  'code': DiagnosticFieldShape.code,
  'platform': DiagnosticFieldShape.platform,
  'version': DiagnosticFieldShape.version,
};
const _policy = DiagnosticExportPolicy(
  allowedCodes: {'network_timeout'},
  fields: _fields,
);
SafeDiagnosticBundle _bundle() => SafeDiagnosticBundle(
  platform: DiagnosticPlatform.ios,
  buildMode: DiagnosticBuildMode.release,
  version: DiagnosticVersion(major: 1, minor: 0, patch: 0, build: 2),
  code: const DiagnosticCodeCandidate('network_timeout'),
);

Matcher _diagnosticReject(DiagnosticExportRejectReason reason) => throwsA(
  isA<DiagnosticExportException>()
      .having((error) => error.reason, 'reason', reason)
      .having(
        (error) => error.toString(),
        'message',
        isNot(contains('sensitive-policy-detail')),
      ),
);

void main() {
  test('revocation during value snapshot prevents the event from leaving', () {
    final sink = _Sink();
    final gate = InMemoryConsentGate()..grant(ConsentPurpose.productAnalytics);
    final emitter = TelemetryEmitter(
      allowlist: EventAllowlist.v2,
      consentGate: gate,
      attributePolicy: const TelemetryAttributePolicy(
        events: {
          'session_completed': TelemetryEventAttributePolicy(
            fields: {'is_first_session': TelemetryBoolFieldPolicy()},
          ),
        },
      ),
      sink: sink,
    );
    final result = emitter.emit(
      TelemetryEvent(
        name: 'session_completed',
        attributes: {'is_first_session': _RevokingTelemetryBool(gate)},
      ),
    );
    expect(result.reason, RejectReason.noConsent);
    expect(sink.sent, isEmpty);
  });

  test('content diagnostics cannot widen their closed field schema', () {
    final sink = _Sink();
    final emitter = TelemetryEmitter(
      allowlist: _WideningAllowlist(),
      consentGate: InMemoryConsentGate()
        ..grant(ConsentPurpose.productAnalytics),
      attributePolicy: const TelemetryAttributePolicy(
        events: {
          'content_validation_result': TelemetryEventAttributePolicy(
            fields: {
              'appVersion': TelemetryTokenFieldPolicy(allowedValues: {'1.0.0'}),
              'buildNumber': TelemetryIntFieldPolicy(min: 0, max: 2),
              'schemaVersion': TelemetryIntFieldPolicy(min: 1, max: 1),
              'contentVersion': TelemetryTokenFieldPolicy(
                allowedValues: {'1.0.0'},
              ),
              'result': TelemetryTokenFieldPolicy(allowedValues: {'ready'}),
              'bodyReading': TelemetryIntFieldPolicy(min: 0, max: 3),
            },
          ),
        },
      ),
      sink: sink,
    );
    final result = emitter.emit(
      const TelemetryEvent(
        name: 'content_validation_result',
        attributes: {
          'appVersion': TelemetryString('1.0.0'),
          'buildNumber': TelemetryInt(2),
          'schemaVersion': TelemetryInt(1),
          'contentVersion': TelemetryString('1.0.0'),
          'result': TelemetryString('ready'),
          'bodyReading': TelemetryInt(2),
        },
      ),
    );
    expect(result.reason, RejectReason.invalidEventShape);
    expect(sink.sent, isEmpty);
  });

  test('diagnostic field limit rejects before copying an oversized map', () {
    expect(
      () => DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(
          allowedCodes: {'network_timeout'},
          fields: _OversizedPolicyMap(),
        ),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });

  test('diagnostic caller-owned field access failures stay sanitized', () {
    expect(
      () => DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(
          allowedCodes: {'network_timeout'},
          fields: _FailingPolicyMap(),
        ),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });

  test('diagnostic byte bound does not depend on an overridable getter', () {
    final exporter = _MutableDiagnosticExporter();
    exporter.currentBytes = DiagnosticExporter.hardMaxEncodedBytes + 1;
    expect(
      () => exporter.export(_request, _bundle(), _policy),
      _diagnosticReject(DiagnosticExportRejectReason.encodedSizeExceeded),
    );
  });

  test('diagnostic membership uses enumerated codes, not custom contains', () {
    final bundle = SafeDiagnosticBundle(
      platform: DiagnosticPlatform.ios,
      buildMode: DiagnosticBuildMode.release,
      version: DiagnosticVersion(major: 1, minor: 0, patch: 0, build: 2),
      code: const DiagnosticCodeCandidate('unapproved_marker'),
    );
    expect(
      () => DiagnosticExporter().export(
        _request,
        bundle,
        DiagnosticExportPolicy(
          allowedCodes: _WideningCodeSet(),
          fields: _fields,
        ),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });

  test('oversized diagnostic code policy rejects before iteration', () {
    expect(
      () => DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(
          allowedCodes: _OversizedCodeSet(),
          fields: _fields,
        ),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });

  test('undercounted diagnostic code policy cannot bypass iteration cap', () {
    expect(
      () => DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(
          allowedCodes: _UndercountedCodeSet(),
          fields: _fields,
        ),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });

  test('diagnostic policy accepts exactly 64 enumerated approved codes', () {
    final codes = <String>{'network_timeout'};
    codes.addAll(Iterable.generate(63, (index) => 'code_$index'));
    expect(
      DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(allowedCodes: codes, fields: _fields),
      ),
      contains('network_timeout'),
    );
  });

  test('diagnostic policy rejects 65 genuine codes even for a member', () {
    final codes = <String>{'network_timeout'};
    codes.addAll(Iterable.generate(64, (index) => 'code_$index'));
    expect(
      () => DiagnosticExporter().export(
        _request,
        _bundle(),
        DiagnosticExportPolicy(allowedCodes: codes, fields: _fields),
      ),
      _diagnosticReject(DiagnosticExportRejectReason.disallowedPolicyValue),
    );
  });
}
