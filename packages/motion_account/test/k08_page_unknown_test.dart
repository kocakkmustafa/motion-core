// K08 page closure tests (T07/T08/T09/T10/T12): unknown outcomes stay visible,
// block a second dispatch until acknowledged, and never publish across owners.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _operationUnknown =
    "The server didn't answer in time, so we can't tell whether this went through. Check your connection before trying again.";
const _emailUnknown =
    "We couldn't confirm the request. An email may still arrive, so check your inbox and spam folder before asking for another.";
const _deletionUnknown =
    "We couldn't confirm whether your Motion account was deleted. History on this device was kept. Open the app online later to check again.";
const _saveUnknown =
    "We couldn't confirm the save, and the profile couldn't be checked. Your entry is kept.";
const _saveMatches = 'Your profile now shows the name you entered.';
const _saveDiffers =
    'Your profile shows a different name. Your entry is kept; save again to use it.';
const _signedOutOnDevice =
    "Signed out on this device. The server couldn't be reached to end the session there too.";

void main() {
  testWidgets('T07 unknown sign-in blocks re-dispatch until OK', (
    tester,
  ) async {
    final account = _FakeAccount(userId: null);
    await _pump(tester, account);
    await _enterCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(account.signIns, 1);
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.signIn),
    );
    await tester.pump();

    expect(find.text(_operationUnknown), findsOneWidget);
    expect(_button(tester, 'Sign in').onPressed, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(account.signIns, 1);

    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text(_operationUnknown), findsNothing);
    expect(_button(tester, 'Sign in').onPressed, isNotNull);
    expect(account.signIns, 1); // nothing was retried automatically
    expect(tester.takeException(), isNull);
  });

  testWidgets('T12 a late sign-in Session replaces the unknown outcome', (
    tester,
  ) async {
    final account = _FakeAccount(userId: null);
    await _pump(tester, account);
    await _enterCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.signIn),
    );
    await tester.pump();
    expect(find.text(_operationUnknown), findsOneWidget);

    account.switchTo('user-a'); // the delayed reply published a Session
    await tester.pump();
    expect(find.text(_operationUnknown), findsNothing);
    expect(find.text('OK'), findsNothing);
    expect(find.text('user-a@example.invalid'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T12 unknown for an owner that already changed is not shown', (
    tester,
  ) async {
    final account = _FakeAccount(userId: 'user-a');
    await _pump(tester, account);
    account.reads.single.complete({'display_name': 'A'});
    await tester.pump();
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();
    expect(account.deletions, 1);

    account.switchTo('user-b');
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.deleteAccount),
    );
    await tester.pump();
    expect(find.text(_deletionUnknown), findsNothing);
    expect(find.text('OK'), findsNothing);
    expect(account.cleared, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T08 unknown reset mail explains a possible delivery', (
    tester,
  ) async {
    final account = _FakeAccount(userId: null);
    await _pump(tester, account);
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'n@example.invalid',
    );
    await tester.pump(); // the typed address enables the mail request
    await tester.tap(find.text('Forgot password'));
    await tester.pump();
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.passwordReset),
    );
    await tester.pump();
    expect(find.text(_emailUnknown), findsOneWidget);
    expect(_textButton(tester, 'Forgot password').onPressed, isNull);
    expect(account.resets, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mail requests stay closed until the field holds an address', (
    tester,
  ) async {
    final account = _FakeAccount(userId: null);
    await _pump(tester, account);
    final email = find.widgetWithText(TextField, 'Email');
    expect(_textButton(tester, 'Forgot password').onPressed, isNull);
    await tester.tap(find.text('Forgot password'));
    await tester.pump();
    expect(account.resets, 0);
    for (final partial in ['n', 'n@', 'n@example', ' n @example.invalid']) {
      await tester.enterText(email, partial);
      await tester.pump();
      expect(
        _textButton(tester, 'Forgot password').onPressed,
        isNull,
        reason: partial,
      );
    }
    await tester.enterText(email, ' n@example.invalid ');
    await tester.pump();
    expect(_textButton(tester, 'Forgot password').onPressed, isNotNull);

    await tester.tap(find.text('Create a new account'));
    await tester.pump();
    await tester.enterText(email, '');
    await tester.pump();
    final resend = find.widgetWithText(TextButton, 'Resend verification email');
    await tester.ensureVisible(resend);
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.enterText(email, 'n@example.invalid');
    await tester.pump();
    expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
    await tester.tap(resend);
    await tester.pump();
    expect(account.resends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T10 unknown deletion keeps local data and needs OK', (
    tester,
  ) async {
    final account = _FakeAccount(userId: 'user-a');
    await _pump(tester, account);
    account.reads.single.complete({'display_name': 'A'});
    await tester.pump();
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.deleteAccount),
    );
    await tester.pump();
    expect(find.text(_deletionUnknown), findsOneWidget);
    expect(account.cleared, isEmpty);
    expect(_textButton(tester, 'Delete Motion account').onPressed, isNull);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(_textButton(tester, 'Delete Motion account').onPressed, isNotNull);
    expect(account.deletions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T11 signed out locally with unconfirmed revoke is explained', (
    tester,
  ) async {
    final account = _FakeAccount(userId: 'user-a');
    await _pump(tester, account);
    account.reads.single.complete({'display_name': 'A'});
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    account.switchTo(null); // the SDK discarded the Session before logout
    account.pending.single.completeError(
      const MotionOperationUnknown(MotionAccountOperation.signOut),
    );
    await tester.pump();
    expect(find.text(_signedOutOnDevice), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('T09 unknown profile save reads back without replay', () {
    Future<_FakeAccount> unknownSave(WidgetTester tester) async {
      final account = _FakeAccount(userId: 'user-a');
      await _pump(tester, account);
      account.reads.single.complete({'display_name': 'Old'});
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Display name'),
        '  New name ',
      );
      await tester.pump();
      await tester.tap(find.text('Save profile'));
      await tester.pump();
      expect(account.saves, ['  New name ']);
      account.pending.single.completeError(
        const MotionOperationUnknown(MotionAccountOperation.saveProfile),
      );
      await tester.pump();
      expect(account.reads, hasLength(2)); // one bounded readback
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      return account;
    }

    testWidgets('equal current name', (tester) async {
      final account = await unknownSave(tester);
      account.reads.last.complete({'display_name': 'New name'});
      await tester.pump();
      expect(find.text(_saveMatches), findsOneWidget);
      expect(_displayName(tester), '  New name ');
      expect(_button(tester, 'Save profile').onPressed, isNotNull);
      expect(account.saves, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('different current name keeps the draft', (tester) async {
      final account = await unknownSave(tester);
      account.reads.last.complete({'display_name': 'Other device'});
      await tester.pump();
      expect(find.text(_saveDiffers), findsOneWidget);
      expect(_displayName(tester), '  New name ');
      expect(account.saves, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('unavailable readback stays unknown until OK', (tester) async {
      final account = await unknownSave(tester);
      account.reads.last.completeError(StateError('offline'));
      await tester.pump();
      expect(find.text(_saveUnknown), findsOneWidget);
      expect(_displayName(tester), '  New name ');
      expect(_button(tester, 'Save profile').onPressed, isNull);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(_button(tester, 'Save profile').onPressed, isNotNull);
      expect(account.saves, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('stalled readback ends at the read budget', (tester) async {
      final account = await unknownSave(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text(_saveUnknown), findsOneWidget);
      account.reads.last.complete({'display_name': 'Too late'});
      await tester.pump();
      expect(find.text(_saveMatches), findsNothing);
      expect(find.text(_saveDiffers), findsNothing);
      expect(_displayName(tester), '  New name ');
      expect(tester.takeException(), isNull);
    });

    testWidgets('owner change during readback publishes nothing', (
      tester,
    ) async {
      final account = await unknownSave(tester);
      account.switchTo('user-b');
      await tester.pump();
      account.reads[1].complete({'display_name': 'New name'});
      await tester.pump();
      expect(find.text(_saveMatches), findsNothing);
      expect(find.text(_saveUnknown), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pump(WidgetTester tester, _FakeAccount account) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await account.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      home: MotionAccountPage(
        account: account,
        membershipAvailable: false,
        clearLocalData: (id) async => account.cleared.add(id),
      ),
    ),
  );
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Email'),
    'a@example.invalid',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Password'),
    'secret-pass',
  );
  await tester.pump();
}

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

TextButton _textButton(WidgetTester tester, String label) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, label));

String _displayName(WidgetTester tester) => tester
    .widget<TextField>(find.widgetWithText(TextField, 'Display name'))
    .controller!
    .text;

class _FakeAccount implements MotionAccountClient {
  _FakeAccount({required String? userId}) : _userId = userId;

  final _changes = StreamController<AuthState>.broadcast(sync: true);
  final pending = <Completer<void>>[];
  final reads = <Completer<Map<String, dynamic>?>>[];
  final saves = <String>[];
  final cleared = <String>[];
  var signIns = 0;
  var resets = 0;
  var resends = 0;
  var deletions = 0;
  String? _userId;

  Future<T> _hold<T>(T value) {
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future.then((_) => value);
  }

  @override
  SupabaseClient get supabase => const _FakeSupabase();

  @override
  MotionApp get app => MotionApp.ostinato;

  @override
  String get emailRedirectTo => 'com.yulalab.ostinato://auth/callback';

  @override
  User? get currentUser => _userId == null
      ? null
      : User(
          id: _userId!,
          appMetadata: const {},
          userMetadata: null,
          aud: 'authenticated',
          createdAt: '2026-10-21T00:00:00Z',
          email: '$_userId@example.invalid',
        );

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    signIns++;
    return _hold(AuthResponse());
  }

  @override
  Future<void> sendPasswordReset(String email) {
    resets++;
    return _hold(null);
  }

  @override
  Future<void> resendConfirmation(String email) {
    resends++;
    return _hold(null);
  }

  @override
  Future<void> signOut() => _hold(null);

  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) {
    deletions++;
    return _hold(null);
  }

  @override
  Future<Map<String, dynamic>?> loadProfile() {
    final read = Completer<Map<String, dynamic>?>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> saveDisplayName(String name) {
    saves.add(name);
    return _hold(null);
  }

  void switchTo(String? userId) {
    _userId = userId;
    _changes.add(
      AuthState(
        userId == null ? AuthChangeEvent.signedOut : AuthChangeEvent.signedIn,
        null,
      ),
    );
  }

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupabase implements SupabaseClient {
  const _FakeSupabase();

  @override
  GoTrueClient get auth => const _FakeAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements GoTrueClient {
  const _FakeAuth();

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
