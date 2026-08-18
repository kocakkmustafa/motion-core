import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

void main() {
  group('JournalExporter', () {
    test('exports every journal entry as both JSON and CSV', () async {
      final journal = InMemoryJournal();
      await journal.append(JournalEntry(
        id: 'a',
        type: 'test.event',
        payload: const {'k': 'v'},
        createdAt: DateTime.utc(2026, 1, 1),
        schemaVersion: 1,
      ));

      final bundle = await JournalExporter().export(journal);

      final decoded = jsonDecode(bundle.journalJson) as List<Object?>;
      expect(decoded, hasLength(1));
      expect((decoded.single as Map<String, Object?>)['id'], 'a');

      expect(bundle.journalCsv, contains('id,type,createdAt,schemaVersion'));
      expect(bundle.journalCsv, contains('a,test.event,'));
    });

    test('an empty journal exports a header-only CSV and an empty JSON array', () async {
      final bundle = await JournalExporter().export(InMemoryJournal());
      expect(jsonDecode(bundle.journalJson), isEmpty);
      expect(bundle.journalCsv.trim().split('\n'), hasLength(1));
    });
  });
}
