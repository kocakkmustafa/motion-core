import 'journal_entry.dart';

sealed class JournalExportCandidateValue {
  const JournalExportCandidateValue();
}

/// A shaped value proposed by a projector. Construction does not authorize
/// export; [JournalExportPolicy] must independently allow the exact value.
class JournalExportTokenCandidate extends JournalExportCandidateValue {
  const JournalExportTokenCandidate(this.value);

  final String value;
}

class JournalExportIntCandidate extends JournalExportCandidateValue {
  const JournalExportIntCandidate(this.value);

  final int value;
}

class JournalExportBoolCandidate extends JournalExportCandidateValue {
  const JournalExportBoolCandidate(this.value);

  final bool value;
}

sealed class JournalExportFieldPolicy {
  const JournalExportFieldPolicy();
}

class JournalTokenFieldPolicy extends JournalExportFieldPolicy {
  const JournalTokenFieldPolicy({required this.allowedValues});

  final Set<String> allowedValues;
}

class JournalIntFieldPolicy extends JournalExportFieldPolicy {
  const JournalIntFieldPolicy({required this.min, required this.max});

  final int min;
  final int max;
}

class JournalBoolFieldPolicy extends JournalExportFieldPolicy {
  const JournalBoolFieldPolicy();
}

class JournalEntryExportPolicy {
  const JournalEntryExportPolicy({required this.fields});

  final Map<String, JournalExportFieldPolicy> fields;
}

class JournalExportPolicy {
  /// Exact entry-type and per-field export membership. Callers must define
  /// this independently rather than deriving it from journal payload data.
  const JournalExportPolicy({required this.entriesByType});
  const JournalExportPolicy.denyAll() : entriesByType = const {};

  factory JournalExportPolicy.snapshot(JournalExportPolicy policy) =>
      JournalExportPolicy(
        entriesByType: Map.unmodifiable({
          for (final entry in policy.entriesByType.entries)
            entry.key: JournalEntryExportPolicy(
              fields: Map.unmodifiable({
                for (final field in entry.value.fields.entries)
                  field.key: switch (field.value) {
                    JournalTokenFieldPolicy(:final allowedValues) =>
                      JournalTokenFieldPolicy(
                        allowedValues: Set.unmodifiable(allowedValues),
                      ),
                    JournalIntFieldPolicy(:final min, :final max) =>
                      JournalIntFieldPolicy(min: min, max: max),
                    JournalBoolFieldPolicy() => const JournalBoolFieldPolicy(),
                  },
              }),
            ),
        }),
      );

  final Map<String, JournalEntryExportPolicy> entriesByType;
}

abstract interface class JournalExportProjector {
  Map<String, JournalExportCandidateValue> project(JournalEntry entry);
}

class MetadataOnlyJournalProjector implements JournalExportProjector {
  const MetadataOnlyJournalProjector();

  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) =>
      const {};
}

class JournalExportLimits {
  static const hardMaxEntries = 10000;
  static const hardMaxFieldsPerEntry = 16;
  static const hardMaxEncodedBytes = 2 * 1024 * 1024;

  JournalExportLimits({
    this.maxEntries = hardMaxEntries,
    this.maxFieldsPerEntry = hardMaxFieldsPerEntry,
    this.maxEncodedBytes = hardMaxEncodedBytes,
  }) {
    _requireBounded(
      name: 'maxEntries',
      value: maxEntries,
      hardMaximum: hardMaxEntries,
    );
    _requireBounded(
      name: 'maxFieldsPerEntry',
      value: maxFieldsPerEntry,
      hardMaximum: hardMaxFieldsPerEntry,
    );
    _requireBounded(
      name: 'maxEncodedBytes',
      value: maxEncodedBytes,
      hardMaximum: hardMaxEncodedBytes,
    );
  }

  factory JournalExportLimits.snapshot(JournalExportLimits limits) =>
      JournalExportLimits(
        maxEntries: limits.maxEntries,
        maxFieldsPerEntry: limits.maxFieldsPerEntry,
        maxEncodedBytes: limits.maxEncodedBytes,
      );

  final int maxEntries;
  final int maxFieldsPerEntry;
  final int maxEncodedBytes;

  static void _requireBounded({
    required String name,
    required int value,
    required int hardMaximum,
  }) {
    if (value < 0 || value > hardMaximum) {
      throw ArgumentError.value(
        value,
        name,
        'must be between 0 and $hardMaximum',
      );
    }
  }
}

enum JournalExportRejectReason {
  unboundedJournal,
  unsafeIdentifier,
  disallowedEntryType,
  disallowedProjectedKey,
  disallowedTokenValue,
  valueShapeMismatch,
  tooManyEntries,
  tooManyFields,
  unsafeFieldKey,
  unsafeValue,
  encodedSizeExceeded,
  projectorFailure,
}

class JournalExportException implements Exception {
  const JournalExportException(this.reason);

  final JournalExportRejectReason reason;

  @override
  String toString() => 'JournalExportException(${reason.name})';
}
