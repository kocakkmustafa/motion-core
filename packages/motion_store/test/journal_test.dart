import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

JournalEntry _entry(String id, {DateTime? at}) => JournalEntry(
      id: id,
      type: 'test.event',
      payload: {'k': 'v'},
      createdAt: at ?? DateTime(2026, 1, 1),
      schemaVersion: 1,
    );

void main() {
  group('InMemoryJournal — append-only', () {
    test('readAll returns entries in append order', () async {
      final journal = InMemoryJournal();
      await journal.append(_entry('a'));
      await journal.append(_entry('b'));
      await journal.append(_entry('c'));
      final all = await journal.readAll();
      expect(all.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('readSince a known cursor returns only entries after it', () async {
      final journal = InMemoryJournal();
      await journal.append(_entry('a'));
      await journal.append(_entry('b'));
      await journal.append(_entry('c'));
      final since = await journal.readSince('a');
      expect(since.map((e) => e.id), ['b', 'c']);
    });

    test('fail-closed: readSince an unrecognized cursor returns everything '
        'rather than silently dropping provenance', () async {
      final journal = InMemoryJournal();
      await journal.append(_entry('a'));
      await journal.append(_entry('b'));
      final since = await journal.readSince('never-seen-cursor');
      expect(since.map((e) => e.id), ['a', 'b']);
    });

    test('readAll returns an unmodifiable view', () async {
      final journal = InMemoryJournal();
      await journal.append(_entry('a'));
      final all = await journal.readAll();
      expect(() => all.add(_entry('b')), throwsUnsupportedError);
    });
  });
}
