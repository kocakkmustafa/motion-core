sealed class TelemetryFieldPolicy {
  const TelemetryFieldPolicy();
}

final class TelemetryTokenFieldPolicy extends TelemetryFieldPolicy {
  const TelemetryTokenFieldPolicy({required this.allowedValues});

  final Set<String> allowedValues;
}

final class TelemetryIntFieldPolicy extends TelemetryFieldPolicy {
  const TelemetryIntFieldPolicy({required this.min, required this.max});

  final int min;
  final int max;
}

final class TelemetryBoolFieldPolicy extends TelemetryFieldPolicy {
  const TelemetryBoolFieldPolicy();
}

final class TelemetryDurationFieldPolicy extends TelemetryFieldPolicy {
  const TelemetryDurationFieldPolicy();
}

final class TelemetryEventAttributePolicy {
  const TelemetryEventAttributePolicy({required this.fields});

  final Map<String, TelemetryFieldPolicy> fields;
}

final class TelemetryAttributePolicy {
  /// Exact event/field/value policy configured independently of emitted data.
  const TelemetryAttributePolicy({required this.events});
  const TelemetryAttributePolicy.denyAll() : events = const {};

  /// Copies policy structure independently of future caller mutations.
  factory TelemetryAttributePolicy.snapshot(TelemetryAttributePolicy policy) =>
      TelemetryAttributePolicy(
        events: Map.unmodifiable({
          for (final event in policy.events.entries)
            event.key: TelemetryEventAttributePolicy(
              fields: Map.unmodifiable({
                for (final field in event.value.fields.entries)
                  field.key: switch (field.value) {
                    TelemetryTokenFieldPolicy(:final allowedValues) =>
                      TelemetryTokenFieldPolicy(
                        allowedValues: Set.unmodifiable(allowedValues),
                      ),
                    TelemetryIntFieldPolicy(:final min, :final max) =>
                      TelemetryIntFieldPolicy(min: min, max: max),
                    TelemetryBoolFieldPolicy() =>
                      const TelemetryBoolFieldPolicy(),
                    TelemetryDurationFieldPolicy() =>
                      const TelemetryDurationFieldPolicy(),
                  },
              }),
            ),
        }),
      );

  final Map<String, TelemetryEventAttributePolicy> events;
}
