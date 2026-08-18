import 'dart:convert';

import 'journal.dart';
import 'journal_entry.dart';

class ExportBundle {
  const ExportBundle({required this.journalJson, required this.journalCsv});

  final String journalJson;
  final String journalCsv;
}

/// Produces a user-facing data export (JSON + CSV) of an entire journal.
class JournalExporter {
  Future<ExportBundle> export(AppendOnlyJournal journal) async {
    final entries = await journal.readAll();
    return ExportBundle(
      journalJson: _toJson(entries),
      journalCsv: _toCsv(entries),
    );
  }

  String _toJson(List<JournalEntry> entries) => jsonEncode([
        for (final e in entries)
          {
            'id': e.id,
            'type': e.type,
            'payload': e.payload,
            'createdAt': e.createdAt.toIso8601String(),
            'schemaVersion': e.schemaVersion,
          },
      ]);

  String _toCsv(List<JournalEntry> entries) {
    final buffer = StringBuffer('id,type,createdAt,schemaVersion\n');
    for (final e in entries) {
      buffer.writeln(
        '${_csvField(e.id)},${_csvField(e.type)},'
        '${_csvField(e.createdAt.toIso8601String())},${e.schemaVersion}',
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
}
