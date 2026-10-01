import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

const _id = '123e4567-e89b-42d3-a456-426614174000';

class _MutableEntry extends JournalEntry {
  _MutableEntry()
    : super(
        id: _id,
        type: 'session',
        payload: const {},
        createdAt: DateTime.utc(2026),
        schemaVersion: 1,
      );
  String currentId = _id;
  @override
  String get id => currentId;
}

class _Projector implements JournalExportProjector {
  _Projector(this.callback);
  final Map<String, JournalExportCandidateValue> Function(JournalEntry)
  callback;
  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) =>
      callback(entry);
}

class _ChangingToken extends JournalExportTokenCandidate {
  _ChangingToken() : super('complete');
  int reads = 0;
  @override
  String get value => reads++ < 2 ? 'complete' : 'unapproved-marker';
}

const _policy = JournalExportPolicy(
  entriesByType: {
    'session': JournalEntryExportPolicy(
      fields: {
        'status': JournalTokenFieldPolicy(allowedValues: {'complete'}),
      },
    ),
  },
);
void main() {
  test('projector cannot change metadata after validation', () async {
    final entry = _MutableEntry();
    final journal = InMemoryJournal();
    await journal.append(entry);
    final exporter = JournalExporter(
      policy: _policy,
      projector: _Projector((entry) {
        (entry as _MutableEntry).currentId = '/private/unapproved-marker';
        return {};
      }),
    );
    final bundle = await exporter.export(journal);
    expect((jsonDecode(bundle.journalJson) as List).single['id'], _id);
    expect(bundle.journalCsv, isNot(contains('unapproved-marker')));
  });

  test(
    'candidate getter is snapshotted once before policy validation',
    () async {
      final journal = InMemoryJournal();
      await journal.append(_MutableEntry());
      final candidate = _ChangingToken();
      final bundle = await JournalExporter(
        policy: _policy,
        projector: _Projector((_) => {'status': candidate}),
      ).export(journal);
      expect(
        (jsonDecode(bundle.journalJson) as List).single['payload']['status'],
        'complete',
      );
      expect(candidate.reads, 1);
    },
  );

  test('projector cannot widen an independently configured policy', () async {
    final journal = InMemoryJournal();
    await journal.append(_MutableEntry());
    final allowed = {'complete'};
    final exporter = JournalExporter(
      policy: JournalExportPolicy(
        entriesByType: {
          'session': JournalEntryExportPolicy(
            fields: {'status': JournalTokenFieldPolicy(allowedValues: allowed)},
          ),
        },
      ),
      projector: _Projector((_) {
        allowed.add('unapproved-marker');
        return {
          'status': const JournalExportTokenCandidate('unapproved-marker'),
        };
      }),
    );
    await expectLater(
      exporter.export(journal),
      throwsA(
        isA<JournalExportException>().having(
          (e) => e.reason,
          'reason',
          JournalExportRejectReason.disallowedTokenValue,
        ),
      ),
    );
  });
}
