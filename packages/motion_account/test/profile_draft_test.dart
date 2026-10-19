import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('an untouched draft receives the delayed profile name', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    expect(_displayName(tester), isEmpty);
    expect(account.profileReads.single.userId, 'user-a');
    account.profileReads.single.complete('Alice from server');
    await tester.pump();

    expect(_displayName(tester), 'Alice from server');
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late profile read cannot replace an edited draft', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    await tester.enterText(_displayNameField, 'My draft');
    account.profileReads.single.complete('Old server name');
    await tester.pump();

    expect(_displayName(tester), 'My draft');
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing an edited draft still rejects a late profile read', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    await tester.enterText(_displayNameField, 'Temporary draft');
    await tester.enterText(_displayNameField, '');
    account.profileReads.single.complete('Old server name');
    await tester.pump();

    expect(_displayName(tester), isEmpty);
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a draft keeps its payload and UI during a late read', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    await tester.enterText(_displayNameField, 'Saved draft');
    await tester.tap(find.text('Save profile'));
    await tester.pump();

    final save = account.profileSaves.single;
    expect(save.userId, 'user-a');
    expect(save.displayName, 'Saved draft');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    account.profileReads.single.complete('Old server name');
    await tester.pump();
    expect(_displayName(tester), 'Saved draft');
    expect(save.displayName, 'Saved draft');
    expect(account.profileSaves, hasLength(1));

    save.complete();
    await tester.pump();
    expect(_displayName(tester), 'Saved draft');
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an untouched empty field invalidates the pending read', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    // No enterText: Save itself must express intent before the initial GET.
    await tester.tap(find.text('Save profile'));
    await tester.pump();

    final save = account.profileSaves.single;
    expect(save.userId, 'user-a');
    expect(save.displayName, isEmpty);

    account.profileReads.single.complete('Old server name');
    await tester.pump();
    expect(_displayName(tester), isEmpty);
    expect(save.displayName, isEmpty);
    expect(account.profileSaves, hasLength(1));

    save.complete();
    await tester.pump();
    expect(_displayName(tester), isEmpty);
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a same-owner auth reload after a read error preserves a draft', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    account.profileReads.single.fail();
    await tester.pump();
    expect(_displayName(tester), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.enterText(_displayNameField, 'Offline draft');
    account.notifyUserUpdated();
    await tester.pump();

    expect(account.profileReads, hasLength(2));
    expect(account.profileReads.last.userId, 'user-a');
    expect(_displayName(tester), 'Offline draft');

    account.profileReads.last.complete('Server retry name');
    await tester.pump();
    expect(_displayName(tester), 'Offline draft');
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching owners clears a dirty draft and rejects the old read', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    final firstRead = account.profileReads.single;
    await tester.enterText(_displayNameField, 'Alice draft');
    account.switchTo('user-b');
    await tester.pump();

    expect(account.profileReads, hasLength(2));
    expect(account.profileReads.last.userId, 'user-b');
    // B is still loading: A's draft must already have disappeared.
    expect(_displayName(tester), isEmpty);

    account.profileReads.last.complete('Bob from server');
    await tester.pump();
    // B's read must be allowed, so A's dirty flag must also have reset.
    expect(_displayName(tester), 'Bob from server');

    firstRead.complete('Alice from server');
    await tester.pump();
    expect(account.currentUser?.id, 'user-b');
    expect(_displayName(tester), 'Bob from server');
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a profile read finishing after disposal cannot publish a name', (
    tester,
  ) async {
    final account = _DelayedProfileAccount();
    await _pumpAccount(tester, account);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('REPLACEMENT_PAGE'))),
    );
    account.profileReads.single.complete('Late server name');
    await tester.pump();

    expect(find.text('REPLACEMENT_PAGE'), findsOneWidget);
    expect(find.byType(MotionAccountPage), findsNothing);
    expect(find.text('Late server name'), findsNothing);
    expect(account.profileSaves, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Finder get _displayNameField => find.widgetWithText(TextField, 'Display name');

String _displayName(WidgetTester tester) =>
    tester.widget<TextField>(_displayNameField).controller!.text;

Future<void> _pumpAccount(
  WidgetTester tester,
  _DelayedProfileAccount account,
) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await account.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: MotionAccountPage(
        account: account,
        paidFeaturesAvailable: false,
      ),
    ),
  );
  expect(account.profileReads, hasLength(1));
}

class _DelayedProfileAccount implements MotionAccountClient {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  final profileReads = <_ProfileRead>[];
  final profileSaves = <_ProfileSave>[];
  String _userId = 'user-a';

  @override
  SupabaseClient get supabase => const _ProfileSupabase();

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
    createdAt: '2026-10-19T00:00:00Z',
    email: '$_userId@example.invalid',
  );

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<Map<String, dynamic>?> loadProfile() {
    final read = _ProfileRead(_userId);
    profileReads.add(read);
    return read.result.future;
  }

  @override
  Future<void> saveDisplayName(String name) {
    final save = _ProfileSave(userId: _userId, displayName: name);
    profileSaves.add(save);
    return save.result.future;
  }

  void notifyUserUpdated() {
    _changes.add(const AuthState(AuthChangeEvent.userUpdated, null));
  }

  void switchTo(String userId) {
    _userId = userId;
    _changes.add(const AuthState(AuthChangeEvent.signedIn, null));
  }

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRead {
  _ProfileRead(this.userId);

  final String userId;
  final result = Completer<Map<String, dynamic>?>();

  void complete(String name) {
    result.complete({'user_id': userId, 'display_name': name});
  }

  void fail() {
    result.completeError(StateError('Profile unavailable'));
  }
}

class _ProfileSave {
  _ProfileSave({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
  final result = Completer<void>();

  void complete() => result.complete();
}

class _ProfileSupabase implements SupabaseClient {
  const _ProfileSupabase();

  @override
  GoTrueClient get auth => const _ProfileAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileAuth implements GoTrueClient {
  const _ProfileAuth();

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
