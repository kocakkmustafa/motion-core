// OST-T3-J01 closure: a late same-owner profile GET never replaces the user's
// draft, across save, auth-stream error and A→B→A owner changes. Every case
// ends with an explicit receipt of the visible draft and every dispatched save.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _requestFailed =
    'Could not complete the request. Check your details and connection, then retry.';
const _refreshFailed = 'Could not refresh your account. Please retry.';

void main() {
  testWidgets('delayed GET + edit + save: late old name after save success '
      'keeps the saved draft', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    final firstRead = account.reads.single;

    await tester.enterText(_field, 'New name');
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    account.saves.single.complete();
    await tester.pump();
    expect(find.text('Profile saved.'), findsOneWidget);

    firstRead.complete('Old server name');
    await tester.pump();
    expect(_draft(tester), 'New name');

    // A same-owner reload (userUpdated) after the save still keeps intent.
    account.emit(AuthChangeEvent.userUpdated);
    await tester.pump();
    account.reads.last.complete('Old server name');
    await tester.pump();

    expect(_draft(tester), 'New name');
    expect(account.saves.map((s) => s.receipt), ['user-a:New name']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delayed GET + save in flight: late GET then save failure keeps '
      'the draft saveable without replay', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    await tester.enterText(_field, 'Draft during read');
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();

    account.reads.single.complete('Server name');
    await tester.pump();
    expect(_draft(tester), 'Draft during read');
    account.saves.single.fail();
    await tester.pump();

    expect(find.text(_requestFailed), findsOneWidget);
    expect(_draft(tester), 'Draft during read');
    expect(_save(tester).onPressed, isNotNull);
    expect(account.saves.map((s) => s.receipt), ['user-a:Draft during read']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth-stream error during a delayed GET: draft kept, late GET '
      'rejected, explicit save goes to the same owner', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    await tester.enterText(_field, 'Kept through error');
    await tester.pump();

    account.fail();
    await tester.pump();
    expect(find.text(_refreshFailed), findsOneWidget);
    account.reads.single.complete('Server after error');
    await tester.pump();
    expect(_draft(tester), 'Kept through error');

    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    account.saves.single.complete();
    await tester.pump();
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(_draft(tester), 'Kept through error');
    expect(account.saves.map((s) => s.receipt), ['user-a:Kept through error']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth-stream error with an untouched field does not authorise '
      'saving an unobserved blank name', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    account.fail();
    await tester.pump();
    account.reads.single.complete('Server after error');
    await tester.pump();
    expect(_draft(tester), isEmpty);
    expect(_save(tester).onPressed, isNull);
    expect(account.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A→B→A: no stale read or save from an earlier lifetime reaches '
      'the returning owner', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    final aFirstRead = account.reads.single;
    await tester.enterText(_field, 'A first draft');
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    final aFirstSave = account.saves.single;

    account.switchTo('user-b');
    await tester.pump();
    final bRead = account.reads.last;
    expect(bRead.userId, 'user-b');
    expect(_draft(tester), isEmpty);

    account.switchTo('user-a');
    await tester.pump();
    final aSecondRead = account.reads.last;
    expect(aSecondRead.userId, 'user-a');
    expect(account.reads, hasLength(3));
    expect(_draft(tester), isEmpty); // owner change starts a clean field

    // Earlier lifetimes finish late, in the worst order.
    bRead.complete('Bob server');
    aFirstRead.complete('A stale server');
    aFirstSave.complete();
    await tester.pump();
    expect(_draft(tester), isEmpty);
    expect(find.text('Bob server'), findsNothing);
    expect(find.text('Profile saved.'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    aSecondRead.complete('A current server');
    await tester.pump();
    expect(_draft(tester), 'A current server');

    await tester.enterText(_field, 'A second draft');
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    account.saves.last.complete();
    await tester.pump();
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(_draft(tester), 'A second draft');
    expect(account.saves.map((s) => s.receipt), [
      'user-a:A first draft',
      'user-a:A second draft',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A→B→A: a retained first-lifetime A save callback cannot '
      'dispatch into the returning A form', (tester) async {
    final account = _Account();
    await _pump(tester, account);
    account.reads.single.complete('A server');
    await tester.pump();
    await tester.enterText(_field, 'A edited');
    await tester.pump();
    final retained = _save(tester).onPressed!;

    account.switchTo('user-b');
    await tester.pump();
    account.reads.last.complete('Bob server');
    await tester.pump();
    account.switchTo('user-a');
    await tester.pump();
    account.reads.last.complete('A server');
    await tester.pump();

    // Same UUID again: the closure's captured owner matches, so dispatch is
    // allowed, but it must carry the *current* field value, never a stale one.
    retained();
    await tester.pump();
    expect(account.saves.map((s) => s.receipt), ['user-a:A server']);
    expect(_draft(tester), 'A server');
    expect(tester.takeException(), isNull);
  });
}

Finder get _field => find.widgetWithText(TextField, 'Display name');

String _draft(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

FilledButton _save(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Save profile'),
);

Future<void> _pump(WidgetTester tester, _Account account) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await account.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: MotionAccountPage(account: account, membershipAvailable: false),
    ),
  );
}

class _Account implements MotionAccountClient {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  final reads = <_Read>[];
  final saves = <_Save>[];
  String _userId = 'user-a';

  @override
  SupabaseClient get supabase => const _Supabase();

  @override
  MotionApp get app => MotionApp.ostinato;

  @override
  String get emailRedirectTo => 'com.yulalab.ostinato://auth/callback';

  @override
  User? get currentUser => User(
    id: _userId,
    appMetadata: const {},
    userMetadata: null,
    aud: 'authenticated',
    createdAt: '2026-10-21T00:00:00Z',
    email: '$_userId@example.invalid',
  );

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<Map<String, dynamic>?> loadProfile() {
    final read = _Read(_userId);
    reads.add(read);
    return read.result.future;
  }

  @override
  Future<void> saveDisplayName(String name) {
    final save = _Save('$_userId:$name');
    saves.add(save);
    return save.result.future;
  }

  void emit(AuthChangeEvent event) => _changes.add(AuthState(event, null));

  void fail() => _changes.addError(StateError('synthetic stream error'));

  void switchTo(String userId) {
    _userId = userId;
    emit(AuthChangeEvent.signedIn);
  }

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Read {
  _Read(this.userId);
  final String userId;
  final result = Completer<Map<String, dynamic>?>();
  void complete(String name) =>
      result.complete({'user_id': userId, 'display_name': name});
}

class _Save {
  _Save(this.receipt);
  final String receipt;
  final result = Completer<void>();
  void complete() => result.complete();
  void fail() => result.completeError(StateError('synthetic save failure'));
}

class _Supabase implements SupabaseClient {
  const _Supabase();

  @override
  GoTrueClient get auth => const _Auth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements GoTrueClient {
  const _Auth();

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
