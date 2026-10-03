import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

const _uuid = '123e4567-e89b-42d3-a456-426614174000';
const _ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV';

JournalEntry _entry({
  String id = _uuid,
  String type = 'test.session.completed',
  Map<String, Object?>? payload,
  DateTime? createdAt,
  int schemaVersion = 1,
}) => JournalEntry(
  id: id,
  type: type,
  payload: payload ?? const {},
  createdAt: createdAt ?? DateTime.utc(2026, 8, 30),
  schemaVersion: schemaVersion,
);

const _policy = JournalExportPolicy(
  entriesByType: {
    'test.session.completed': JournalEntryExportPolicy(
      fields: {
        'status': JournalTokenFieldPolicy(allowedValues: {'complete'}),
        'count': JournalIntFieldPolicy(min: 0, max: 10),
        'verified': JournalBoolFieldPolicy(),
      },
    ),
  },
);

class _FixedProjector implements JournalExportProjector {
  const _FixedProjector(this.values);

  final Map<String, JournalExportCandidateValue> values;

  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) =>
      values;
}

class _ThrowingProjector implements JournalExportProjector {
  const _ThrowingProjector();

  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) {
    throw StateError('caller-controlled-secret');
  }
}

class _FixedJournal implements AppendOnlyJournal, BoundedJournalReader {
  _FixedJournal(this.entries);

  final List<JournalEntry> entries;

  @override
  Future<void> append(JournalEntry entry) async =>
      throw UnsupportedError('read-only test journal');

  @override
  Future<List<JournalEntry>> readAll() async => entries;

  @override
  Future<List<JournalEntry>> readForExport({required int limit}) async =>
      List.unmodifiable(entries.take(limit));

  @override
  Future<List<JournalEntry>> readSince(String cursor) async => entries;
}

Future<AppendOnlyJournal> _journalWith(JournalEntry entry) async {
  final journal = InMemoryJournal();
  await journal.append(entry);
  return journal;
}

