import 'consent_gate.dart';
import 'event_allowlist.dart';
import 'redactor.dart';
import 'telemetry_attribute_policy.dart';
import 'telemetry_event.dart';
import 'telemetry_value.dart';

enum RejectReason {
  notAllowlisted,
  noConsent,
  attributeNotAllowlisted,
  forbiddenKey,
  unsafeValueShape,
  invalidEventShape,
}

class EmitResult {
  const EmitResult.accepted() : rejected = false, reason = null;

  const EmitResult.rejected(RejectReason this.reason) : rejected = true;

  final bool rejected;
  final RejectReason? reason;
}

abstract class TelemetrySink {
  void send(TelemetryEvent event);
}

/// The single choke point every product-analytics event must pass through.
/// Fail-closed at every gate, checked in order: event allowlist, consent,
/// per-event attribute allowlist, forbidden-content keys, closed event schemas,
/// and an independent exact field/value policy (deny-all by default).
/// Accepted attributes and values are snapshotted before
/// [sink] receives them.
class TelemetryEmitter {
  TelemetryEmitter({
    required this.allowlist,
    TelemetryAttributePolicy attributePolicy =
        const TelemetryAttributePolicy.denyAll(),
    required this.consentGate,
    required this.sink,
  }) : attributePolicy = TelemetryAttributePolicy.snapshot(attributePolicy),
       _redactor = Redactor();

  final EventAllowlist allowlist;
  final TelemetryAttributePolicy attributePolicy;
  final ConsentGate consentGate;
  final TelemetrySink sink;
  final Redactor _redactor;

  EmitResult emit(TelemetryEvent event) {
    final eventName = event.name;
    final attributes = event.attributes;
    if (!allowlist.allows(eventName)) {
      return const EmitResult.rejected(RejectReason.notAllowlisted);
    }
    if (!consentGate.hasConsent(ConsentPurpose.productAnalytics)) {
      return const EmitResult.rejected(RejectReason.noConsent);
    }
    if (attributes.length > 16) {
      return const EmitResult.rejected(RejectReason.unsafeValueShape);
    }
    final safeAttributes = <String, TelemetryValue>{};
    for (final entry in attributes.entries) {
      if (!_safeKeyPattern.hasMatch(entry.key)) {
        return const EmitResult.rejected(RejectReason.unsafeValueShape);
      }
      if (!allowlist.allowsAttribute(eventName, entry.key)) {
        return const EmitResult.rejected(RejectReason.attributeNotAllowlisted);
      }
      if (!_redactor.allowsKey(entry.key)) {
        return const EmitResult.rejected(RejectReason.forbiddenKey);
      }
      final value = _snapshotValue(entry.value);
      if (value is TelemetryString &&
          !_redactor.allowsStringValue(value.value)) {
        return const EmitResult.rejected(RejectReason.unsafeValueShape);
      }
      if (value is TelemetryDurationBucket &&
          !_redactor.allowsDurationBucket(value.bucketLabel)) {
        return const EmitResult.rejected(RejectReason.unsafeValueShape);
      }
      safeAttributes[entry.key] = value;
    }
    if (!_validEventShape(eventName, safeAttributes)) {
      return const EmitResult.rejected(RejectReason.invalidEventShape);
    }
    final eventPolicy = attributePolicy.events[eventName];
    if (eventPolicy == null) {
      return const EmitResult.rejected(RejectReason.unsafeValueShape);
    }
    for (final entry in safeAttributes.entries) {
      final policy = eventPolicy.fields[entry.key];
      if (policy == null || !_allowsPolicyValue(entry.value, policy)) {
        return const EmitResult.rejected(RejectReason.unsafeValueShape);
      }
    }
    // Caller-owned getters may revoke consent while values are snapshotted.
    // No external value access remains between this check and dispatch.
    if (!consentGate.hasConsent(ConsentPurpose.productAnalytics)) {
      return const EmitResult.rejected(RejectReason.noConsent);
    }
    sink.send(
      TelemetryEvent(
        name: eventName,
        attributes: Map<String, TelemetryValue>.unmodifiable(safeAttributes),
      ),
    );
    return const EmitResult.accepted();
  }
}

TelemetryValue _snapshotValue(TelemetryValue value) => switch (value) {
  TelemetryString() => TelemetryString(value.value),
  TelemetryInt() => TelemetryInt(value.value),
  TelemetryBool() => TelemetryBool(value.value),
  TelemetryDurationBucket() => TelemetryDurationBucket(value.bucketLabel),
};

const _contentValidationEvent = 'content_validation_result';
const _sessionCompletedEvent = 'session_completed';
const _sessionCompletedAttributes = {
  'app_version',
  'is_first_session',
  'duration_bucket',
};
const _contentValidationRequiredFields = {
  'appVersion',
  'buildNumber',
  'schemaVersion',
  'contentVersion',
  'result',
};
const _contentValidationAllowedFields = {
  ..._contentValidationRequiredFields,
  'errorCode',
  'contentId',
  'expectedHashPrefix',
  'actualHashPrefix',
};
const _contentErrorCodes = {
  'parse',
  'duplicateJsonKey',
  'resourceLimit',
  'schema',
  'appIdentity',
  'compatibility',
  'duplicateId',
  'orphanReference',
  'unsafePath',
  'missingAsset',
  'sizeMismatch',
  'hashMismatch',
  'catalogDigestMismatch',
  'timeout',
  'locale',
  'capability',
  'io',
};
final _semanticVersionPattern = RegExp(r'^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}$');
final _contentIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$');
final _hashPrefixPattern = RegExp(r'^[a-f0-9]{12}$');
final _closedDurationBucketPattern = RegExp(r'^([0-9]{1,6})-([0-9]{1,6})s$');
final _openDurationBucketPattern = RegExp(r'^[0-9]{1,6}s\+$');

