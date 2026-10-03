import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '11111111-1111-1111-1111-111111111111';
const _bob = '22222222-2222-2222-2222-222222222222';
const _product = 'com.yulalab.ostinato.motionplus.monthly';

String _session([String userId = _alice, String token = 'local-test-token']) =>
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'created_at': '2026-09-24T00:00:00Z',
        'app_metadata': <String, dynamic>{},
      },
    });

StorePurchaseEvidence _evidence() => const StorePurchaseEvidence(
  platform: StorePlatform.ios,
  originatingAppId: 'ostinato',
  productId: _product,
  verificationData: 'store-receipt',
  transactionId: '123456789',
);

http.Response _verified({String userId = _alice, String state = 'active'}) =>
    http.Response(
      jsonEncode({
        'userId': userId,
        'appId': 'motion_plus',
        'productId': _product,
        'state': state,
        'expiresAt': '2026-10-24T16:00:00.000Z',
        'lastVerifiedAt': '2026-09-24T16:00:00.000Z',
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final silent in [false, true]) {
    test(
      'same-token purchase response rejects ${silent ? 'silent recovery' : 'initial session'} replacement',
      () async {
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        final client = SupabaseClient(
          'https://motion.example.invalid',
          'public-test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((_) {
            entered.complete();
            return response.future;
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(_session());
        final initiating = client.auth.currentSession;
        final verifying = SupabasePurchaseServerAdapter(
          client,
        ).verify(_evidence());
        await entered.future;
        if (silent) {
          await client.auth.recoverSession(_session());
        } else {
          await client.auth.setInitialSession(_session());
        }
        expect(identical(client.auth.currentSession, initiating), isFalse);
        expect(
          client.auth.currentSession?.accessToken,
          initiating?.accessToken,
        );
        response.complete(_verified());
        expect(await verifying, isNull);
      },
    );
  }

  test(
    'authenticated purchase evidence reaches the Motion Edge Function',
    () async {
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, endsWith('/motion-verify-purchase'));
          expect(request.headers['authorization'], 'Bearer local-test-token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['store'], 'apple');
          expect(body['originatingAppId'], 'ostinato');
          expect(body['transactionId'], '123456789');
          return _verified();
        }),
      );
      await client.auth.setInitialSession(_session());
      final status = await SupabasePurchaseServerAdapter(
        client,
      ).verify(_evidence());
      expect(status?.source, EntitlementSource.server);
      expect(
        status?.grantsAccessAt(
          DateTime.utc(2026, 9, 25),
          userId: _alice,
          appId: 'lissom',
        ),
        isTrue,
      );
      client.dispose();
    },
  );

  test('mismatched user and revoked responses cannot grant access', () async {
    for (final response in [
      _verified(userId: _bob),
      _verified(state: 'revoked'),
    ]) {
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async => response),
      );
      await client.auth.setInitialSession(_session());
      final status = await SupabasePurchaseServerAdapter(
        client,
      ).verify(_evidence());
      expect(
        status?.grantsAccessAt(
              DateTime.utc(2026, 9, 25),
              userId: _alice,
              appId: 'ostinato',
            ) ??
            false,
        isFalse,
      );
      client.dispose();
    }
  });

  test('account switch during verification discards the response', () async {
    final pending = Completer<http.Response>();
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) => pending.future),
    );
    await client.auth.setInitialSession(_session());
    final verifying = SupabasePurchaseServerAdapter(client).verify(_evidence());
    await client.auth.setInitialSession(_session(_bob));
    pending.complete(_verified());
    expect(await verifying, isNull);
    client.dispose();
  });

  test('purchase dispatch keeps its initiating account token', () async {
    String? authorization;
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        authorization =
            request.headers['Authorization'] ??
            request.headers['authorization'];
        return _verified(
          userId: authorization == 'Bearer alice-session' ? _alice : _bob,
        );
      }),
    );
    await client.auth.setInitialSession(_session(_alice, 'alice-session'));
    final verifying = SupabasePurchaseServerAdapter(client).verify(_evidence());
    await client.auth.setInitialSession(_session(_bob, 'bob-session'));
    expect(await verifying, isNull);
    expect(authorization, 'Bearer alice-session');
    client.dispose();
  });

  test('purchase response cannot survive an A-B-A account switch', () async {
    final dispatched = Completer<void>();
    final pending = Completer<http.Response>();
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) {
        dispatched.complete();
        return pending.future;
      }),
    );
    await client.auth.setInitialSession(_session(_alice, 'alice-session'));
    final verifying = SupabasePurchaseServerAdapter(client).verify(_evidence());
    await dispatched.future;
    await client.auth.setInitialSession(_session(_bob, 'bob-session'));
    await client.auth.setInitialSession(
      _session(_alice, 'replacement-session'),
    );
    pending.complete(_verified());
    expect(await verifying, isNull);
    client.dispose();
  });

  test('purchase response cannot survive a new session for its UUID', () async {
    final dispatched = Completer<void>();
    final pending = Completer<http.Response>();
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) {
        dispatched.complete();
        return pending.future;
      }),
    );
    await client.auth.setInitialSession(_session(_alice, 'alice-session'));
    final verifying = SupabasePurchaseServerAdapter(client).verify(_evidence());
    await dispatched.future;
    await client.auth.setInitialSession(
      _session(_alice, 'replacement-session'),
    );
    pending.complete(_verified());
    expect(await verifying, isNull);
    client.dispose();
  });
}
