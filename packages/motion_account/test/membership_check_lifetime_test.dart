import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// CORE-01: a membership check started by the account page must never surface
// as an uncaught error, keep a page-owned timer alive, or publish into a
// newer check or another owner's UI.
void main() {
  Widget host(MotionAccountClient account, ValueNotifier<bool> visible) =>
      MaterialApp(
        locale: const Locale('en'),
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, show, _) => show
              ? MotionAccountPage(account: account, membershipAvailable: true)
              : const Scaffold(body: Text('REPLACEMENT_PAGE')),
        ),
      );

  Future<void> tapRefresh(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Refresh account and membership'));
    await tester.tap(find.text('Refresh account and membership'));
    await tester.pump();
  }

  testWidgets('a never-answering check is dropped when the page closes', (
    tester,
  ) async {
    final account = _ScriptedAccount();
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(host(account, visible));
    await tester.pump();
    expect(find.text('Checking membership…'), findsOneWidget);

    await tapRefresh(tester);
    expect(account.checks.length, 2);
    visible.value = false;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('REPLACEMENT_PAGE'), findsOneWidget);
  });

  for (final closeFirst in [true, false]) {
    testWidgets(
      'a late check error ${closeFirst ? 'after close' : 'on a superseded check'} is not uncaught',
      (tester) async {
        final account = _ScriptedAccount(
          answer: (index) => index == 0
              ? Future<bool>.delayed(
                  const Duration(seconds: 3),
                  () => throw StateError('private-membership-error'),
                )
              : Future<bool>.value(true),
        );
        final visible = ValueNotifier<bool>(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(host(account, visible));
        await tester.pump();

        if (closeFirst) {
          visible.value = false;
          await tester.pump();
        } else {
          await tapRefresh(tester);
          await tester.pump();
          expect(find.text('Membership active in this app.'), findsOneWidget);
        }
        // Let the first check's delayed error fire: no pending timer remains
        // at test end and the error is observed, not thrown into the zone.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        if (closeFirst) {
          expect(find.text('REPLACEMENT_PAGE'), findsOneWidget);
        } else {
          expect(find.text('Membership active in this app.'), findsOneWidget);
          expect(find.text('Membership unavailable.'), findsNothing);
        }
      },
    );
  }

  testWidgets('the current check error still shows as unavailable', (
    tester,
  ) async {
    final account = _ScriptedAccount(
      answer: (_) => Future<bool>.error(StateError('private-membership-error')),
    );
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(host(account, visible));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Membership unavailable.'), findsOneWidget);
  });

  testWidgets('an old owner answer does not reach the new owner', (
    tester,
  ) async {
    final first = Completer<bool>();
    final account = _ScriptedAccount(
      answer: (index) => index == 0 ? first.future : Future<bool>.value(false),
    );
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    addTearDown(account.dispose);
    await tester.pumpWidget(host(account, visible));
    await tester.pump();

    account.switchTo('user-b');
    await tester.pumpAndSettle();
    expect(find.text('No active membership in this app.'), findsOneWidget);

    first.complete(true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No active membership in this app.'), findsOneWidget);
    expect(find.text('Membership active in this app.'), findsNothing);
  });

  testWidgets('a check answered after the owner changes is not published', (
    tester,
  ) async {
    // The owner changes before the auth event arrives: the page has not yet
    // started a new check, and the old owner's answer must stay unpublished.
    final first = Completer<bool>();
    final account = _ScriptedAccount(
      answer: (index) => index == 0 ? first.future : Future<bool>.value(false),
    );
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    addTearDown(account.dispose);
    await tester.pumpWidget(host(account, visible));
    await tester.pump();

    account.switchTo('user-b', announce: false);
    first.complete(true);
    await tester.pump();
    expect(find.text('Membership active in this app.'), findsNothing);

    account.announce();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No active membership in this app.'), findsOneWidget);
  });
}

class _ScriptedAccount implements MotionAccountClient {
  _ScriptedAccount({Future<bool> Function(int index)? answer})
    : _answer = answer ?? ((_) => Completer<bool>().future);

  final Future<bool> Function(int index) _answer;
  final _changes = StreamController<AuthState>.broadcast();
  final checks = <String>[];
  String _id = 'user-a';

  @override
  SupabaseClient get supabase => const _WidgetSupabase();

  @override
  MotionApp get app => MotionApp.lissom;

  @override
  String get emailRedirectTo => 'com.yulalab.lissom://auth/callback';

  @override
  User? get currentUser => User(
    id: _id,
    appMetadata: const {},
    userMetadata: null,
    aud: 'authenticated',
    createdAt: '2026-09-24T00:00:00Z',
    email: '$_id@example.invalid',
  );

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<bool> hasActiveMembership() {
    checks.add(_id);
    return _answer(checks.length - 1);
  }

  @override
  Future<Map<String, dynamic>?> loadProfile() async => null;

  void switchTo(String id, {bool announce = true}) {
    _id = id;
    if (announce) this.announce();
  }

  void announce() =>
      _changes.add(const AuthState(AuthChangeEvent.signedIn, null));

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetSupabase implements SupabaseClient {
  const _WidgetSupabase();

  @override
  GoTrueClient get auth => const _WidgetAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WidgetAuth implements GoTrueClient {
  const _WidgetAuth();

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
