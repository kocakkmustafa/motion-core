import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '00000000-0000-4000-8000-000000000001';
const _bob = '00000000-0000-4000-8000-000000000002';

String _session(String userId, {String token = 'alice-session'}) => jsonEncode({
  'access_token': token,
  'token_type': 'bearer',
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'created_at': '2026-09-24T00:00:00Z',
    'app_metadata': <String, dynamic>{},
  },
});

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _user(String id) => _json({
  'id': id,
  'aud': 'authenticated',
  'created_at': '2026-09-24T00:00:00Z',
  'app_metadata': <String, dynamic>{},
});

SupabaseClient _client(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );

MotionAccountClient _account(SupabaseClient client) => MotionAccountClient(
  supabase: client,
  app: MotionApp.ostinato,
  emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
);

class _DialogAccount extends MotionAccountClient {
  _DialogAccount(SupabaseClient client)
    : super(
        supabase: client,
        app: MotionApp.ostinato,
        emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
      );

  var deletionDispatches = 0;

  @override
  Future<Map<String, dynamic>?> loadProfile() async => null;

  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    deletionDispatches++;
    await afterRemoteDelete?.call(currentUser!.id);
  }
}

Future<void> _until(
  ValueListenable<MotionIdentityPhase> phase,
  MotionIdentityPhase target,
) async {
  if (phase.value == target) return;
  final done = Completer<void>();
  void listener() {
    if (phase.value == target && !done.isCompleted) done.complete();
  }

  phase.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 3));
  } finally {
    phase.removeListener(listener);
  }
}

