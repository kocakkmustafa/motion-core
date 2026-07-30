import 'dart:io';

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

SessionRecord rec(
  String lesson, {
  DateTime? at,
  int worked = 300,
  int units = 3,
  int planned = 5,
  String label = 'rep',
  String cls = 'measurementOnly',
  int unmeasured = 0,
  String? why,
}) =>
    SessionRecord(
      lessonId: lesson,
      completedAt: at ?? DateTime.utc(2026, 7, 30, 3),
      workedSeconds: worked,
      unitsCompleted: units,
      plannedUnits: planned,
      unitLabel: label,
      lessonClass: cls,
      unmeasuredUnits: unmeasured,
      unmeasuredReason: why,
    );

void main() {
  late Directory dir;
  late File file;
  late JsonlSessionStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('session_store_test');
    file = File('${dir.path}/sessions.jsonl');
    store = JsonlSessionStore(file);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('record semantics (M-F-193)', () {
    test('completion counts ATTEMPTS — an unmeasurable unit never lowers '
        'progress', () {
      final SessionRecord r =
          rec('squat', units: 4, planned: 5, unmeasured: 1, why: 'framing');
      expect(r.attemptedUnits, 5);
      expect(r.isComplete, isTrue,
          reason: 'the user did 5 units of work; one going unjudged is a '
              'measurement fact, not a progress penalty');
    });

    test('least-privilege class read: only the shared value scores', () {
      expect(rec('a', cls: 'scored').isScoredClass, isTrue);
      for (final String c in <String>['demoOnly', 'measurementOnly', '', 'x']) {
        expect(rec('a', cls: c).isScoredClass, isFalse,
            reason: 'unknown or app-specific class must never read as '
                'scored — when in doubt, claim less');
      }
    });

    test('unmeasured fields stay off the wire when empty', () {
      expect(rec('a').toJson().containsKey('unmeasuredUnits'), isFalse);
      expect(rec('a', unmeasured: 2, why: 'light').toJson(),
          containsPair('unmeasuredUnits', 2));
    });
  });

  group('JsonlSessionStore invariants (J-064 carried)', () {
    test('missing file is empty history, not an error — first launch', () async {
      expect(await store.recent(), isEmpty);
      expect(await store.workedSecondsFor('any'), 0);
    });

    test('append/read round-trip, newest first, limit honored', () async {
      await store.append(rec('a', at: DateTime.utc(2026, 7, 30, 1)));
      await store.append(rec('b', at: DateTime.utc(2026, 7, 30, 2)));
      await store.append(rec('c', at: DateTime.utc(2026, 7, 30, 3)));
      final List<SessionRecord> two = await store.recent(limit: 2);
      expect(two.map((SessionRecord r) => r.lessonId), <String>['c', 'b']);
    });

    test('a corrupt line never wipes history', () async {
      await store.append(rec('keep1'));
      await file.writeAsString('${file.readAsStringSync()}{broken json\n');
      await store.append(rec('keep2'));
      expect((await store.recent()).length, 2);
    });

    test('a half-written last line does not take the rest down', () async {
      await store.append(rec('keep'));
      await file.writeAsString(
          '${file.readAsStringSync()}{"v":2,"lessonId":"tr', flush: true);
      expect((await store.recent()).single.lessonId, 'keep');
    });

    test('unknown schema version is skipped, never crashed on', () async {
      await store.append(rec('now'));
      await file.writeAsString(
          '${file.readAsStringSync()}{"v":99,"future":"field"}\n');
      expect((await store.recent()).single.lessonId, 'now');
    });

    test('v1 legacy lines read with rounds vocabulary and unscored class',
        () async {
      const String v1 = '{"v":1,"lessonId":"r3","completedAt":'
          '"2026-07-29T20:00:00.000Z","workedSeconds":540,'
          '"roundsCompleted":3,"plannedRounds":3}';
      await file.writeAsString('$v1\n');
      final SessionRecord r = (await store.recent()).single;
      expect(r.unitsCompleted, 3);
      expect(r.unitLabel, 'round');
      expect(r.isComplete, isTrue);
      expect(r.isScoredClass, isFalse,
          reason: 'v1 surfaces showed facts, never marks — least-privilege '
              'keeps that true retroactively');
    });

    test('workedSecondsFor sums one lesson only', () async {
      await store.append(rec('a', worked: 100));
      await store.append(rec('b', worked: 999));
      await store.append(rec('a', worked: 50, at: DateTime.utc(2026, 7, 31)));
      expect(await store.workedSecondsFor('a'), 150);
    });

    test('no .tmp file leaks after append', () async {
      await store.append(rec('a'));
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('per-record unit labels coexist in one file — the Gravita case',
        () async {
      await store.append(rec('push_up', label: 'rep', units: 3, planned: 5));
      await store.append(rec('plank',
          label: 'second', units: 45, planned: 60, worked: 45,
          at: DateTime.utc(2026, 7, 30, 4)));
      final List<SessionRecord> all = await store.recent();
      expect(all.map((SessionRecord r) => r.unitLabel).toSet(),
          <String>{'rep', 'second'});
      // The documented degeneration (arbitration §5): second-unit records
      // duplicate workedSeconds — accepted, and visible for surfaces to
      // avoid presenting as two facts.
      final SessionRecord plank =
          all.firstWhere((SessionRecord r) => r.lessonId == 'plank');
      expect(plank.unitsCompleted, plank.workedSeconds);
    });
  });
}
