import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final beforeFirstBuild in [true, false]) {
    testWidgets(
      'retained deletion dialog survives parent removal ${beforeFirstBuild ? 'before first build' : 'after opening'}',
      (tester) async {
        final visible = ValueNotifier<bool>(true);
        final locale = ValueNotifier<Locale>(const Locale('en'));
        final account = _SignedInAccount();
        var cleanupCalls = 0;
        addTearDown(visible.dispose);
        addTearDown(locale.dispose);
        await tester.pumpWidget(
          ValueListenableBuilder<Locale>(
            valueListenable: locale,
            builder: (_, value, _) => MaterialApp(
              locale: value,
              supportedLocales: const [Locale('tr'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, show, _) => show
                    ? MotionAccountPage(
                        account: account,
                        clearLocalData: (_) async => cleanupCalls++,
                      )
                    : const Scaffold(body: Text('REPLACEMENT_PAGE')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Delete Motion account'));
        await tester.tap(find.text('Delete Motion account'));
        if (!beforeFirstBuild) await tester.pumpAndSettle();
        visible.value = false;
        await tester.pump();
        locale.value = const Locale('tr');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(account.deleted, isFalse);
        expect(cleanupCalls, 0);
        expect(find.text('REPLACEMENT_PAGE'), findsOneWidget);
      },
    );
  }

  for (final recovering in [false, true]) {
    testWidgets(
      'auth stream error keeps ${recovering ? 'recovery' : 'guest'} page usable',
      (tester) async {
        final account = _ErrorAccount();
        var cleanupCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MotionAccountPage(
              account: account,
              initialPasswordRecovery: recovering,
              clearLocalData: (_) async => cleanupCalls++,
            ),
          ),
        );
        final passwordField = find.widgetWithText(
          TextField,
          recovering ? 'New password' : 'Password',
        );
        await tester.enterText(passwordField, 'retained-password');
        account.failAuth();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Could not refresh your account. Please retry.'),
          findsOneWidget,
        );
        expect(find.textContaining('private-auth-error'), findsNothing);
        expect(
          find.text('Save password'),
          recovering ? findsOneWidget : findsNothing,
        );
        expect(find.text('Sign in'), recovering ? findsNothing : findsWidgets);
        expect(account.currentUser, isNull);
        expect(
          tester.widget<TextField>(passwordField).controller?.text,
          'retained-password',
        );
        expect(cleanupCalls, 0);

        account.recoverAuth();
        await tester.pump();
        expect(
          find.text('Could not refresh your account. Please retry.'),
          findsNothing,
        );
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        account.failAuth();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(cleanupCalls, 0);
        await account.dispose();
      },
    );
  }

  testWidgets('auth stream error rejects a pending profile result', (
    tester,
  ) async {
    final account = _SwitchableAccount();
    await tester.pumpWidget(
      MaterialApp(home: MotionAccountPage(account: account)),
    );
    account.failAuth();
    await tester.pump();
    account.finishFirstProfile();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Display name'))
          .controller
          ?.text,
      isEmpty,
    );
    expect(account.currentUser?.id, 'user-a');
    expect(account.deleteCalls, 0);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await account.dispose();
  });

  testWidgets('first release shows membership on the account page by default', (
    tester,
  ) async {
    final account = _SignedInAccount();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: MotionAccountPage(account: account),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Refresh account and membership'), findsOneWidget);
    expect(find.text('Membership options'), findsOneWidget);
    expect(find.text('No active membership in this app.'), findsOneWidget);
    expect(account.membershipChecks, 1);
  });

  testWidgets('a host without sales keeps account tools only', (tester) async {
    final account = _SignedInAccount();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: MotionAccountPage(account: account, membershipAvailable: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Refresh account'), findsOneWidget);
    expect(find.text('Membership options'), findsNothing);
    expect(find.text('No active membership in this app.'), findsNothing);
    expect(account.membershipChecks, 0);
  });

  testWidgets('Turkish sign-in can switch to sign-up without a fake paywall', (
    tester,
  ) async {
    final account = _SignedOutAccount();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccountPage(account: account),
      ),
    );

    expect(find.text('Motion hesabı'), findsOneWidget);
    expect(find.text('Giriş yap'), findsWidgets);
    expect(find.text('Yeni hesap oluştur'), findsOneWidget);
    expect(find.text('Gizlilik politikası'), findsOneWidget);
    expect(find.textContaining('Satın al'), findsNothing);
    expect(find.text('Motion hesabını sil'), findsNothing);

    await tester.tap(find.text('Yeni hesap oluştur'));
    await tester.pump();
    expect(find.text('Hesap oluştur'), findsWidgets);
    expect(find.text('Zaten hesabım var'), findsOneWidget);
  });

  testWidgets(
    'account deletion clears this app after confirmed remote deletion',
    (tester) async {
      final account = _SignedInAccount();
      String? clearedUser;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MotionAccountPage(
            account: account,
            clearLocalData: (userId) async {
              expect(account.deleted, isTrue);
              clearedUser = userId;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Delete Motion account'));
      expect(find.text('Privacy policy'), findsOneWidget);
      await tester.tap(find.text('Delete Motion account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(clearedUser, 'user-a');
      expect(account.currentUser, isNull);
    },
  );

  testWidgets('remote deletion failure keeps local history intact', (
    tester,
  ) async {
    final account = _FailingDeleteAccount();
    var localClearCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccountPage(
          account: account,
          clearLocalData: (_) async => localClearCalled = true,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(account.deleted, isFalse);
    expect(localClearCalled, isFalse);
    expect(account.currentUser?.id, 'user-a');
  });

  testWidgets('local cleanup failure follows confirmed remote deletion', (
    tester,
  ) async {
    final account = _SignedInAccount();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccountPage(
          account: account,
          clearLocalData: (_) async => throw StateError('disk error'),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(account.deleted, isTrue);
    expect(account.currentUser, isNull);
    expect(
      find.textContaining('Your Motion account was deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('a rebuilt page retains the password recovery form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccountPage(
          account: _SignedOutAccount(),
          initialPasswordRecovery: true,
        ),
      ),
    );
    expect(find.text('New password'), findsWidgets);
    expect(find.text('Save password'), findsOneWidget);
    expect(find.text('Create a new account'), findsNothing);
  });

  testWidgets('late profile response cannot overwrite another account', (
    tester,
  ) async {
    final account = _SwitchableAccount();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionAccountPage(account: account),
      ),
    );
    account.switchTo('user-b');
    await tester.pump();
    final displayName = find.widgetWithText(TextField, 'Display name');
    expect(tester.widget<TextField>(displayName).controller?.text, 'Bob');
    account.finishFirstProfile();
    await tester.pump();
    expect(tester.widget<TextField>(displayName).controller?.text, 'Bob');
    await account.dispose();
  });

  testWidgets('host recovery update opens the form on an existing page', (
    tester,
  ) async {
    final account = _SignedOutAccount();
    await tester.pumpWidget(
      MaterialApp(home: MotionAccountPage(account: account)),
    );
    expect(find.text('Save password'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: MotionAccountPage(
          account: account,
          initialPasswordRecovery: true,
        ),
      ),
    );
    expect(find.text('Save password'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: MotionAccountPage(account: account)),
    );
    expect(find.text('Save password'), findsNothing);
  });

  testWidgets('a deletion dialog cannot authorize a replacement account', (
    tester,
  ) async {
    final account = _SwitchableAccount();
    String? cleared;
    await tester.pumpWidget(
      MaterialApp(
        home: MotionAccountPage(
          account: account,
          clearLocalData: (id) async => cleared = id,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    account.switchTo('user-b');
    await tester.pump();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(account.deleteCalls, 0);
    expect(cleared, isNull);
    await account.dispose();
  });
}

class _SignedOutAccount implements MotionAccountClient {
  @override
  SupabaseClient get supabase => const _WidgetSupabase();

  @override
  MotionApp get app => MotionApp.lissom;

  @override
  String get emailRedirectTo => 'com.yulalab.lissom://auth/callback';

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get authChanges => const Stream<AuthState>.empty();

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

class _ErrorAccount extends _SignedOutAccount {
  final _changes = StreamController<AuthState>.broadcast(sync: true);

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  void failAuth() => _changes.addError(StateError('private-auth-error'));

  void recoverAuth() =>
      _changes.add(const AuthState(AuthChangeEvent.signedOut, null));

  Future<void> dispose() => _changes.close();
}

class _SignedInAccount extends _SignedOutAccount {
  User? _user = const User(
    id: 'user-a',
    appMetadata: {},
    userMetadata: null,
    aud: 'authenticated',
    createdAt: '2026-09-24T00:00:00Z',
    email: 'member@example.invalid',
  );
  bool deleted = false;
  int membershipChecks = 0;

  @override
  User? get currentUser => _user;

  @override
  Future<bool> hasActiveMembership() async {
    membershipChecks++;
    return false;
  }

  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    deleted = true;
    try {
      await afterRemoteDelete?.call(_user!.id);
    } catch (_) {
      throw const MotionLocalCleanupPending();
    } finally {
      _user = null;
    }
  }
}

class _FailingDeleteAccount extends _SignedInAccount {
  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async => throw StateError('server error');
}

class _SwitchableAccount extends _SignedOutAccount {
  final _changes = StreamController<AuthState>.broadcast();
  final _firstProfile = Completer<Map<String, dynamic>?>();
  String _id = 'user-a';
  int deleteCalls = 0;

  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    deleteCalls++;
    await afterRemoteDelete?.call(_id);
  }

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
  Future<bool> hasActiveMembership() async => false;

  @override
  Future<Map<String, dynamic>?> loadProfile() => _id == 'user-a'
      ? _firstProfile.future
      : Future.value({'display_name': 'Bob'});

  void switchTo(String id) {
    _id = id;
    _changes.add(const AuthState(AuthChangeEvent.signedIn, null));
  }

  void finishFirstProfile() {
    _firstProfile.complete({'display_name': 'Alice'});
  }

  void failAuth() => _changes.addError(StateError('private-auth-error'));

  Future<void> dispose() => _changes.close();
}
