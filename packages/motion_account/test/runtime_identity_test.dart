import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '00000000-0000-4000-8000-000000000001';

String _session() => jsonEncode({
  'access_token': 'local-test-token',
  'token_type': 'bearer',
  'user': {
    'id': _userId,
    'aud': 'authenticated',
    'created_at': '2026-09-24T00:00:00Z',
    'app_metadata': <String, dynamic>{},
  },
});

http.Response _userResponse() => http.Response(
  jsonEncode({
    'id': _userId,
    'aud': 'authenticated',
    'created_at': '2026-09-24T00:00:00Z',
    'app_metadata': <String, dynamic>{},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restored identity stays closed until server verifies it', () async {
    final pending = Completer<http.Response>();
    var hold = true;
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user')) {
          return hold ? pending.future : _userResponse();
        }
        return http.Response('{}', 200);
      }),
    );
    await client.auth.setInitialSession(_session());
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    );
    expect(runtime.userId.value, isNull);
    expect(runtime.phase.value, MotionIdentityPhase.verifying);
    pending.complete(_userResponse());
    await _until(runtime.phase, MotionIdentityPhase.verified);
    expect(runtime.userId.value, _userId);

    hold = false;
    final refresh = runtime.refreshIdentity();
    expect(runtime.userId.value, _userId);
    await refresh;
    expect(runtime.phase.value, MotionIdentityPhase.verified);
    runtime.dispose();
    client.dispose();
  });

  test(
    'deleted account clears its app data and closes restored session',
    () async {
      String? deletedUser;
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/user')) {
            return http.Response(
              '{"code":"user_not_found","error_code":"user_not_found","message":"User missing"}',
              403,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 403);
        }),
      );
      await client.auth.setInitialSession(_session());
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.gravita,
        onDeletedAccount: (userId) async => deletedUser = userId,
      );
      await _until(runtime.phase, MotionIdentityPhase.signedOut);
      expect(deletedUser, _userId);
      expect(runtime.userId.value, isNull);
      expect(client.auth.currentUser, isNull);
      runtime.dispose();
      client.dispose();
    },
  );

  test('network failure never opens cached account history', () async {
    var cleared = false;
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );
    await client.auth.setInitialSession(_session());
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.lissom,
      onDeletedAccount: (_) async => cleared = true,
    );
    await _until(runtime.phase, MotionIdentityPhase.unavailable);
    expect(runtime.userId.value, isNull);
    expect(cleared, isFalse);
    runtime.dispose();
    client.dispose();
  });

  test(
    'confirmed remote deletion reports pending local cleanup truthfully',
    () async {
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/motion-delete-account')) {
            return http.Response(
              '{"deleted":true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await client.auth.setInitialSession(_session());
      final account = MotionAccountClient(
        supabase: client,
        app: MotionApp.ostinato,
        emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
      );
      await expectLater(
        account.deleteCommonAccount(
          afterRemoteDelete: (_) async => throw StateError('disk unavailable'),
        ),
        throwsA(isA<MotionLocalCleanupPending>()),
      );
      expect(client.auth.currentUser, isNull);
      client.dispose();
    },
  );

  testWidgets('offline cached identity can use only guest space', (
    tester,
  ) async {
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );
    await client.auth.setInitialSession(_session());
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.lissom,
      onDeletedAccount: (_) async {},
    );
    addTearDown(() {
      runtime.dispose();
      client.dispose();
    });
    await tester.runAsync(
      () => _until(runtime.phase, MotionIdentityPhase.unavailable),
    );
    await tester.pumpWidget(
      MotionIdentityGate(
        runtime: runtime,
        child: const MaterialApp(home: Scaffold(body: Text('GUEST_ONLY'))),
      ),
    );
    expect(find.text('GUEST_ONLY'), findsNothing);
    expect(runtime.userId.value, isNull);
    await tester.tap(find.text('Continue as guest'));
    await tester.pump();
    expect(find.text('GUEST_ONLY'), findsOneWidget);
    expect(runtime.userId.value, isNull);
    expect(client.auth.currentUser, isNull);
    expect(runtime.phase.value, MotionIdentityPhase.signedOut);
  });

  test(
    'signed-out app clears only IDs with a server deletion receipt',
    () async {
      const otherId = '00000000-0000-4000-8000-000000000002';
      final cleared = <String>[];
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.jablab,
        onDeletedAccount: (id) async => cleared.add(id),
        localAccountIds: () async => <String>[_userId, otherId, '../guest'],
        wasAccountDeleted: (id) async => id == _userId,
      );
      await runtime.reconcileDeletedLocalAccounts();
      expect(cleared, <String>[_userId]);
      expect(runtime.phase.value, MotionIdentityPhase.signedOut);
      runtime.dispose();
      client.dispose();
    },
  );

  test('an unavailable receipt lookup preserves local history', () async {
    final cleared = <String>[];
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.choreia,
      onDeletedAccount: (id) async => cleared.add(id),
      localAccountIds: () async => <String>[_userId],
      wasAccountDeleted: (_) async => throw const SocketException('offline'),
    );
    await expectLater(
      runtime.reconcileDeletedLocalAccounts(),
      throwsA(isA<SocketException>()),
    );
    expect(cleared, isEmpty);
    runtime.dispose();
    client.dispose();
  });

  test('offline receipt lookup retries after network recovery', () async {
    var lookups = 0;
    final cleaned = Completer<String>();
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    final runtime = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (id) async => cleaned.complete(id),
      localAccountIds: () async => <String>[_userId],
      wasAccountDeleted: (_) async {
        lookups++;
        if (lookups == 1) throw const SocketException('offline');
        return true;
      },
      receiptRetryDelay: const Duration(milliseconds: 10),
    );
    expect(await cleaned.future.timeout(const Duration(seconds: 2)), _userId);
    expect(lookups, 2);
    runtime.dispose();
    client.dispose();
  });

  test(
    'resuming the app checks an account deleted while it was away',
    () async {
      var deleted = false;
      final cleared = Completer<String>();
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.gravita,
        onDeletedAccount: (id) async => cleared.complete(id),
        localAccountIds: () async => <String>[_userId],
        wasAccountDeleted: (_) async => deleted,
      );
      await runtime.reconcileDeletedLocalAccounts();
      deleted = true;
      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(await cleared.future.timeout(const Duration(seconds: 2)), _userId);
      runtime.dispose();
      client.dispose();
    },
  );
}
