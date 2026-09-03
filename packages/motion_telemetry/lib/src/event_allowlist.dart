/// A versioned, closed set of event names product analytics may ever emit.
/// Fail-closed by construction: anything not explicitly listed is refused
/// by [TelemetryEmitter], there is no wildcard/pass-through mode.
class EventAllowlist {
  factory EventAllowlist({
    required int version,
    required Set<String> eventNames,
    Map<String, Set<String>> attributeNamesByEvent = const {},
  }) {
    final copiedEventNames = Set<String>.unmodifiable(eventNames);
    final copiedAttributes = <String, Set<String>>{
      for (final eventName in copiedEventNames)
        eventName: Set<String>.unmodifiable(
          eventName == _contentValidationEvent
              ? _contentValidationAttributes
              : attributeNamesByEvent[eventName] ?? const <String>{},
        ),
    };
    return EventAllowlist._(
      version: version,
      eventNames: copiedEventNames,
      attributeNamesByEvent: Map.unmodifiable(copiedAttributes),
    );
  }

  const EventAllowlist._({
    required this.version,
    required this.eventNames,
    required Map<String, Set<String>> attributeNamesByEvent,
  }) : _attributeNamesByEvent = attributeNamesByEvent;

  final int version;
  final Set<String> eventNames;
  final Map<String, Set<String>> _attributeNamesByEvent;

  bool allows(String eventName) => eventNames.contains(eventName);

  Set<String>? attributeNamesFor(String eventName) =>
      _attributeNamesByEvent[eventName];

  bool allowsAttribute(String eventName, String attributeName) {
    if (!allows(eventName)) return false;
    final names = attributeNamesFor(eventName);
    return names?.contains(attributeName) ?? false;
  }

  static const _contentValidationEvent = 'content_validation_result';

  static const _contentValidationAttributes = {
    'appVersion',
    'buildNumber',
    'schemaVersion',
    'contentVersion',
    'result',
    'errorCode',
    'contentId',
    'expectedHashPrefix',
    'actualHashPrefix',
  };

  static const _v1EventNames = {
    'onboarding_complete',
    'device_check_result',
    'session_started',
    'session_completed',
    'value_event',
    'paywall_viewed',
    'purchase_state_changed',
    'restore_state_changed',
  };

  /// The original family-wide v1 set (00-AILE-MIMARISI.md §8.4).
  static const v1 = EventAllowlist._(
    version: 1,
    eventNames: _v1EventNames,
    attributeNamesByEvent: {
      'onboarding_complete': {},
      'device_check_result': {},
      'session_started': {},
      'session_completed': {
        'app_version',
        'is_first_session',
        'duration_bucket',
      },
      'value_event': {},
      'paywall_viewed': {},
      'purchase_state_changed': {},
      'restore_state_changed': {},
    },
  );

  /// V2 adds one bounded embedded-content diagnostic event. The old v1
  /// constant remains immutable so pinned consumers cannot gain a new event
  /// merely by updating implementation code.
  static const v2 = EventAllowlist._(
    version: 2,
    eventNames: {..._v1EventNames, 'content_validation_result'},
    attributeNamesByEvent: {
      'onboarding_complete': {},
      'device_check_result': {},
      'session_started': {},
      'session_completed': {
        'app_version',
        'is_first_session',
        'duration_bucket',
      },
      'value_event': {},
      'paywall_viewed': {},
      'purchase_state_changed': {},
      'restore_state_changed': {},
      'content_validation_result': _contentValidationAttributes,
    },
  );

  static const current = v2;
}
