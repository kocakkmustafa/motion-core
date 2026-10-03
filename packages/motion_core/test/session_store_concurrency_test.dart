import 'dart:io';

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

SessionRecord _record(String id) => SessionRecord(
  lessonId: id,
  completedAt: DateTime.utc(2026),
  workedSeconds: 1,
  unitsCompleted: 1,
  plannedUnits: 1,
  unitLabel: 'unit',
  lessonClass: 'measurementOnly',
);

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('store_concurrency');
    file = File('${directory.path}/sessions.jsonl');
  });

  tearDown(() async => directory.delete(recursive: true));

  test('concurrent append calls preserve every record in call order', () async {
    final store = JsonlSessionStore(file);
    await Future.wait([
      for (var i = 0; i < 12; i++) store.append(_record('record-$i')),
    ]);
    expect((await store.recent()).length, 12);
    final lines = await file.readAsLines();
    for (var i = 0; i < 12; i++) {
      expect(lines[i], contains('"lessonId":"record-$i"'));
    }
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('separate handles serialize writes to the same journal path', () async {
    final first = JsonlSessionStore(file);
    final second = JsonlSessionStore(File(file.path));
    await Future.wait([
      first.append(_record('first')),
      second.append(_record('second')),
    ]);
    expect((await first.recent()).map((entry) => entry.lessonId).toSet(), {
      'first',
      'second',
    });
    expect(await first.unreadableRecords(), 0);
  });
}
