import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

class _FlakyJournal implements AppendOnlyJournal {
  @override
  Future<void> append(JournalEntry entry) async {}

  @override
  Future<List<JournalEntry>> readAll() async {
    throw StateError('journal unavailable');
  }

  @override
  Future<List<JournalEntry>> readSince(String cursor) async => [];
}

void main() {
  group('InMemoryProjectionStore — rebuild is fail-closed', () {
    test('isReady is false before the first rebuild', () {
      final store = InMemoryProjectionStore();
      expect(store.isReady, isFalse);
    });

    test('rebuild from a healthy journal becomes ready and mirrors its entries', () async {
      final journal = InMemoryJournal();
      await journal.append(JournalEntry(
        id: 'a',
        type: 'test.event',
        payload: const {},
        createdAt: DateTime(2026, 1, 1),
        schemaVersion: 1,
      ));
      final store = InMemoryProjectionStore();
      await store.rebuildFromJournal(journal);
      expect(store.isReady, isTrue);
      expect(store.snapshot.map((e) => e.id), ['a']);
    });

    test('fail-closed: a rebuild that throws leaves the store not-ready, '
        'never serving a half-built projection', () async {
      final store = InMemoryProjectionStore();
      await expectLater(
        () => store.rebuildFromJournal(_FlakyJournal()),
        throwsStateError,
      );
      expect(store.isReady, isFalse);
    });
  });
}
