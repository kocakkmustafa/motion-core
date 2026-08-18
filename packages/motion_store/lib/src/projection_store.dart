import 'journal.dart';
import 'journal_entry.dart';

/// A read-optimized projection rebuilt from an [AppendOnlyJournal] (the
/// production backing is Drift/SQLite; this package defines the contract,
/// not the storage engine).
abstract class ProjectionStore {
  bool get isReady;

  /// Rebuilds all projected state from [journal]. Fail-closed: implementers
  /// must only flip to ready *after* a full, successful rebuild — a
  /// projection that half-rebuilt and then failed must keep reporting
  /// itself not-ready rather than serve stale-mixed-with-partial data.
  Future<void> rebuildFromJournal(AppendOnlyJournal journal);
}

class InMemoryProjectionStore implements ProjectionStore {
  bool _ready = false;
  List<JournalEntry> _snapshot = const [];

  @override
  bool get isReady => _ready;

  List<JournalEntry> get snapshot => _snapshot;

  @override
  Future<void> rebuildFromJournal(AppendOnlyJournal journal) async {
    _ready = false;
    final entries = await journal.readAll();
    _snapshot = List.unmodifiable(entries);
    _ready = true;
  }
}