bool _validEventShape(
  String eventName,
  Map<String, TelemetryValue> attributes,
) {
  if (eventName == _sessionCompletedEvent) {
    return _validSessionCompletedShape(attributes);
  }
  if (eventName != _contentValidationEvent) return attributes.isEmpty;
  if (attributes.keys.any(
    (key) => !_contentValidationAllowedFields.contains(key),
  )) {
    return false;
  }
  if (!attributes.keys.toSet().containsAll(_contentValidationRequiredFields)) {
    return false;
  }
  if (!_isMatchingString(attributes['appVersion'], _semanticVersionPattern) ||
      !_isMatchingString(
        attributes['contentVersion'],
        _semanticVersionPattern,
      )) {
    return false;
  }
  final buildNumber = attributes['buildNumber'];
  final schemaVersion = attributes['schemaVersion'];
  if (buildNumber is! TelemetryInt ||
      buildNumber.value < 0 ||
      buildNumber.value > 0x7fffffff ||
      schemaVersion is! TelemetryInt ||
      schemaVersion.value < 1 ||
      schemaVersion.value > 999) {
    return false;
  }
  final resultValue = attributes['result'];
  if (resultValue is! TelemetryString) return false;
  final result = resultValue.value;
  if (result != 'ready' && result != 'degraded' && result != 'blocked') {
    return false;
  }

  final errorValue = attributes['errorCode'];
  final contentIdValue = attributes['contentId'];
  final expectedHashValue = attributes['expectedHashPrefix'];
  final actualHashValue = attributes['actualHashPrefix'];
  if (contentIdValue != null &&
      !_isMatchingString(contentIdValue, _contentIdPattern)) {
    return false;
  }

  if (result == 'ready') {
    return errorValue == null &&
        contentIdValue == null &&
        expectedHashValue == null &&
        actualHashValue == null;
  }
  if (errorValue is! TelemetryString ||
      !_contentErrorCodes.contains(errorValue.value)) {
    return false;
  }
  if (result == 'degraded' &&
      (errorValue.value != 'capability' || contentIdValue == null)) {
    return false;
  }

  final isDigestFailure =
      errorValue.value == 'hashMismatch' ||
      errorValue.value == 'catalogDigestMismatch';
  if (isDigestFailure) {
    return _isMatchingString(expectedHashValue, _hashPrefixPattern) &&
        _isMatchingString(actualHashValue, _hashPrefixPattern);
  }
  return expectedHashValue == null && actualHashValue == null;
}

bool _validSessionCompletedShape(Map<String, TelemetryValue> attributes) {
  if (attributes.keys.any(
    (key) => !_sessionCompletedAttributes.contains(key),
  )) {
    return false;
  }

  final appVersion = attributes['app_version'];
  if (appVersion != null &&
      !_isMatchingString(appVersion, _semanticVersionPattern)) {
    return false;
  }

  final isFirstSession = attributes['is_first_session'];
  if (isFirstSession != null && isFirstSession is! TelemetryBool) {
    return false;
  }

  final durationBucket = attributes['duration_bucket'];
  return durationBucket == null || _isSemanticDurationBucket(durationBucket);
}

bool _isSemanticDurationBucket(TelemetryValue value) {
  if (value is! TelemetryDurationBucket) return false;
  if (_openDurationBucketPattern.hasMatch(value.bucketLabel)) return true;

  final range = _closedDurationBucketPattern.firstMatch(value.bucketLabel);
  if (range == null) return false;
  return int.parse(range.group(1)!) < int.parse(range.group(2)!);
}

bool _isMatchingString(TelemetryValue? value, RegExp pattern) =>
    value is TelemetryString && pattern.hasMatch(value.value);

final _safeKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,39}$');
final _safePolicyTokenPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$');

bool _allowsPolicyValue(TelemetryValue value, TelemetryFieldPolicy policy) =>
    switch (value) {
      TelemetryString(:final value) =>
        policy is TelemetryTokenFieldPolicy &&
            _safePolicyTokenPattern.hasMatch(value) &&
            policy.allowedValues.contains(value),
      TelemetryInt(:final value) =>
        policy is TelemetryIntFieldPolicy &&
            value >= -1000000 &&
            value <= 1000000 &&
            value >= policy.min &&
            value <= policy.max,
      TelemetryBool() => policy is TelemetryBoolFieldPolicy,
      TelemetryDurationBucket(:final bucketLabel) =>
        policy is TelemetryDurationFieldPolicy &&
            TelemetryDurationBucket.allowedLabels.contains(bucketLabel),
    };
