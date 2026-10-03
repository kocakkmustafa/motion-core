import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_store/motion_store.dart';

const _policy = JournalExportPolicy(
  entriesByType: {'test.event': JournalEntryExportPolicy(fields: {})},
);

JournalEntry _entry() => JournalEntry(
  id: '123e4567-e89b-42d3-a456-426614174000',
  type: 'test.event',
  payload: const {},
  createdAt: DateTime.utc(2026),
  schemaVersion: 1,
);

class _LegacyJournal implements AppendOnlyJournal {
  var readAllCalls = 0;

  @override
  Future<void> append(JournalEntry entry) async {}

  @override
  Future<List<JournalEntry>> readAll() async {
    readAllCalls++;
    return [_entry()];
  }

  @override
  Future<List<JournalEntry>> readSince(String cursor) async => [];
}

class _BoundedReadTrapJournal extends InMemoryJournal {
  var readAllCalls = 0;
  int? requestedLimit;

  @override
  Future<List<JournalEntry>> readAll() async {
    readAllCalls++;
    throw StateError('unbounded history read must not run');
  }

  // The new capability's contract: read the requested storage prefix only.
  @override
  Future<List<JournalEntry>> readForExport({required int limit}) async {
    requestedLimit = limit;
    return [_entry(), _entry(), _entry()].take(limit).toList();
  }
}

class _CountingProjector implements JournalExportProjector {
  var calls = 0;

  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) {
    calls++;
    return const {};
  }
}

class _OversizedMap extends MapBase<String, JournalExportCandidateValue> {
  @override
  int get length => 1000000;

  @override
  Iterable<String> get keys =>
      throw StateError('oversized projection must not be copied or iterated');

  @override
  JournalExportCandidateValue? operator [](Object? key) => null;

  @override
  void operator []=(String key, JournalExportCandidateValue value) =>
      throw UnsupportedError('read-only');

  @override
  void clear() => throw UnsupportedError('read-only');

  @override
  JournalExportCandidateValue? remove(Object? key) =>
      throw UnsupportedError('read-only');
}

class _OversizedProjector implements JournalExportProjector {
  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) =>
      _OversizedMap();
}

class _LazyFailureMap extends _OversizedMap {
  @override
  int get length => 1;

  @override
  Iterable<String> get keys => throw StateError('sensitive-projector-detail');
}

class _LazyFailureProjector implements JournalExportProjector {
  @override
  Map<String, JournalExportCandidateValue> project(JournalEntry entry) =>
      _LazyFailureMap();
}

class _MutableLimits extends JournalExportLimits {
  int currentBytes = 0;

  @override
  int get maxEncodedBytes => currentBytes;
}

class _WideningExporter extends JournalExporter {
  _WideningExporter()
    : super(policy: _policy, limits: JournalExportLimits(maxEncodedBytes: 0));

  @override
  JournalExportLimits get limits => JournalExportLimits();
}

Matcher _rejects(String reason) => throwsA(
  isA<JournalExportException>().having(
    (error) => error.reason.name,
    'reason',
    reason,
  ),
);

void main() {
  test('exporter getter overrides cannot widen configured limits', () async {
    final journal = InMemoryJournal();
    await journal.append(_entry());
    await expectLater(
      _WideningExporter().export(journal),
      _rejects('encodedSizeExceeded'),
    );
  });

  test(
    'configured byte limits are snapshotted before caller mutation',
    () async {
      final limits = _MutableLimits();
      final exporter = JournalExporter(policy: _policy, limits: limits);
      limits.currentBytes = JournalExportLimits.hardMaxEncodedBytes + 1;
      final journal = InMemoryJournal();
      await journal.append(_entry());
      await expectLater(
        exporter.export(journal),
        _rejects('encodedSizeExceeded'),
      );
      expect(exporter.limits.maxEncodedBytes, 0);
    },
  );

  test(
    'lazy projector map failures return only a sanitized rejection',
    () async {
      final journal = InMemoryJournal();
      await journal.append(_entry());
      await expectLater(
        JournalExporter(
          policy: _policy,
          projector: _LazyFailureProjector(),
        ).export(journal),
        throwsA(
          isA<JournalExportException>()
              .having(
                (error) => error.reason.name,
                'reason',
                'projectorFailure',
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('sensitive-projector-detail')),
              ),
        ),
      );
    },
  );

  test('legacy readers reject without an unbounded history read', () async {
    final journal = _LegacyJournal();
    await expectLater(
      JournalExporter(policy: _policy).export(journal),
      _rejects('unboundedJournal'),
    );
    expect(journal.readAllCalls, 0);
  });

  test('reader requests only the entry limit plus overflow sentinel', () async {
    final journal = _BoundedReadTrapJournal();
    await expectLater(
      JournalExporter(
        policy: _policy,
        limits: JournalExportLimits(maxEntries: 1),
      ).export(journal),
      _rejects('tooManyEntries'),
    );
    expect(journal.requestedLimit, 2);
    expect(journal.readAllCalls, 0);
  });

  test('zero-entry limit still detects a nonempty journal', () async {
    final journal = _BoundedReadTrapJournal();
    await expectLater(
      JournalExporter(
        policy: _policy,
        limits: JournalExportLimits(maxEntries: 0),
      ).export(journal),
      _rejects('tooManyEntries'),
    );
    expect(journal.requestedLimit, 1);
    expect(journal.readAllCalls, 0);
  });

  test('aggregate byte budget is exact for JSON and CSV together', () async {
    final journal = InMemoryJournal();
    await journal.append(_entry());
    final baseline = await JournalExporter(policy: _policy).export(journal);
    final bytes =
        utf8.encode(baseline.journalJson).length +
        utf8.encode(baseline.journalCsv).length;
    final equal = await JournalExporter(
      policy: _policy,
      limits: JournalExportLimits(maxEncodedBytes: bytes),
    ).export(journal);
    expect(equal.journalJson, baseline.journalJson);
    expect(equal.journalCsv, baseline.journalCsv);
    await expectLater(
      JournalExporter(
        policy: _policy,
        limits: JournalExportLimits(maxEncodedBytes: bytes - 1),
      ).export(journal),
      _rejects('encodedSizeExceeded'),
    );
  });

  test('encoding stops projecting once the aggregate budget is full', () async {
    final journal = InMemoryJournal();
    await journal.append(_entry());
    final single = await JournalExporter(policy: _policy).export(journal);
    final bytes =
        utf8.encode(single.journalJson).length +
        utf8.encode(single.journalCsv).length;
    await journal.append(_entry());
    await journal.append(_entry());
    final projector = _CountingProjector();
    await expectLater(
      JournalExporter(
        policy: _policy,
        projector: projector,
        limits: JournalExportLimits(maxEncodedBytes: bytes),
      ).export(journal),
      _rejects('encodedSizeExceeded'),
    );
    expect(projector.calls, 2);
  });

  test('oversized projector output rejects before map iteration', () async {
    final journal = InMemoryJournal();
    await journal.append(_entry());
    await expectLater(
      JournalExporter(
        policy: _policy,
        projector: _OversizedProjector(),
      ).export(journal),
      _rejects('tooManyFields'),
    );
  });
}
