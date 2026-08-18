/// A versioned, closed set of event names product analytics may ever emit.
/// Fail-closed by construction: anything not explicitly listed is refused
/// by [TelemetryEmitter], there is no wildcard/pass-through mode.
class EventAllowlist {
  const EventAllowlist({required this.version, required this.eventNames});

  final int version;
  final Set<String> eventNames;

  bool allows(String eventName) => eventNames.contains(eventName);

  /// The exact family-wide v1 set (00-AILE-MIMARISI.md §8.4). Extending
  /// this list is a versioned, deliberate change — not an app-by-app
  /// decision.
  static const v1 = EventAllowlist(
    version: 1,
    eventNames: {
      'onboarding_complete',
      'device_check_result',
      'session_started',
      'session_completed',
      'value_event',
      'paywall_viewed',
      'purchase_state_changed',
      'restore_state_changed',
    },
  );
}