Future<void> _recovery(SupabaseClient client) async {
  await client.auth.getSessionFromUrl(
    Uri.parse(
      'com.yulalab.ostinato://auth/callback'
      '#access_token=recovery-session&refresh_token=local-refresh'
      '&token_type=bearer&expires_in=3600&type=recovery',
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pending deletion dialog keeps its unchanged-session wrapper', (
    tester,
  ) async {
    var openingCleanupCalls = 0;
    var replacementCleanupCalls = 0;
    final client = (await tester.runAsync(
      () async => _client((_) async => _json({})),
    ))!;
    final openingAccount = _DialogAccount(client);
    final replacementAccount = _DialogAccount(client);
    final account = ValueNotifier<MotionAccountClient>(openingAccount);
    addTearDown(() async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      account.dispose();
      await tester.runAsync(client.dispose);
    });
    await tester.runAsync(
      () => client.auth.setInitialSession(_session(_alice)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<MotionAccountClient>(
          valueListenable: account,
          builder: (_, value, _) => MotionAccountPage(
            account: value,
            clearLocalData: (_) async {
              if (identical(value, openingAccount)) {
                openingCleanupCalls++;
              } else {
                replacementCleanupCalls++;
              }
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    final openingSession = client.auth.currentSession;
    account.value = replacementAccount;
    await tester.pumpAndSettle();
    expect(identical(client.auth.currentSession, openingSession), isTrue);
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(openingAccount.deletionDispatches, 1);
    expect(replacementAccount.deletionDispatches, 0);
    expect(openingCleanupCalls, 1);
    expect(replacementCleanupCalls, 0);
  });

  testWidgets('same-token Session cannot inherit a pending deletion dialog', (
    tester,
  ) async {
    var cleanupCalls = 0;
    final client = (await tester.runAsync(
      () async => _client((_) async => _json({})),
    ))!;
    final account = _DialogAccount(client);
    addTearDown(() async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(client.dispose);
    });
    await tester.runAsync(
      () => client.auth.setInitialSession(_session(_alice)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MotionAccountPage(
          account: account,
          clearLocalData: (_) async => cleanupCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    final openingSession = client.auth.currentSession;
    await tester.runAsync(
      () => client.auth.setInitialSession(_session(_alice)),
    );
    final replacement = client.auth.currentSession;
    expect(identical(openingSession, replacement), isFalse);
    await tester.pump();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(account.deletionDispatches, 0);
    expect(cleanupCalls, 0);
    expect(identical(client.auth.currentSession, replacement), isTrue);
  });

  for (final holdCleanup in [false, true]) {
    test(
      'same-token replacement survives ${holdCleanup ? 'cleanup' : 'HTTP'} deletion wait',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var logoutCalls = 0;
        String? cleaned;
        final client = _client((request) async {
          if (request.url.path.endsWith('/motion-delete-account')) {
            if (!holdCleanup) {
              entered.complete();
              await release.future;
            }
            return _json({'deleted': true, 'userId': _alice});
          }
          if (request.url.path.endsWith('/logout')) logoutCalls++;
          return _json({});
        });
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session(_alice));
        final initiating = client.auth.currentSession;
        final deletion = _account(client).deleteCommonAccount(
          afterRemoteDelete: (id) async {
            cleaned = id;
            if (holdCleanup) {
              entered.complete();
              await release.future;
            }
          },
        );
        await entered.future;
        await client.auth.setInitialSession(_session(_alice));
        final replacement = client.auth.currentSession;
        expect(identical(initiating, replacement), isFalse);
        expect(replacement?.accessToken, initiating?.accessToken);
        release.complete();
        await deletion;
        expect(cleaned, _alice);
        expect(identical(client.auth.currentSession, replacement), isTrue);
        expect(client.auth.currentUser?.id, _alice);
        expect(logoutCalls, 0);
      },
    );
  }

  test(
    'unchanged initiating session signs out after confirmed deletion',
    () async {
      var logoutCalls = 0;
      String? cleaned;
      final client = _client((request) async {
        if (request.url.path.endsWith('/motion-delete-account')) {
          return _json({'deleted': true, 'userId': _alice});
        }
        if (request.url.path.endsWith('/logout')) logoutCalls++;
        return _json({});
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await _account(
        client,
      ).deleteCommonAccount(afterRemoteDelete: (id) async => cleaned = id);
      expect(cleaned, _alice);
      expect(client.auth.currentSession, isNull);
      expect(logoutCalls, 1);
    },
  );

  for (final status in [200, 403]) {
    test('same-token replacement survives held logout HTTP $status', () async {
      final entered = Completer<void>();
      final release = Completer<http.Response>();
      final client = _client((request) {
        if (request.url.path.endsWith('/motion-delete-account')) {
          return Future.value(_json({'deleted': true, 'userId': _alice}));
        }
        if (request.url.path.endsWith('/logout')) {
          entered.complete();
          return release.future;
        }
        return Future.value(_json({}));
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final deletion = _account(client).deleteCommonAccount();
      await entered.future;
      expect(client.auth.currentSession, isNull);
      await client.auth.setInitialSession(_session(_alice));
      final replacement = client.auth.currentSession;
      release.complete(_json({}, status: status));
      await deletion;
      expect(identical(client.auth.currentSession, replacement), isTrue);
    });
  }

  for (final silent in [false, true]) {
    test(
      'same-token membership response rejects ${silent ? 'silent recovery' : 'initial session'} replacement',
      () async {
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        final client = _client((_) {
          entered.complete();
          return response.future;
        });
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session(_alice));
        final initiating = client.auth.currentSession;
        final membership = _account(client).membershipStatus();
        await entered.future;
        if (silent) {
          await client.auth.recoverSession(_session(_alice));
        } else {
          await client.auth.setInitialSession(_session(_alice));
        }
        expect(identical(client.auth.currentSession, initiating), isFalse);
        expect(
          client.auth.currentSession?.accessToken,
          initiating?.accessToken,
        );
        response.complete(_json({'active': true, 'anyActive': true}));
        await expectLater(membership, throwsStateError);
      },
    );
  }

  test('same-token silent recovery rejects stale identity success', () async {
    final entered = Completer<void>();
    final response = Completer<http.Response>();
    var hold = true;
    final client = _client((request) {
      if (request.url.path.endsWith('/user') && hold) {
        if (!entered.isCompleted) entered.complete();
        return response.future;
      }
      return Future.value(_user(_alice));
    });
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    );
    addTearDown(() {
      runtime.dispose();
      client.dispose();
    });
    await client.auth.setInitialSession(_session(_alice));
    await entered.future;
    final initiating = client.auth.currentSession;
    var authEvents = 0;
    final events = client.auth.onAuthStateChange.listen((_) => authEvents++);
    await Future<void>.delayed(Duration.zero);
    authEvents = 0;
    await client.auth.recoverSession(_session(_alice));
    await Future<void>.delayed(Duration.zero);
    expect(authEvents, 0);
    expect(identical(client.auth.currentSession, initiating), isFalse);
    response.complete(_user(_alice));
    await Future<void>.delayed(Duration.zero);
    expect(runtime.userId.value, isNull);
    expect(runtime.phase.value, MotionIdentityPhase.verifying);
    hold = false;
    await runtime.refreshIdentity();
    expect(runtime.userId.value, _alice);
    expect(runtime.phase.value, MotionIdentityPhase.verified);
    await events.cancel();
  });

  test('same-token silent recovery survives user-not-found cleanup', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var missing = false;
    var logoutCalls = 0;
    var cleanupCalls = 0;
    final client = _client((request) async {
      if (request.url.path.endsWith('/user')) {
        return missing
            ? _json({
                'error_code': 'user_not_found',
                'message': 'missing',
              }, status: 403)
            : _user(_alice);
      }
      if (request.url.path.endsWith('/logout')) logoutCalls++;
      return _json({});
    });
    await client.auth.setInitialSession(_session(_alice));
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (id) {
        expect(id, _alice);
        cleanupCalls++;
        entered.complete();
        return release.future;
      },
    );
    addTearDown(() {
      runtime.dispose();
      client.dispose();
    });
    await _until(runtime.phase, MotionIdentityPhase.verified);
    missing = true;
    final refresh = runtime.refreshIdentity();
    await entered.future;
    final initiating = client.auth.currentSession;
    var authEvents = 0;
    final events = client.auth.onAuthStateChange.listen((_) => authEvents++);
    await Future<void>.delayed(Duration.zero);
    authEvents = 0;
    await client.auth.recoverSession(_session(_alice));
    final replacement = client.auth.currentSession;
    await Future<void>.delayed(Duration.zero);
    expect(authEvents, 0);
    expect(identical(initiating, replacement), isFalse);
    release.complete();
    await refresh;
    expect(cleanupCalls, 1);
    expect(logoutCalls, 0);
    expect(identical(client.auth.currentSession, replacement), isTrue);
    await events.cancel();
  });

  test('same-token silent recovery survives receipt cleanup', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var hasReceipt = false;
    var logoutCalls = 0;
    var cleanupCalls = 0;
    final client = _client((request) async {
      if (request.url.path.endsWith('/user')) return _user(_alice);
      if (request.url.path.endsWith('/logout')) logoutCalls++;
      return _json({});
    });
    await client.auth.setInitialSession(_session(_alice));
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      localAccountIds: () async => hasReceipt ? [_alice] : [],
      wasAccountDeleted: (_) async => true,
      onDeletedAccount: (id) {
        expect(id, _alice);
        cleanupCalls++;
        entered.complete();
        return release.future;
      },
    );
    addTearDown(() {
      runtime.dispose();
      client.dispose();
    });
    await _until(runtime.phase, MotionIdentityPhase.verified);
    await runtime.reconcileDeletedLocalAccounts();
    hasReceipt = true;
    final cleanup = runtime.reconcileDeletedLocalAccounts();
    await entered.future;
    final initiating = client.auth.currentSession;
    await client.auth.recoverSession(_session(_alice));
    final replacement = client.auth.currentSession;
    expect(identical(initiating, replacement), isFalse);
    release.complete();
    await cleanup;
    expect(cleanupCalls, 1);
    expect(logoutCalls, 0);
    expect(identical(client.auth.currentSession, replacement), isTrue);
  });

  for (final receipt in [
    <String, Object>{'deleted': true},
    <String, Object>{'deleted': true, 'userId': _bob},
  ]) {
    test(
      'delete rejects unowned receipt $receipt before local cleanup',
      () async {
        final client = _client((_) async => _json(receipt));
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session(_alice));
        var cleared = false;
        await expectLater(
          _account(
            client,
          ).deleteCommonAccount(afterRemoteDelete: (_) async => cleared = true),
          throwsStateError,
        );
        expect(cleared, isFalse);
        expect(client.auth.currentUser?.id, _alice);
      },
    );
  }

  test(
    'delete pins the initiating token and UUID before asynchronous dispatch',
    () async {
      String? authorization;
      Map<String, dynamic>? body;
      final client = _client((request) async {
        if (request.url.path.endsWith('/motion-delete-account')) {
          authorization = request.headers['Authorization'];
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'deleted': true,
            'userId': authorization == 'Bearer alice-session' ? _alice : _bob,
          });
        }
        return _json({});
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      String? cleared;
      final deletion = _account(
        client,
      ).deleteCommonAccount(afterRemoteDelete: (id) async => cleared = id);
      await client.auth.setInitialSession(_session(_bob, token: 'bob-session'));
      await deletion;
      expect(authorization, 'Bearer alice-session');
      expect(body?['expectedUserId'], _alice);
      expect(cleared, _alice);
      expect(client.auth.currentUser?.id, _bob);
    },
  );

  for (final replacement in [_bob, _alice]) {
    test(
      'delayed delete cleanup preserves replacement session $replacement',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final client = _client(
          (request) async => request.url.path.endsWith('/motion-delete-account')
              ? _json({'deleted': true, 'userId': _alice})
              : _json({}),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session(_alice));
        final deletion = _account(client).deleteCommonAccount(
          afterRemoteDelete: (id) {
            expect(id, _alice);
            started.complete();
            return release.future;
          },
        );
        await started.future;
        await client.auth.setInitialSession(
          _session(replacement, token: 'replacement-session'),
        );
        release.complete();
        await deletion;
        expect(client.auth.currentUser?.id, replacement);
        expect(client.auth.currentSession?.accessToken, 'replacement-session');
      },
    );
  }

  test(
    'membership cannot grant a response after an A-B-A account switch',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      String? authorization;
      final client = _client((request) {
        authorization = request.headers['Authorization'];
        started.complete();
        return response.future;
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final membership = _account(client).membershipStatus();
      await client.auth.setInitialSession(_session(_bob, token: 'bob-session'));
      await started.future;
      await client.auth.setInitialSession(
        _session(_alice, token: 'alice-replacement-session'),
      );
      response.complete(_json({'active': true, 'anyActive': true}));
      await expectLater(membership, throwsStateError);
      expect(authorization, 'Bearer alice-session');
    },
  );

  test(
    'membership response cannot survive a replacement session for its UUID',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = _client((_) {
        started.complete();
        return response.future;
      });
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final membership = _account(client).membershipStatus();
      await started.future;
      await client.auth.setInitialSession(
        _session(_alice, token: 'alice-replacement-session'),
      );
      response.complete(_json({'active': true, 'anyActive': true}));
      await expectLater(membership, throwsStateError);
    },
  );

  test(
    'user-not-found cleanup cannot sign out a newer verified account',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final client = _client((request) async {
        if (request.url.path.endsWith('/user')) {
          return request.headers['Authorization'] == 'Bearer alice-session'
              ? _json({
                  'error_code': 'user_not_found',
                  'message': 'missing',
                }, status: 403)
              : _user(_bob);
        }
        return _json({});
      });
      await client.auth.setInitialSession(_session(_alice));
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.ostinato,
        onDeletedAccount: (id) {
          expect(id, _alice);
          started.complete();
          return release.future;
        },
      );
      addTearDown(() {
        runtime.dispose();
        client.dispose();
      });
      await started.future;
      await client.auth.setInitialSession(_session(_bob, token: 'bob-session'));
      await _until(runtime.phase, MotionIdentityPhase.verified);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(client.auth.currentUser?.id, _bob);
      expect(runtime.userId.value, _bob);
      expect(runtime.phase.value, MotionIdentityPhase.verified);
    },
  );

  test(
    'receipt cleanup cannot sign out a replacement session for the same UUID',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final client = _client(
        (request) async =>
            request.url.path.endsWith('/user') ? _user(_alice) : _json({}),
      );
      await client.auth.setInitialSession(_session(_alice));
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.ostinato,
        localAccountIds: () async => [_alice],
        wasAccountDeleted: (_) async => true,
        onDeletedAccount: (_) {
          started.complete();
          return release.future;
        },
      );
      addTearDown(() {
        runtime.dispose();
        client.dispose();
      });
      await started.future;
      await client.auth.setInitialSession(
        _session(_alice, token: 'replacement-session'),
      );
      await runtime.refreshIdentity();
      release.complete();
      await runtime.reconcileDeletedLocalAccounts();
      expect(client.auth.currentSession?.accessToken, 'replacement-session');
      expect(runtime.phase.value, MotionIdentityPhase.verified);
    },
  );

  testWidgets(
    'stalled verification reaches guest retry without deleting history',
    (tester) async {
      final pending = Completer<http.Response>();
      var cleared = false;
      final client = _client((_) => pending.future);
      await client.auth.setInitialSession(_session(_alice));
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.ostinato,
        onDeletedAccount: (_) async => cleared = true,
      );
      addTearDown(() {
        runtime.dispose();
        client.dispose();
      });
      await tester.pumpWidget(
        MotionIdentityGate(
          runtime: runtime,
          child: const MaterialApp(home: Text('GUEST_HISTORY')),
        ),
      );
      await tester.pump(const Duration(seconds: 11));
      expect(runtime.phase.value, MotionIdentityPhase.unavailable);
      expect(runtime.userId.value, isNull);
      expect(cleared, isFalse);
      expect(find.text('Continue as guest'), findsOneWidget);
      expect(find.text('GUEST_HISTORY'), findsNothing);
      pending.complete(_user(_alice));
      await tester.pump();
      expect(runtime.phase.value, MotionIdentityPhase.unavailable);
      expect(runtime.userId.value, isNull);
    },
  );

  test(
    'recovery listenable follows callback, password success and sign-out',
    () async {
      final client = _client(
        (request) async =>
            request.url.path.endsWith('/user') ? _user(_alice) : _json({}),
      );
      await client.auth.setInitialSession(_session(_alice));
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.ostinato,
        onDeletedAccount: (_) async {},
      );
      addTearDown(() {
        runtime.dispose();
        client.dispose();
      });
      await _until(runtime.phase, MotionIdentityPhase.verified);
      final recovery = runtime.passwordRecovery;
      final observations = <bool>[];
      recovery.addListener(() => observations.add(recovery.value));
      expect(recovery.value, isFalse);
      await _recovery(client);
      expect(recovery.value, isTrue);
      expect(runtime.isPasswordRecovery, isTrue);
      await runtime.account.updatePassword('LocalOnly!Pass123');
      await Future<void>.delayed(Duration.zero);
      expect(recovery.value, isFalse);
      await _recovery(client);
      expect(recovery.value, isTrue);
      await runtime.account.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(recovery.value, isFalse);
      expect(observations, [true, false, true, false]);
    },
  );
}