void main() {
  group('JournalExporter safe projection', () {
    test(
      'JSON carries the projection while legacy CSV stays metadata-only',
      () async {
        final journal = await _journalWith(
          _entry(
            payload: {
              'freeText': 'private note that must not leave',
              'encodedMarker': 'QUJDREVGRw==',
              'nested': {
                'bytes': Uint8List.fromList([1, 2, 3]),
              },
            },
          ),
        );
        final exporter = JournalExporter(
          policy: _policy,
          projector: _FixedProjector({
            'status': JournalExportTokenCandidate('complete'),
            'count': JournalExportIntCandidate(3),
            'verified': JournalExportBoolCandidate(true),
          }),
        );

        final bundle = await exporter.export(journal);
        final decoded = jsonDecode(bundle.journalJson) as List<Object?>;
        final record = decoded.single as Map<String, Object?>;

        expect(record['payload'], {
          'count': 3,
          'status': 'complete',
          'verified': true,
        });
        expect(
          bundle.journalCsv.split('\n').first,
          'id,type,createdAt,schemaVersion',
        );
        expect(
          bundle.journalCsv,
          'id,type,createdAt,schemaVersion\n'
          '123e4567-e89b-42d3-a456-426614174000,'
          'test.session.completed,2026-08-30T00:00:00.000Z,1\n',
        );
        expect(bundle.journalJson, isNot(contains('private note')));
        expect(bundle.journalJson, isNot(contains('QUJDREVGRw')));
        expect(bundle.journalCsv, isNot(contains('private note')));
        expect(bundle.journalCsv, isNot(contains('QUJDREVGRw')));
      },
    );

    test('default deny-all policy rejects a non-empty journal', () async {
      final journal = await _journalWith(_entry());

      await expectLater(
        JournalExporter().export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.disallowedEntryType,
          ),
        ),
      );
    });

    test('metadata-only export requires an exact entry-type policy', () async {
      final journal = await _journalWith(_entry());
      const metadataPolicy = JournalExportPolicy(
        entriesByType: {
          'test.session.completed': JournalEntryExportPolicy(fields: {}),
        },
      );

      final bundle = await JournalExporter(
        policy: metadataPolicy,
      ).export(journal);
      final decoded = jsonDecode(bundle.journalJson) as List<Object?>;
      expect((decoded.single as Map<String, Object?>)['payload'], isEmpty);
      expect(bundle.journalCsv, isNot(contains('{}')));
    });

    test('UUID and ULID identifiers are accepted', () async {
      const metadataPolicy = JournalExportPolicy(
        entriesByType: {
          'test.session.completed': JournalEntryExportPolicy(fields: {}),
        },
      );
      final journal = InMemoryJournal();
      await journal.append(_entry());
      await journal.append(_entry(id: _ulid));

      final bundle = await JournalExporter(
        policy: metadataPolicy,
      ).export(journal);
      expect(jsonDecode(bundle.journalJson), hasLength(2));
    });

    test('CSV-safe date and schema boundaries are accepted', () async {
      final journal = await _journalWith(
        _entry(createdAt: DateTime.utc(9999, 12, 31), schemaVersion: 0),
      );

      final bundle = await JournalExporter(policy: _policy).export(journal);

      expect(bundle.journalCsv, contains('9999-12-31T00:00:00.000Z,0'));
    });

    for (final unsafeEntry in [
      _entry(createdAt: DateTime.utc(10000)),
      _entry(createdAt: DateTime.utc(-1)),
      _entry(schemaVersion: -1),
    ]) {
      test(
        'formula-prefixed typed CSV metadata rejects the entire export',
        () async {
          await expectLater(
            JournalExporter(
              policy: _policy,
            ).export(await _journalWith(unsafeEntry)),
            throwsA(
              isA<JournalExportException>().having(
                (error) => error.reason,
                'reason',
                JournalExportRejectReason.unsafeValue,
              ),
            ),
          );
        },
      );
    }

    for (final prefix in ['=', '+', '-', '@']) {
      test(
        'all formula prefixes are rejected from identifier cells: $prefix',
        () async {
          await expectLater(
            JournalExporter(
              policy: _policy,
            ).export(await _journalWith(_entry(id: '${prefix}fixture'))),
            throwsA(isA<JournalExportException>()),
          );
        },
      );

      test(
        'all formula prefixes are rejected from type cells: $prefix',
        () async {
          final type = '${prefix}fixture';
          final policy = JournalExportPolicy(
            entriesByType: {type: const JournalEntryExportPolicy(fields: {})},
          );
          await expectLater(
            JournalExporter(
              policy: policy,
            ).export(await _journalWith(_entry(type: type))),
            throwsA(isA<JournalExportException>()),
          );
        },
      );
    }

    for (final unsafeId in [
      'a',
      '123E4567-E89B-42D3-A456-426614174000',
      '../private/file',
      '=IMPORTXML',
      '81ARZ3NDEKTSV4RRFFQ69G5FAV',
    ]) {
      test('unsafe identifier is rejected: $unsafeId', () async {
        final journal = await _journalWith(_entry(id: unsafeId));

        await expectLater(
          JournalExporter(policy: _policy).export(journal),
          throwsA(
            isA<JournalExportException>().having(
              (error) => error.reason,
              'reason',
              JournalExportRejectReason.unsafeIdentifier,
            ),
          ),
        );
      });
    }

    test('regex-valid but non-member token is rejected', () async {
      final journal = await _journalWith(_entry());
      final exporter = JournalExporter(
        policy: _policy,
        projector: _FixedProjector({
          'status': JournalExportTokenCandidate('QUJDREVGRw'),
        }),
      );

      await expectLater(
        exporter.export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.disallowedTokenValue,
          ),
        ),
      );
    });

    test('unknown projected key is rejected', () async {
      final journal = await _journalWith(_entry());
      final exporter = JournalExporter(
        policy: _policy,
        projector: _FixedProjector({'other': JournalExportBoolCandidate(true)}),
      );

      await expectLater(
        exporter.export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.disallowedProjectedKey,
          ),
        ),
      );
    });

    test('unknown and forbidden entry types are rejected', () async {
      final unknown = await _journalWith(_entry(type: 'test.unknown'));
      const forbiddenPolicy = JournalExportPolicy(
        entriesByType: {
          'test.video.completed': JournalEntryExportPolicy(fields: {}),
        },
      );
      final forbidden = await _journalWith(
        _entry(type: 'test.video.completed'),
      );

      await expectLater(
        JournalExporter(policy: _policy).export(unknown),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.disallowedEntryType,
          ),
        ),
      );
      await expectLater(
        JournalExporter(policy: forbiddenPolicy).export(forbidden),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.disallowedEntryType,
          ),
        ),
      );
    });

    test('more than sixteen projected fields is rejected', () async {
      final policies = <String, JournalExportFieldPolicy>{};
      final values = <String, JournalExportCandidateValue>{};
      for (var index = 0; index < 17; index++) {
        final key = 'flag_$index';
        policies[key] = const JournalBoolFieldPolicy();
        values[key] = const JournalExportBoolCandidate(true);
      }
      final policy = JournalExportPolicy(
        entriesByType: {
          'test.session.completed': JournalEntryExportPolicy(fields: policies),
        },
      );
      final journal = await _journalWith(_entry());

      await expectLater(
        JournalExporter(
          policy: policy,
          projector: _FixedProjector(values),
        ).export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.tooManyFields,
          ),
        ),
      );
    });

    test('candidate shape and integer bounds are enforced', () async {
      final journal = await _journalWith(_entry());
      final wrongShape = JournalExporter(
        policy: _policy,
        projector: _FixedProjector({'count': JournalExportBoolCandidate(true)}),
      );
      final outOfRange = JournalExporter(
        policy: _policy,
        projector: _FixedProjector({'count': JournalExportIntCandidate(11)}),
      );

      await expectLater(
        wrongShape.export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.valueShapeMismatch,
          ),
        ),
      );
      await expectLater(
        outOfRange.export(journal),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.unsafeValue,
          ),
        ),
      );
    });

    test(
      'entry and encoded-byte limits fail without returning a bundle',
      () async {
        final journal = InMemoryJournal();
        await journal.append(_entry());
        await journal.append(_entry(id: _ulid));

        await expectLater(
          JournalExporter(
            policy: _policy,
            limits: JournalExportLimits(maxEntries: 1),
          ).export(journal),
          throwsA(
            isA<JournalExportException>().having(
              (error) => error.reason,
              'reason',
              JournalExportRejectReason.tooManyEntries,
            ),
          ),
        );
        await expectLater(
          JournalExporter(
            policy: _policy,
            limits: JournalExportLimits(maxEncodedBytes: 1),
          ).export(await _journalWith(_entry())),
          throwsA(
            isA<JournalExportException>().having(
              (error) => error.reason,
              'reason',
              JournalExportRejectReason.encodedSizeExceeded,
            ),
          ),
        );
      },
    );

    test('hard maxima are named and upward overrides fail at construction', () {
      expect(JournalExportLimits.hardMaxEntries, 10000);
      expect(JournalExportLimits.hardMaxFieldsPerEntry, 16);
      expect(JournalExportLimits.hardMaxEncodedBytes, 2 * 1024 * 1024);

      final defaults = JournalExportLimits();
      expect(defaults.maxEntries, JournalExportLimits.hardMaxEntries);
      expect(
        defaults.maxFieldsPerEntry,
        JournalExportLimits.hardMaxFieldsPerEntry,
      );
      expect(defaults.maxEncodedBytes, JournalExportLimits.hardMaxEncodedBytes);
      expect(() => JournalExportLimits(maxEntries: 10001), throwsArgumentError);
      expect(
        () => JournalExportLimits(maxFieldsPerEntry: 17),
        throwsArgumentError,
      );
      expect(
        () => JournalExportLimits(maxEncodedBytes: 2 * 1024 * 1024 + 1),
        throwsArgumentError,
      );
    });

    test('10,001 entries fail closed at the hard entry maximum', () async {
      final entries = List<JournalEntry>.filled(10001, _entry());

      await expectLater(
        JournalExporter(policy: _policy).export(_FixedJournal(entries)),
        throwsA(
          isA<JournalExportException>().having(
            (error) => error.reason,
            'reason',
            JournalExportRejectReason.tooManyEntries,
          ),
        ),
      );
    });

    test(
      'the real default 2 MiB aggregate artifact limit fails closed',
      () async {
        final entries = List<JournalEntry>.filled(10000, _entry());

        await expectLater(
          JournalExporter(policy: _policy).export(_FixedJournal(entries)),
          throwsA(
            isA<JournalExportException>().having(
              (error) => error.reason,
              'reason',
              JournalExportRejectReason.encodedSizeExceeded,
            ),
          ),
        );
      },
    );

    test(
      'projector failures do not expose caller-controlled messages',
      () async {
        final journal = await _journalWith(_entry());

        await expectLater(
          JournalExporter(
            policy: _policy,
            projector: _ThrowingProjector(),
          ).export(journal),
          throwsA(
            isA<JournalExportException>()
                .having(
                  (error) => error.reason,
                  'reason',
                  JournalExportRejectReason.projectorFailure,
                )
                .having(
                  (error) => error.toString(),
                  'message',
                  isNot(contains('caller-controlled-secret')),
                ),
          ),
        );
      },
    );
  });
}
