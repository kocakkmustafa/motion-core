/// One immutable provenance record. [type] is an opaque, caller-namespaced
/// string (e.g. `"<app>.assessment.completed"`) and [payload] is an opaque
/// map — this package stores and orders entries, it never interprets their
/// content.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    required this.schemaVersion,
  });

  final String id;
  final String type;
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final int schemaVersion;
}
