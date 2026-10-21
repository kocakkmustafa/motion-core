// K08 closure tests: per-method total deadlines, unknown mutation outcomes and
// readback. Real SupabaseClient with held mock HTTP replies; no live backend.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '00000000-0000-4000-8000-000000000001';
const _bob = '00000000-0000-4000-8000-000000000002';
const _short = Duration(milliseconds: 150);
const _wait = Duration(seconds: 3);

String _session(String id, {String token = 'alice-session'}) => jsonEncode({
  'access_token': token,
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'expires_at': 4102444800,
  'expires_in': 3600,
  'user': {
    'id': id,
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

http.Response _notFound() => _json({
  'code': 'user_not_found',
  'error_code': 'user_not_found',
  'message': 'synthetic missing user',
}, status: 403);

/// Routes by path suffix; unmatched paths answer `{}`. Records every request.
class _Router {
  _Router(this.routes);
  final Map<String, Future<http.Response> Function(http.Request)> routes;
  final requests = <http.Request>[];

  int count(String suffix) =>
      requests.where((r) => r.url.path.endsWith(suffix)).length;

  Future<http.Response> call(http.Request request) async {
    requests.add(request);
    var response = _json(<String, dynamic>{});
    for (final entry in routes.entries) {
      if (request.url.path.endsWith(entry.key)) {
        response = await entry.value(request);
        break;
      }
    }
    // A real transport links the reply to its request; PostgREST's error
    // decoding reads that link.
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

SupabaseClient _client(_Router router) => SupabaseClient(
  'https://motion.example.invalid',
  'public-test-key',
  // Implicit flow: a plain client has no PKCE verifier storage. The Motion
  // runtime itself uses PKCE with the Flutter storage.
  authOptions: const AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.implicit,
  ),
  httpClient: MockClient(router.call),
);

MotionAccountClient _account(
  SupabaseClient client, {
  Future<bool> Function(String userId)? deletionReceipt,
}) => MotionAccountClient(
  supabase: client,
  app: MotionApp.ostinato,
  emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
  deletionReceipt: deletionReceipt,
  operationTimeout: _short,
  readTimeout: _short,
);

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > _wait) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Matcher _unknown(MotionAccountOperation operation) =>
    isA<MotionOperationUnknown>().having(
      (e) => e.operation,
      'operation',
      operation,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T07/T08 Auth mutations', () {
    test('held sign-in reply is unknown, single dispatch, late Session '
        'is still observed by the SDK', () async {
      final reply = Completer<http.Response>();
      final router = _Router({'/token': (_) => reply.future});
      final client = _client(router);
      addTearDown(client.dispose);
      final account = _account(client);

      final watch = Stopwatch()..start();
      await expectLater(
        account.signIn(email: 'a@example.invalid', password: 'secret-pass'),
        throwsA(_unknown(MotionAccountOperation.signIn)),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(router.count('/token'), 1);
      expect(client.auth.currentUser, isNull);

      // A late reply is an SDK effect outside this call; no retry was sent.
      reply.complete(
        http.Response(
          _session(_alice),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await _until(() => client.auth.currentUser != null);
      expect(client.auth.currentUser!.id, _alice);
      expect(router.count('/token'), 1);
    });

    test('definite 400 rejection is rethrown, not unknown', () async {
      final router = _Router({
        '/token': (_) async => _json({
          'error_code': 'invalid_credentials',
          'message': 'synthetic invalid',
        }, status: 400),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await expectLater(
        _account(client).signIn(email: 'a@example.invalid', password: 'x'),
        throwsA(isA<AuthApiException>()),
      );
    });

    for (final (name, path, operation, call)
        in <
          (
            String,
            String,
            MotionAccountOperation,
            Future<void> Function(MotionAccountClient),
          )
        >[
          (
            'sign-up',
            '/signup',
            MotionAccountOperation.signUp,
            (a) =>
                a.signUp(email: 'n@example.invalid', password: 'new-password'),
          ),
          (
            'password reset',
            '/recover',
            MotionAccountOperation.passwordReset,
            (a) => a.sendPasswordReset('n@example.invalid'),
          ),
          (
            'confirmation resend',
            '/resend',
            MotionAccountOperation.resendConfirmation,
            (a) => a.resendConfirmation('n@example.invalid'),
          ),
        ]) {
      test(
        '$name: held mail request is unknown and never sent twice',
        () async {
          final router = _Router({
            path: (_) => Completer<http.Response>().future,
          });
          final client = _client(router);
          addTearDown(client.dispose);
          await expectLater(
            call(_account(client)),
            throwsA(_unknown(operation)),
          );
          await Future<void>.delayed(_short * 2);
          expect(router.count(path), 1);
        },
      );

      test('$name: transport loss after dispatch is unknown', () async {
        final router = _Router({
          path: (_) async => throw const SocketException('synthetic reset'),
        });
        final client = _client(router);
        addTearDown(client.dispose);
        await expectLater(call(_account(client)), throwsA(_unknown(operation)));
        expect(router.count(path), 1);
      });
    }

    test('held password update is unknown; no re-login or retry', () async {
      final router = _Router({
        '/user': (r) => r.method == 'PUT'
            ? Completer<http.Response>().future
            : Future.value(_json({'id': _alice})),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await expectLater(
        _account(client).updatePassword('new-password-1'),
        throwsA(_unknown(MotionAccountOperation.updatePassword)),
      );
      expect(router.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(router.count('/token'), 0);
      expect(client.auth.currentUser?.id, _alice);
    });

    test(
      'held remote logout: local discard observed, revoke unknown',
      () async {
        final router = _Router({
          '/logout': (_) => Completer<http.Response>().future,
        });
        final client = _client(router);
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session(_alice));
        await expectLater(
          _account(client).signOut(),
          throwsA(_unknown(MotionAccountOperation.signOut)),
        );
        expect(client.auth.currentUser, isNull);
        expect(router.count('/logout'), 1);
      },
    );
  });

  group('T05/T09 profile', () {
    test('held profile read ends within its budget with one GET', () async {
      final router = _Router({
        '/motion_profiles': (_) => Completer<http.Response>().future,
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final watch = Stopwatch()..start();
      await expectLater(
        _account(client).loadProfile(),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      await Future<void>.delayed(_short * 2);
      expect(router.count('/motion_profiles'), 1);
    });

    test('held upsert is unknown and is not replayed', () async {
      final router = _Router({
        '/motion_profiles': (_) => Completer<http.Response>().future,
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await expectLater(
        _account(client).saveDisplayName('Alice'),
        throwsA(_unknown(MotionAccountOperation.saveProfile)),
      );
      await Future<void>.delayed(_short * 2);
      expect(router.count('/motion_profiles'), 1);
    });

    test('decoded database error is a definite rejection', () async {
      final router = _Router({
        '/motion_profiles': (_) async => _json({
          'code': '23514',
          'message': 'synthetic check violation',
        }, status: 400),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await expectLater(
        _account(client).saveDisplayName('Alice'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('undecodable 503 gateway reply is unknown', () async {
      final router = _Router({
        '/motion_profiles': (_) async =>
            http.Response('<html>busy</html>', 503),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await expectLater(
        _account(client).saveDisplayName('Alice'),
        throwsA(_unknown(MotionAccountOperation.saveProfile)),
      );
    });
  });

  group('T10 deletion response loss', () {
    Future<(SupabaseClient, _Router)> signedIn(
      Future<http.Response> Function(http.Request) delete,
    ) async {
      final router = _Router({
        '/motion-delete-account': delete,
        '/logout': (_) async => http.Response('', 204),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      return (client, router);
    }

    test(
      'lost reply + positive receipt: one cleanup, same Session logout',
      () async {
        final (client, _) = await signedIn(
          (_) => Completer<http.Response>().future,
        );
        final probes = <String>[];
        final cleaned = <String>[];
        await _account(
          client,
          deletionReceipt: (id) async {
            probes.add(id);
            return true;
          },
        ).deleteCommonAccount(afterRemoteDelete: (id) async => cleaned.add(id));
        expect(probes, [_alice]);
        expect(cleaned, [_alice]);
        expect(client.auth.currentUser, isNull);
      },
    );

    for (final (label, probe) in <(String, Future<bool> Function(String))>[
      ('negative receipt', (_) async => false),
      ('receipt error', (_) async => throw const SocketException('offline')),
      ('stalled receipt', (_) => Completer<bool>().future),
    ]) {
      test('lost reply + $label: unknown, files and Session kept', () async {
        final (client, _) = await signedIn(
          (_) async => throw const SocketException('synthetic reset'),
        );
        final cleaned = <String>[];
        await expectLater(
          _account(client, deletionReceipt: probe).deleteCommonAccount(
            afterRemoteDelete: (id) async => cleaned.add(id),
          ),
          throwsA(_unknown(MotionAccountOperation.deleteAccount)),
        );
        expect(cleaned, isEmpty);
        expect(client.auth.currentUser?.id, _alice);
      });
    }

    test('401 is a definite rejection: no receipt probe, no cleanup', () async {
      final (client, _) = await signedIn(
        (_) async => _json({'error': 'unauthorized'}, status: 401),
      );
      var probes = 0;
      final cleaned = <String>[];
      await expectLater(
        _account(
          client,
          deletionReceipt: (_) async {
            probes++;
            return true;
          },
        ).deleteCommonAccount(afterRemoteDelete: (id) async => cleaned.add(id)),
        throwsA(isA<StateError>()),
      );
      expect(probes, 0);
      expect(cleaned, isEmpty);
      expect(client.auth.currentUser?.id, _alice);
    });

    test('5xx may follow a commit: the receipt decides', () async {
      final (client, _) = await signedIn(
        (_) async => _json({'error': 'deletion_failed'}, status: 500),
      );
      final cleaned = <String>[];
      await _account(
        client,
        deletionReceipt: (_) async => true,
      ).deleteCommonAccount(afterRemoteDelete: (id) async => cleaned.add(id));
      expect(cleaned, [_alice]);
    });

    test('a replacement Session is never signed out by readback', () async {
      final (client, _) = await signedIn(
        (_) => Completer<http.Response>().future,
      );
      final cleaned = <String>[];
      // Bob's Session replaces Alice's while the receipt read is in flight.
      await _account(
        client,
        deletionReceipt: (_) async {
          await client.auth.recoverSession(
            _session(_bob, token: 'bob-session'),
          );
          return true;
        },
      ).deleteCommonAccount(afterRemoteDelete: (id) async => cleaned.add(id));
      expect(cleaned, [_alice]);
      expect(client.auth.currentUser?.id, _bob);
    });
  });

  group('T11 membership', () {
    test('held membership check times out and grants nothing', () async {
      final router = _Router({
        '/motion-check-membership': (_) => Completer<http.Response>().future,
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      await expectLater(
        _account(client).hasActiveMembership(),
        throwsA(isA<TimeoutException>()),
      );
      expect(router.count('/motion-check-membership'), 1);
    });
  });

  group('T02/T03/T04/T06 runtime budgets', () {
    MotionAccountRuntime runtime(
      SupabaseClient client, {
      required Future<void> Function(String) onDeletedAccount,
      Future<Iterable<String>> Function()? localAccountIds,
      Future<bool> Function(String)? wasAccountDeleted,
      Duration receiptRetryDelay = const Duration(minutes: 2),
    }) {
      final value = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.ostinato,
        onDeletedAccount: onDeletedAccount,
        localAccountIds: localAccountIds,
        wasAccountDeleted: wasAccountDeleted,
        receiptRetryDelay: receiptRetryDelay,
        identityVerificationTimeout: _short,
        identityTotalTimeout: _short * 2,
        receiptReadTimeout: _short,
        reconcileTimeout: _short * 3,
        guestTimeout: _short,
        operationTimeout: _short,
      );
      addTearDown(value.dispose);
      return value;
    }

    test('T02 user_not_found cleanup past the budget stays pending; Retry '
        'joins the same ticket and the dead Session is discarded', () async {
      final router = _Router({
        '/user': (_) async => _notFound(),
        '/logout': (_) async => http.Response('', 204),
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final release = Completer<void>();
      final erased = <String>[];
      final rt = runtime(
        client,
        onDeletedAccount: (id) {
          erased.add(id);
          return release.future;
        },
      );

      await _until(() => rt.localCleanupPending.value);
      await expectLater(
        rt.refreshIdentity(),
        throwsA(isA<MotionLocalCleanupPending>()),
      );
      expect(erased, [_alice]);
      expect(rt.phase.value, MotionIdentityPhase.unavailable);
      expect(rt.isCurrentSessionVerified, isFalse);
      expect(client.auth.currentUser?.id, _alice);

      release.complete();
      await _until(() => !rt.localCleanupPending.value);
      await _until(() => client.auth.currentUser == null);
      expect(erased, [_alice]);
      expect(rt.phase.value, MotionIdentityPhase.signedOut);
    });

    test('T04 a listing that never returns ends the pass and releases '
        'single-flight', () async {
      final client = _client(_Router({}));
      addTearDown(client.dispose);
      var listings = 0;
      final erased = <String>[];
      final rt = runtime(
        client,
        onDeletedAccount: (id) async => erased.add(id),
        localAccountIds: () {
          listings++;
          return Completer<Iterable<String>>().future;
        },
      );
      // The constructor's own pass is held; an explicit call joins it.
      await expectLater(
        rt.reconcileDeletedLocalAccounts(),
        throwsA(isA<TimeoutException>()),
      );
      expect(listings, 1);
      final next = rt.reconcileDeletedLocalAccounts();
      expect(listings, 2);
      await expectLater(next, throwsA(isA<TimeoutException>()));
      expect(erased, isEmpty);
    });

    test('T04 a stalled receipt is not false; other UUIDs progress; a late '
        'positive from that read admits nothing', () async {
      final client = _client(_Router({}));
      addTearDown(client.dispose);
      final local = <String>{_alice, _bob};
      final aliceReceipt = Completer<bool>();
      var aliceReads = 0;
      final erased = <String>[];
      final rt = runtime(
        client,
        onDeletedAccount: (id) async {
          erased.add(id);
          local.remove(id);
        },
        localAccountIds: () async => local.toList(),
        wasAccountDeleted: (id) {
          if (id == _bob) return Future.value(true);
          aliceReads++;
          return aliceReads == 1 ? aliceReceipt.future : Future.value(false);
        },
      );
      await expectLater(
        rt.reconcileDeletedLocalAccounts(),
        throwsA(isA<TimeoutException>()),
      );
      expect(erased, [_bob]);
      aliceReceipt.complete(true); // late positive of an abandoned read
      await Future<void>.delayed(_short);
      expect(erased, [_bob]);
      expect(local, {_alice});
      await rt.reconcileDeletedLocalAccounts(); // fresh read says false
      expect(erased, [_bob]);
    });

    test('T04 inconclusive pass schedules the retry timer', () async {
      final client = _client(_Router({}));
      addTearDown(client.dispose);
      var reads = 0;
      final cleaned = Completer<String>();
      runtime(
        client,
        onDeletedAccount: (id) async => cleaned.complete(id),
        localAccountIds: () async => const [_alice],
        wasAccountDeleted: (_) {
          reads++;
          return reads == 1 ? Completer<bool>().future : Future.value(true);
        },
        receiptRetryDelay: const Duration(milliseconds: 20),
      );
      expect(await cleaned.future.timeout(_wait), _alice);
      expect(reads, 2);
    });

    test('T06 admitted cleanup past the pass budget is joined, never '
        'duplicated, by the next pass', () async {
      final client = _client(_Router({}));
      addTearDown(client.dispose);
      final release = Completer<void>();
      var erases = 0;
      final rt = runtime(
        client,
        onDeletedAccount: (_) {
          erases++;
          return release.future;
        },
        localAccountIds: () async => const [_alice],
        wasAccountDeleted: (_) async => true,
      );
      await expectLater(
        rt.reconcileDeletedLocalAccounts(),
        throwsA(isA<TimeoutException>()),
      );
      expect(rt.localCleanupPending.value, isTrue);
      final second = rt.reconcileDeletedLocalAccounts();
      await Future<void>.delayed(_short);
      expect(erases, 1);
      release.complete();
      await second;
      expect(erases, 1);
      expect(rt.localCleanupPending.value, isFalse);
    });

    test('T03 stalled guest logout is unknown, not guest success; an '
        'explicit retry completes locally', () async {
      final router = _Router({
        '/user': (_) async => throw const SocketException('offline'),
        '/logout': (_) => Completer<http.Response>().future,
      });
      final client = _client(router);
      addTearDown(client.dispose);
      await client.auth.setInitialSession(_session(_alice));
      final rt = runtime(client, onDeletedAccount: (_) async {});
      await _until(() => rt.phase.value == MotionIdentityPhase.unavailable);

      await expectLater(
        rt.continueAsGuest(),
        throwsA(_unknown(MotionAccountOperation.continueAsGuest)),
      );
      expect(router.count('/logout'), 1);
      await rt.continueAsGuest();
      expect(router.count('/logout'), 1); // no token left to revoke
      expect(client.auth.currentSession, isNull);
      expect(rt.phase.value, MotionIdentityPhase.signedOut);
    });
  });

  test('public listenable exposes no UUID', () {
    final client = _client(_Router({}));
    addTearDown(client.dispose);
    final rt = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    );
    addTearDown(rt.dispose);
    expect(rt.localCleanupPending, isA<ValueListenable<bool>>());
  });
}
