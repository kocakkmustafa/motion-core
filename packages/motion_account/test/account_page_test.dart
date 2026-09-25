import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('first release keeps account tools without subscription sales', (
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
}

class _SignedOutAccount implements MotionAccountClient {
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

  Future<void> dispose() => _changes.close();
}
