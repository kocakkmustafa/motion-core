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
       _limits = JournalExportLimits.snapshot(limits ?? JournalExportLimits());

  final JournalExportProjector projector;
  final JournalExportPolicy policy;
  final JournalExportLimits _limits;
  JournalExportLimits get limits => _limits;

  Future<ExportBundle> export(AppendOnlyJournal journal) async {
    if (journal is! BoundedJournalReader) {
      throw const JournalExportException(
        JournalExportRejectReason.unboundedJournal,
      );
    }
    final prefix = await (journal as BoundedJournalReader).readForExport(
      limit: _limits.maxEntries + 1,
    );
    final entryCount = prefix.length;
    if (entryCount > _limits.maxEntries) {
      throw const JournalExportException(
        JournalExportRejectReason.tooManyEntries,
      );
    }
    final entries = List<JournalEntry>.generate(
      entryCount,
      (index) => prefix[index],
      growable: false,
    );

    const csvHeader = 'id,type,createdAt,schemaVersion\n';
    final json = StringBuffer('[');
    final csv = StringBuffer(csvHeader);
    // Reserve both JSON brackets and the CSV header before visiting entries.
    var encodedBytes = 2 + csvHeader.length;
    if (encodedBytes > _limits.maxEncodedBytes) {
      throw const JournalExportException(
        JournalExportRejectReason.encodedSizeExceeded,
      );
    }
    var first = true;
    for (final entry in entries) {
      final projected = _project(entry);
      final jsonRow = _toJsonEntry(projected);
      final csvRow = _toCsvRow(projected);
      final addedBytes =
          utf8.encode(jsonRow).length +
          utf8.encode(csvRow).length +
          (first ? 0 : 1);
      if (addedBytes > _limits.maxEncodedBytes - encodedBytes) {
        throw const JournalExportException(
          JournalExportRejectReason.encodedSizeExceeded,
        );
      }
      encodedBytes += addedBytes;
      if (!first) json.write(',');
      json.write(jsonRow);
      csv.write(csvRow);
      first = false;
    }
    json.write(']');
    return ExportBundle(
      journalJson: json.toString(),
      journalCsv: csv.toString(),
    );
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
      projected = projector.project(entry);
    } catch (_) {
      throw const JournalExportException(
        JournalExportRejectReason.projectorFailure,
      );
    }
    try {
      if (projected.length > _limits.maxFieldsPerEntry) {
        throw const JournalExportException(
          JournalExportRejectReason.tooManyFields,
        );
      }

      final payload = SplayTreeMap<String, Object?>();
      var fieldCount = 0;
      for (final field in projected.entries) {
        if (++fieldCount > _limits.maxFieldsPerEntry) {
          throw const JournalExportException(
            JournalExportRejectReason.tooManyFields,
          );
        }
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
    } on JournalExportException {
      rethrow;
    } catch (_) {
      // Lazy map/value access is caller-owned projection code too. Return
      // only a closed reason, never its arbitrary exception text.
      throw const JournalExportException(
        JournalExportRejectReason.projectorFailure,
      );
    }
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

  String _toJsonEntry(_ProjectedEntry e) => jsonEncode({
    'id': e.entry.id,
    'type': e.entry.type,
    'payload': e.payload,
    'createdAt': e.entry.createdAt.toIso8601String(),
    'schemaVersion': e.entry.schemaVersion,
  });

  String _toCsvRow(_ProjectedEntry e) =>
      '${_csvField(e.entry.id)},${_csvField(e.entry.type)},'
      '${_csvField(e.entry.createdAt.toIso8601String())},'
      '${e.entry.schemaVersion}\n';

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
