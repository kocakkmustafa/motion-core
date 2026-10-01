import 'dart:collection';
import 'dart:convert';

import 'journal.dart';
import 'journal_entry.dart';
import 'journal_export_policy.dart';

class ExportBundle {
  const ExportBundle({required this.journalJson, required this.journalCsv});

  final String journalJson;
  final String journalCsv;
}

/// Produces a user-facing data export from policy-approved projections only.
class JournalExporter {
  JournalExporter({
    this.projector = const MetadataOnlyJournalProjector(),
    JournalExportPolicy policy = const JournalExportPolicy.denyAll(),
    JournalExportLimits? limits,
  }) : policy = JournalExportPolicy.snapshot(policy),
       limits = limits ?? JournalExportLimits();

  final JournalExportProjector projector;
  final JournalExportPolicy policy;
  final JournalExportLimits limits;

  Future<ExportBundle> export(AppendOnlyJournal journal) async {
    final entries = await journal.readAll();
    if (entries.length > limits.maxEntries) {
      throw const JournalExportException(
        JournalExportRejectReason.tooManyEntries,
      );
    }

    final safeEntries = <_ProjectedEntry>[];
    for (final entry in entries) {
      safeEntries.add(_project(entry));
    }

    final journalJson = _toJson(safeEntries);
    final journalCsv = _toCsv(safeEntries);
    final encodedBytes =
        utf8.encode(journalJson).length + utf8.encode(journalCsv).length;
    if (encodedBytes > limits.maxEncodedBytes) {
      throw const JournalExportException(
        JournalExportRejectReason.encodedSizeExceeded,
      );
    }
    return ExportBundle(journalJson: journalJson, journalCsv: journalCsv);
  }

  _ProjectedEntry _project(JournalEntry entry) {
    // Snapshot metadata before invoking caller-owned projection code. The
    // original entry remains available to the projector, never to serialization.
    final createdAt = entry.createdAt;
    final metadata = JournalEntry(
      id: entry.id,
      type: entry.type,
      payload: const {},
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        createdAt.microsecondsSinceEpoch,
        isUtc: createdAt.isUtc,
      ),
      schemaVersion: entry.schemaVersion,
    );
    if (!_isSafeIdentifier(metadata.id)) {
      throw const JournalExportException(
        JournalExportRejectReason.unsafeIdentifier,
      );
    }
    final entryPolicy = policy.entriesByType[metadata.type];
    if (entryPolicy == null || !_isSafeKey(metadata.type)) {
      throw const JournalExportException(
        JournalExportRejectReason.disallowedEntryType,
      );
    }
    if (_hasFormulaPrefixedMetadata(metadata)) {
      throw const JournalExportException(JournalExportRejectReason.unsafeValue);
    }

    Map<String, JournalExportCandidateValue> projected;
    try {
      projected = Map.of(projector.project(entry));
    } catch (_) {
      throw const JournalExportException(
        JournalExportRejectReason.projectorFailure,
      );
    }
    if (projected.length > limits.maxFieldsPerEntry) {
      throw const JournalExportException(
        JournalExportRejectReason.tooManyFields,
      );
    }

    final payload = SplayTreeMap<String, Object?>();
    for (final field in projected.entries) {
      if (!_isSafeKey(field.key)) {
        throw const JournalExportException(
          JournalExportRejectReason.unsafeFieldKey,
        );
      }
      final fieldPolicy = entryPolicy.fields[field.key];
      if (fieldPolicy == null) {
        throw const JournalExportException(
          JournalExportRejectReason.disallowedProjectedKey,
        );
      }
      payload[field.key] = _validateValue(field.value, fieldPolicy);
    }

    return _ProjectedEntry(entry: metadata, payload: payload);
  }

  Object _validateValue(
    JournalExportCandidateValue candidate,
    JournalExportFieldPolicy fieldPolicy,
  ) {
    if (candidate is JournalExportTokenCandidate) {
      final value = candidate.value;
      if (fieldPolicy is! JournalTokenFieldPolicy) {
        throw const JournalExportException(
          JournalExportRejectReason.valueShapeMismatch,
        );
      }
      if (!_safeTokenPattern.hasMatch(value) ||
          !Set<String>.of(fieldPolicy.allowedValues).contains(value)) {
        throw const JournalExportException(
          JournalExportRejectReason.disallowedTokenValue,
        );
      }
      return value;
    }
    if (candidate is JournalExportIntCandidate) {
      final value = candidate.value;
      if (fieldPolicy is! JournalIntFieldPolicy) {
        throw const JournalExportException(
          JournalExportRejectReason.valueShapeMismatch,
        );
      }
      if (value < -1000000 ||
          value > 1000000 ||
          value < fieldPolicy.min ||
          value > fieldPolicy.max) {
        throw const JournalExportException(
          JournalExportRejectReason.unsafeValue,
        );
      }
      return value;
    }
    if (candidate is JournalExportBoolCandidate) {
      final value = candidate.value;
      if (fieldPolicy is! JournalBoolFieldPolicy) {
        throw const JournalExportException(
          JournalExportRejectReason.valueShapeMismatch,
        );
      }
      return value;
    }
    throw const JournalExportException(JournalExportRejectReason.unsafeValue);
  }

  String _toJson(List<_ProjectedEntry> entries) => jsonEncode([
    for (final e in entries)
      {
        'id': e.entry.id,
        'type': e.entry.type,
        'payload': e.payload,
        'createdAt': e.entry.createdAt.toIso8601String(),
        'schemaVersion': e.entry.schemaVersion,
      },
  ]);

  String _toCsv(List<_ProjectedEntry> entries) {
    final buffer = StringBuffer('id,type,createdAt,schemaVersion\n');
    for (final e in entries) {
      buffer.writeln(
        '${_csvField(e.entry.id)},${_csvField(e.entry.type)},'
        '${_csvField(e.entry.createdAt.toIso8601String())},'
        '${e.entry.schemaVersion}',
      );
    }
    return buffer.toString();
  }

  String _csvField(String value) {
    final escaped = value.replaceAll('"', '""');
    return value.contains(',') || value.contains('"') || value.contains('\n')
        ? '"$escaped"'
        : escaped;
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _ulidPattern = RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');
  static final _safeKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,39}$');
  static final _safeTokenPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,39}$');
  static const _forbiddenKeySubstrings = [
    'angle',
    'landmark',
    'audio',
    'video',
    'injury',
    'song',
    'choreography',
    'freetext',
    'free_text',
    'note',
    'comment',
  ];

  bool _isSafeIdentifier(String value) =>
      _uuidPattern.hasMatch(value) || _ulidPattern.hasMatch(value);

  bool _isFormulaPrefixed(String value) =>
      value.isNotEmpty && const {'=', '+', '-', '@'}.contains(value[0]);

  bool _hasFormulaPrefixedMetadata(JournalEntry entry) => [
    entry.id,
    entry.type,
    entry.createdAt.toIso8601String(),
    entry.schemaVersion.toString(),
  ].any(_isFormulaPrefixed);

  bool _isSafeKey(String value) {
    if (!_safeKeyPattern.hasMatch(value)) return false;
    final lower = value.toLowerCase();
    return !_forbiddenKeySubstrings.any(lower.contains);
  }
}

class _ProjectedEntry {
  const _ProjectedEntry({required this.entry, required this.payload});

  final JournalEntry entry;
  final Map<String, Object?> payload;
}
