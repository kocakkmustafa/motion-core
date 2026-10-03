import 'journal_entry.dart';
import 'journal_export_policy.dart';

/// Append-only provenance log: entries are never edited or removed once
/// written. Individual delete/redaction lives at a higher layer (see
/// [AtomicEraser] for whole-journal erasure) — this contract intentionally
/// has no `update`/`delete` method for single entries.
abstract class AppendOnlyJournal {
  Future<void> append(JournalEntry entry);
  Future<List<JournalEntry>> readAll();

  /// Entries strictly after the one whose id is [cursor], in append order.
  /// Fail-closed: an unrecognized cursor returns every entry rather than
  /// silently dropping provenance — a duplicate read is recoverable, a
  /// silently skipped one is not.
  Future<List<JournalEntry>> readSince(String cursor);
}

/// A storage-level bounded prefix read. Implementations must apply [limit]
/// before materializing history, preserve append order, and return the entire
/// prefix up to [limit]. Export requests one extra entry to detect overflow.
/// This capability is separate so legacy projection readers remain compatible.
abstract interface class BoundedJournalReader {
  Future<List<JournalEntry>> readForExport({required int limit});
}

class InMemoryJournal implements AppendOnlyJournal, BoundedJournalReader {
  final _entries = <JournalEntry>[];

  @override
  Future<void> append(JournalEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<JournalEntry>> readAll() async => List.unmodifiable(_entries);

  @override
  Future<List<JournalEntry>> readForExport({required int limit}) async {
    RangeError.checkValueInInterval(
      limit,
      0,
      JournalExportLimits.hardMaxEntries + 1,
      'limit',
    );
    return List.unmodifiable(_entries.take(limit));
  }

  @override
  Future<List<JournalEntry>> readSince(String cursor) async {
    final idx = _entries.indexWhere((e) => e.id == cursor);
    if (idx == -1) return List.unmodifiable(_entries);
    return List.unmodifiable(_entries.sublist(idx + 1));
  }
}
