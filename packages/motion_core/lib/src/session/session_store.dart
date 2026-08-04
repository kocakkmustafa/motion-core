import 'dart:convert';
import 'dart:io';

/// Completed-session record — the family's promoted persistence schema
/// (M-F-193 arbitration over J-064 + two delta contracts; decision record:
/// `workspace/SESSION-STORE-TERFI-KARARI.md`).
///
/// **Why so few fields:** every stored field is an invitation for a product
/// surface to lean on it. There is deliberately NO verdict/score field —
/// recording zeros before the camera bridge would draw zeros on tomorrow's
/// progress chart. Attempt-level provenance (ADR-005: analysisConfidence,
/// orientationStrategy, model SHA) is deliberately absent too: that is
/// attempt-level data, this is a session-level record.
final class SessionRecord {
  const SessionRecord({
    required this.lessonId,
    required this.completedAt,
    required this.workedSeconds,
    required this.unitsCompleted,
    required this.plannedUnits,
    required this.unitLabel,
    required this.lessonClass,
    this.unmeasuredUnits = 0,
    this.unmeasuredReason,
  });

  final String lessonId;
  final DateTime completedAt;

  /// Seconds actually WORKED — rest excluded. Progress gates count work;
  /// including rest would pass gates the user has not earned (J-064).
  final int workedSeconds;

  /// MEASURED units only. Units the engine saw but could not judge live in
  /// [unmeasuredUnits] — the two are different facts and conflating them
  /// hides which part of the user's work went unjudged.
  final int unitsCompleted;
  final int plannedUnits;

  /// The unit THIS record counts in — per-record, never per-app: Gravita
  /// measured 22 rep-unit and 8 second-unit movements in ONE catalog, and
  /// "3 of 5 reps" sits next to "45 of 60 seconds" on one progress screen.
  ///
  /// Known degeneration, accepted and documented (arbitration §5): when
  /// [unitLabel] is `'second'`, [unitsCompleted] duplicates [workedSeconds].
  /// Surfaces must not present the two as independent facts.
  final String unitLabel;

  /// The lesson's class AT WRITE TIME — open vocabulary (apps own their
  /// words: `scored`, `demoOnly`, `measurementOnly`, ...). Written, never
  /// derived later: classes change as measurement matures, and a
  /// class computed after the fact silently reinterprets history — sessions
  /// from before a lesson's promotion must never read as graded.
  final String lessonClass;

  /// Units attempted but not judgeable (framing/light/tracking...). The
  /// alternative — not recording them — would make tomorrow's surface claim
  /// "3 reps" when the user did 4 and one went unmeasured: silence lies.
  final int unmeasuredUnits;
  final String? unmeasuredReason;

  /// Everything the user actually did, measured or not.
  int get attemptedUnits => unitsCompleted + unmeasuredUnits;

  /// Completion is a MEASUREMENT of work done, not a verdict — an
  /// unmeasurable unit still happened, so completion counts attempts
  /// ("an unanalysable attempt never lowers progress").
  bool get isComplete => attemptedUnits >= plannedUnits;

  /// Family least-privilege read (M-F-193 §3): only the shared value
  /// `'scored'` reads as scored. An unknown, empty or app-specific class
  /// NEVER reads as scored — when in doubt, claim less.
  bool get isScoredClass => lessonClass == 'scored';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lessonId': lessonId,
        'completedAt': completedAt.toUtc().toIso8601String(),
        'workedSeconds': workedSeconds,
        'unitsCompleted': unitsCompleted,
        'plannedUnits': plannedUnits,
        'unitLabel': unitLabel,
        'lessonClass': lessonClass,
        if (unmeasuredUnits != 0) 'unmeasuredUnits': unmeasuredUnits,
        if (unmeasuredReason != null) 'unmeasuredReason': unmeasuredReason,
      };

  factory SessionRecord.fromJson(Map<String, dynamic> j) => SessionRecord(
        lessonId: j['lessonId'] as String,
        completedAt: DateTime.parse(j['completedAt'] as String),
        workedSeconds: (j['workedSeconds'] as num).toInt(),
        unitsCompleted: (j['unitsCompleted'] as num).toInt(),
        plannedUnits: (j['plannedUnits'] as num).toInt(),
        unitLabel: j['unitLabel'] as String,
        lessonClass: j['lessonClass'] as String,
        unmeasuredUnits: (j['unmeasuredUnits'] as num?)?.toInt() ?? 0,
        unmeasuredReason: j['unmeasuredReason'] as String?,
      );

  /// JabLab's v1 line shape (rounds vocabulary, no class/label fields).
  /// `lessonClass` maps to `''` — which the least-privilege rule reads as
  /// not-scored, matching what those surfaces actually showed (facts, never
  /// marks). Full migration happens on JabLab's adoption turn.
  factory SessionRecord.fromV1Json(Map<String, dynamic> j) => SessionRecord(
        lessonId: j['lessonId'] as String,
        completedAt: DateTime.parse(j['completedAt'] as String),
        workedSeconds: (j['workedSeconds'] as num).toInt(),
        unitsCompleted: (j['roundsCompleted'] as num).toInt(),
        plannedUnits: (j['plannedRounds'] as num).toInt(),
        unitLabel: 'round',
        lessonClass: '',
      );
}

