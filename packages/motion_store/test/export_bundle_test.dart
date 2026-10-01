import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

void main() {
  group('JournalExporter', () {
    test(
      'exports policy-approved journal metadata as both JSON and CSV',
      () async {
        final journal = InMemoryJournal();
        await journal.append(
          JournalEntry(
            id: '123e4567-e89b-42d3-a456-426614174000',
            type: 'test.event',
            payload: const {'k': 'v'},
            createdAt: DateTime.utc(2026, 1, 1),
            schemaVersion: 1,
          ),
        );

        const policy = JournalExportPolicy(
          entriesByType: {'test.event': JournalEntryExportPolicy(fields: {})},
        );
        final bundle = await JournalExporter(policy: policy).export(journal);

        final decoded = jsonDecode(bundle.journalJson) as List<Object?>;
        expect(decoded, hasLength(1));
        expect(
          (decoded.single as Map<String, Object?>)['id'],
          '123e4567-e89b-42d3-a456-426614174000',
        );
        expect((decoded.single as Map<String, Object?>)['payload'], isEmpty);

        expect(
          bundle.journalCsv,
          'id,type,createdAt,schemaVersion\n'
          '123e4567-e89b-42d3-a456-426614174000,test.event,'
          '2026-01-01T00:00:00.000Z,1\n',
        );
      },
    );

    test(
      'an empty journal exports a header-only CSV and an empty JSON array',
      () async {
        final bundle = await JournalExporter().export(InMemoryJournal());
        expect(jsonDecode(bundle.journalJson), isEmpty);
        expect(bundle.journalCsv.trim().split('\n'), hasLength(1));
      },
    );
  });
}
