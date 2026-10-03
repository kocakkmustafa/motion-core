import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:motion_core/motion_core.dart';
import 'package:test/test.dart';

SessionRecord _record() => SessionRecord(
  lessonId: 'test',
  completedAt: DateTime.utc(2026),
  workedSeconds: 1,
  unitsCompleted: 1,
  plannedUnits: 1,
  unitLabel: 'unit',
  lessonClass: 'measurementOnly',
);

class _GatedFile implements File {
  _GatedFile(this.file, {this.gateExists = false, this.gateRead = false});

  final File file;
  final bool gateExists;
  final bool gateRead;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  String get path => file.path;

  @override
  File get absolute => file.absolute;

  Future<void> _gate() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  @override
  Future<bool> exists() async {
    if (gateExists) await _gate();
    return file.exists();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    if (gateRead) await _gate();
    return file.readAsString(encoding: encoding);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unsupported filesystem operation in test');
}

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('store_lifetime');
    file = File('${directory.path}/sessions.jsonl');
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'retirement invalidates access synchronously without deleting data',
    () async {
      final store = JsonlSessionStore(file);
      await store.append(_record());
      final retirement = store.retireAndDrain();
      expect(store.writeLease.isActive, isFalse);
      await expectLater(
        store.append(_record()),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      await expectLater(
        store.recent(),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      await expectLater(
        store.workedSecondsFor('test'),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      await expectLater(
        store.unreadableRecords(),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      await retirement;
      expect(await file.exists(), isTrue);
    },
  );

  test('retired retained handle cannot recreate an erased journal', () async {
    final store = JsonlSessionStore(file);
    await store.append(_record());
    await store.retireAndDrain();
    await file.delete();
    await expectLater(
      store.append(_record()),
      throwsA(isA<SessionStoreRetiredException>()),
    );
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('retirement waits for a held write before allowing erasure', () async {
    final gated = _GatedFile(file, gateExists: true);
    final store = JsonlSessionStore(gated);
    final write = store.append(_record());
    final rejected = expectLater(
      write,
      throwsA(isA<SessionStoreRetiredException>()),
    );
    await gated.entered.future;
    var drained = false;
    final retirement = store.retireAndDrain().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    gated.release.complete();
    await rejected;
    await retirement;
    expect(drained, isTrue);
    expect(await file.exists(), isFalse);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('a held read never publishes history after owner retirement', () async {
    await JsonlSessionStore(file).append(_record());
    final gated = _GatedFile(file, gateRead: true);
    final store = JsonlSessionStore(gated);
    final rejected = expectLater(
      store.recent(),
      throwsA(isA<SessionStoreRetiredException>()),
    );
    await gated.entered.future;
    final retirement = store.retireAndDrain();
    gated.release.complete();
    await rejected;
    await retirement;
    expect(await file.exists(), isTrue);
  });

  test(
    'one owner lease retires all handles while a fresh owner can reopen',
    () async {
      final lease = SessionStoreWriteLease();
      final first = JsonlSessionStore(file, writeLease: lease);
      final second = JsonlSessionStore(file, writeLease: lease);
      await first.append(_record());
      await lease.retireAndDrain();
      await expectLater(
        second.append(_record()),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      await expectLater(
        second.recent(),
        throwsA(isA<SessionStoreRetiredException>()),
      );
      final reopened = JsonlSessionStore(
        file,
        writeLease: SessionStoreWriteLease(),
      );
      expect((await reopened.recent()).length, 1);
    },
  );

  test('failed filesystem write does not poison the path queue', () async {
    await Directory(file.path).create();
    final store = JsonlSessionStore(file);
    await expectLater(
      store.append(_record()),
      throwsA(isA<FileSystemException>()),
    );
    await Directory(file.path).delete();
    await store.append(_record());
    expect((await store.recent()).length, 1);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });
}