/// Session-history store — interface deliberately narrow (append, read
/// recent, sum work). Query needs grow when MEASURED, not speculatively.
abstract interface class SessionStore {
  Future<void> append(SessionRecord record);

  /// Newest FIRST. All records when [limit] is null.
  Future<List<SessionRecord>> recent({int? limit});

  /// Total worked seconds for one lesson — what progress gates ask.
  Future<int> workedSecondsFor(String lessonId);

  /// How many stored records THIS store could not read (corrupt lines,
  /// versions this reader cannot parse). REQUIRED with no default — a
  /// default of 0 would let a data-losing implementation stay silent on
  /// the one question it must answer (M-F-228; JabLab's measured case:
  /// 40 of 50 lines corrupt and the summary said "10 sessions" with full
  /// confidence — the "you did less" lie). Stores whose read path is
  /// structurally all-or-nothing return 0 AS A DECLARATION, not a default.
  ///
  /// Surfaces derive their own three-state reading from this + open
  /// failure: ok (opened, 0) · partial(n) (opened, n>0 — totals are a
  /// floor, say so) · unavailable (open failed — "hiç yapmadın ≠
  /// bilmiyorum" applies, no numbers shown). The tri-state TYPE stays
  /// app-side until the shell arbitration promotes a shared surface.
  Future<int> unreadableRecords();
}

/// Append-only JSONL store (family ruling: no third-party DB — a session
/// log is an event stream with no query load; a DB brings schema migrations
/// and a platform dependency for a need nobody has measured. The Hive gotcha
/// is separately on record: wrong cipher does not throw, it silently wipes).
///
/// Constructor takes a [File] — the store is pure Dart; `path_provider`
/// belongs to the CALLER (Gravita's promotion condition #1: the measured
/// correction that unblocked two ports).
final class JsonlSessionStore implements SessionStore {
  JsonlSessionStore(this._file);

  /// Line schema THIS writer emits. v1 lines (rounds vocabulary) are still
  /// read via [SessionRecord.fromV1Json]; unknown versions are SKIPPED, not
  /// crashed on — the user may downgrade the app (forward compatibility).
  static const int schemaVersion = 2;

  final File _file;

  @override
  Future<void> append(SessionRecord record) async {
    final String line = jsonEncode(<String, dynamic>{
      'v': schemaVersion,
      ...record.toJson(),
    });

    final String existing =
        await _file.exists() ? await _file.readAsString() : '';
    final String next = existing.isEmpty ? '$line\n' : '$existing$line\n';

    // Atomic tmp+rename: a direct append killed mid-write (the OS may kill
    // a mobile app at any moment) leaves a half line that breaks the next
    // read. POSIX rename is atomic — old file or new file, nothing between.
    final File tmp = File('${_file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(next, flush: true);
    await tmp.rename(_file.path);
  }

  @override
  Future<List<SessionRecord>> recent({int? limit}) async {
    final List<SessionRecord> all = (await _readAll()).records;
    all.sort((SessionRecord a, SessionRecord b) =>
        b.completedAt.compareTo(a.completedAt));
    if (limit == null || limit >= all.length) return all;
    return all.sublist(0, limit);
  }

  @override
  Future<int> workedSecondsFor(String lessonId) async {
    int total = 0;
    for (final SessionRecord r in (await _readAll()).records) {
      if (r.lessonId == lessonId) total += r.workedSeconds;
    }
    return total;
  }

  @override
  Future<int> unreadableRecords() async => (await _readAll()).unreadable;

  Future<({List<SessionRecord> records, int unreadable})> _readAll() async {
    // MUTABLE list is mandatory: recent() sorts in place. Returning
    // `const []` broke the empty-history path — the FIRST LAUNCH — in the
    // original app (a real defect its tests caught; pinned here for good).
    if (!await _file.exists()) {
      // Missing file is EMPTY history, not lost history: nothing was ever
      // written, so nothing is unreadable. First launch must read as ok/0.
      return (records: <SessionRecord>[], unreadable: 0);
    }
    final List<SessionRecord> out = <SessionRecord>[];
    int skipped = 0;
    for (final String raw in (await _file.readAsString()).split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      // A CORRUPT LINE NEVER WIPES HISTORY: declaring months of records
      // unreadable over one bad line loses the same data twice. Skip the
      // line, read the rest.
      //
      // BUT NEVER SILENTLY (M-F-228 / JabLab J-092): skipped lines are
      // COUNTED and carried to the surface. The resilience decision is
      // right; hiding the resilience is the "you did less" lie.
      try {
        final Map<String, dynamic> j =
            (jsonDecode(line) as Map).cast<String, dynamic>();
        final int v = (j['v'] as num?)?.toInt() ?? 0;
        if (v == schemaVersion) {
          out.add(SessionRecord.fromJson(j));
        } else if (v == 1) {
          // v1 is MIGRATED, not lost — readable history is never counted
          // as unreadable (the over-strict twin: counting readable lines
          // would fabricate loss where none exists).
          out.add(SessionRecord.fromV1Json(j));
        } else {
          // Unknown version IS a loss for this reader: the line may be
          // intact, but this version cannot read it — for the user the
          // result is the same, an incomplete summary.
          skipped++;
        }
      } on Object catch (_) {
        skipped++;
      }
    }
    return (records: out, unreadable: skipped);
  }
}
