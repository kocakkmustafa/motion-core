// Under-13 parental consent (ADR-008 / VELI-01): state machine, device token,
// device-consent client calls, flagged restrictions and the page hand-off.
// Synthetic data only; no real network.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _today = DateTime(2026, 11, 16);

MotionAgeDeclaration _born(int year, int month, String? country) =>
    MotionAgeDeclaration(
      birthYear: year,
      birthMonth: month,
      countryCode: country,
      policyVersion: MotionAgePolicy.version,
    );

const _token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ'; // 43 chars

http.Response _json(http.BaseRequest request, int status, Object? body) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

MotionAccountClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  Duration readTimeout = const Duration(seconds: 10),
  Duration operationTimeout = const Duration(seconds: 20),
}) {
  final supabase = SupabaseClient(
    'https://motion.example.invalid',
    'public-test-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
    httpClient: MockClient(handler),
  );
  addTearDown(supabase.dispose);
  return MotionAccountClient(
    supabase: supabase,
    app: MotionApp.lissom,
    emailRedirectTo: 'com.yulalab.lissom://auth/callback',
    readTimeout: readTimeout,
    operationTimeout: operationTimeout,
  );
}

void main() {
  group('state machine (every cell of the transition table)', () {
    const none = MotionParentalConsent.none;
    const pending = MotionParentalConsent.pending;
    const approved = MotionParentalConsent.approved;
    const denied = MotionParentalConsent.denied;
    const expired = MotionParentalConsent.expired;
    const withdrawn = MotionParentalConsent.withdrawn;
    const e = MotionConsentEvent.values;
    // Order of events: request, approve, deny, linkExpire, retentionPurge,
    // withdraw. null = refused.
    final table = <MotionParentalConsent, List<MotionParentalConsent?>>{
      none: [pending, null, null, null, null, null],
      pending: [pending, approved, denied, expired, none, null],
      approved: [null, null, null, null, none, withdrawn],
      denied: [null, null, null, null, none, null],
      expired: [pending, null, null, null, none, null],
      withdrawn: [null, null, null, null, none, null],
    };

    test('the event order of the table matches the enum', () {
      expect(e.map((x) => x.name), [
        'request',
        'approve',
        'deny',
        'linkExpire',
        'retentionPurge',
        'withdraw',
      ]);
      expect(table.keys.toSet(), MotionParentalConsent.values.toSet());
    });

    for (final from in MotionParentalConsent.values) {
      for (var i = 0; i < e.length; i++) {
        final expected = table[from]![i];
        test(
          '${from.name} + ${e[i].name} -> ${expected?.name ?? 'refused'}',
          () {
            expect(MotionParentalConsentMachine.next(from, e[i]), expected);
          },
        );
      }
    }
  });

  group('device token', () {
    test('is 43 base64url characters without padding', () {
      final token = MotionDeviceConsentToken.generate();
      expect(token, hasLength(43));
      expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token), isTrue);
      expect(token, isNot(contains('=')));
      expect(MotionDeviceConsentToken.isWellFormed(token), isTrue);
      expect(base64Url.decode('$token='), hasLength(32));
    });

    test('is unique across calls', () {
      final tokens = {
        for (var i = 0; i < 200; i++) MotionDeviceConsentToken.generate(),
      };
      expect(tokens, hasLength(200));
    });

    test('depends only on the random source, never on child data', () {
      // The API takes no child, device or address input; a fixed source
      // proves the output is a pure function of the random bytes.
      final a = MotionDeviceConsentToken.generate(random: Random(7));
      final b = MotionDeviceConsentToken.generate(random: Random(7));
      final c = MotionDeviceConsentToken.generate(random: Random(8));
      expect(a, b);
      expect(a, isNot(c));
    });

    test('malformed tokens are not well formed', () {
      for (final bad in [
        null,
        '',
        'short',
        '${_token}x',
        _token.replaceRange(0, 1, '='),
        _token.replaceRange(0, 1, '+'),
      ]) {
        expect(MotionDeviceConsentToken.isWellFormed(bad), isFalse);
      }
    });
  });

  group('policy flag', () {
    test('default bandFor is unchanged: under 13 stays blocked', () {
      final d = _born(2015, 1, 'US');
      expect(MotionAgePolicy.bandFor(d, today: _today), MotionAgeBand.blocked);
      expect(
        MotionAgePolicy.bandFor(d, today: _today, underThirteenConsent: true),
        MotionAgeBand.underThirteenConsentRequired,
      );
      // 13+ results do not depend on the flag.
      for (final d in [
        _born(2012, 9, 'DE'),
        _born(2012, 9, 'US'),
        _born(1990, 1, 'TR'),
      ]) {
        expect(
          MotionAgePolicy.bandFor(d, today: _today, underThirteenConsent: true),
          MotionAgePolicy.bandFor(d, today: _today),
        );
      }
    });

    test('the new band is never marketed to and needs analytics opt-in', () {
      const band = MotionAgeBand.underThirteenConsentRequired;
      expect(MotionAgePolicy.marketingAllowed(band), isFalse);
      expect(MotionAgePolicy.analyticsNeedsOptIn(band), isTrue);
    });

    test('purchaseRestrictedOn for each of the six consent states', () {
      final policies = MotionTeenPurchasePolicy.values;
      for (final state in MotionParentalConsent.values) {
        final status = MotionAgeStatus(
          declaration: _born(2015, 1, 'US'),
          consent: state,
        );
        final open = state == MotionParentalConsent.approved;
        for (final policy in policies) {
          // Flag on: only an approved under-13 account may buy.
          expect(
            status.purchaseRestrictedOn(
              _today,
              policy,
              underThirteenConsent: true,
            ),
            !open,
            reason: '${state.name} / ${policy.name}',
          );
          expect(
            status.restrictedOn(_today, underThirteenConsent: true),
            !open,
            reason: state.name,
          );
          // Flag off (default): under 13 never buys, always restricted.
          expect(status.purchaseRestrictedOn(_today, policy), isTrue);
          expect(status.restrictedOn(_today), isTrue);
          // An under-13 account has no store-family-controls bypass.
          expect(
            status.storeDecidesPurchaseOn(
              _today,
              policy,
              underThirteenConsent: true,
            ),
            isFalse,
          );
        }
      }
    });

    test('a withdrawn approval closes a consent-required teen again', () {
      final teen = MotionAgeStatus(
        declaration: _born(2012, 9, 'DE'),
        consent: MotionParentalConsent.withdrawn,
      );
      expect(teen.restrictedOn(_today), isTrue);
      expect(
        teen.purchaseRestrictedOn(
          _today,
          MotionTeenPurchasePolicy.parentalConsentRequired,
        ),
        isTrue,
      );
    });
  });

  group('client: device consent', () {
    test('request sends token, parent address and locale only', () async {
      late Map<String, dynamic> sent;
      late String path;
      final client = _client((request) async {
        path = request.url.path;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(request, 200, {
          'status': 'pending',
          'expiresAt': '2026-11-23T10:00:00Z',
        });
      });
      final status = await client.requestDeviceConsent(
        deviceToken: _token,
        parentEmail: ' parent@example.invalid ',
        locale: 'tr',
      );
      expect(path, endsWith('/motion-parental-consent'));
      expect(sent, {
        'action': 'request_device',
        'deviceToken': _token,
        'parentEmail': 'parent@example.invalid',
        'locale': 'tr',
      });
      expect(status.state, MotionParentalConsent.pending);
      expect(status.verified, isTrue);
      expect(status.expiresAt, DateTime.utc(2026, 11, 23, 10));
      expect(status.allowsAccount, isFalse);
    });

    final refusals = <(int, String, MotionConsentRequestError)>[
      (429, 'too_soon', MotionConsentRequestError.tooSoon),
      (429, 'daily_limit', MotionConsentRequestError.dailyLimit),
      (
        400,
        'invalid_parent_email',
        MotionConsentRequestError.invalidParentEmail,
      ),
      (
        400,
        'invalid_device_token',
        MotionConsentRequestError.invalidDeviceToken,
      ),
      (409, 'already_approved', MotionConsentRequestError.alreadyApproved),
      (409, 'already_decided', MotionConsentRequestError.alreadyDecided),
      (503, 'mail_unavailable', MotionConsentRequestError.mailUnavailable),
    ];
    for (final (status, code, reason) in refusals) {
      test('$status $code maps to ${reason.name}', () async {
        final client = _client(
          (request) async => _json(request, status, {'error': code}),
        );
        await expectLater(
          client.requestDeviceConsent(
            deviceToken: _token,
            parentEmail: 'parent@example.invalid',
            locale: 'en',
          ),
          throwsA(
            isA<MotionConsentRequestRefused>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
      });
    }

    test(
      'server_unavailable is not a refusal reason: outcome unknown',
      () async {
        final client = _client(
          (request) async =>
              _json(request, 503, {'error': 'server_unavailable'}),
        );
        await expectLater(
          client.requestDeviceConsent(
            deviceToken: _token,
            parentEmail: 'parent@example.invalid',
            locale: 'en',
          ),
          throwsA(isA<MotionOperationUnknown>()),
        );
      },
    );

    test('a malformed token is refused locally, nothing is sent', () async {
      var calls = 0;
      final client = _client((request) async {
        calls++;
        return _json(request, 200, {'status': 'pending'});
      });
      await expectLater(
        client.requestDeviceConsent(
          deviceToken: 'short',
          parentEmail: 'parent@example.invalid',
          locale: 'en',
        ),
        throwsA(
          isA<MotionConsentRequestRefused>().having(
            (e) => e.reason,
            'reason',
            MotionConsentRequestError.invalidDeviceToken,
          ),
        ),
      );
      expect((await client.deviceConsentStatus('short')).verified, isFalse);
      expect(calls, 0);
    });

    test('a 200 that is not pending never grants', () async {
      final client = _client(
        (request) async => _json(request, 200, {'status': 'approved'}),
      );
      final status = await client.requestDeviceConsent(
        deviceToken: _token,
        parentEmail: 'parent@example.invalid',
        locale: 'en',
      );
      expect(status.verified, isFalse);
      expect(status.allowsAccount, isFalse);
    });

    test('status parses the five server states', () async {
      for (final state in const [
        'none',
        'pending',
        'approved',
        'denied',
        'expired',
      ]) {
        late Map<String, dynamic> sent;
        final client = _client((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(request, 200, {
            'status': state,
            'decidedAt': '2026-11-16T09:00:00Z',
          });
        });
        final status = await client.deviceConsentStatus(_token);
        expect(sent, {'action': 'status', 'deviceToken': _token});
        expect(status.state.name, state);
        expect(status.verified, isTrue);
        expect(status.decidedAt, DateTime.utc(2026, 11, 16, 9));
        expect(status.allowsAccount, state == 'approved');
      }
    });

    final failures = <String, Future<http.Response> Function(http.Request)>{
      'server error': (r) async =>
          _json(r, 500, {'error': 'server_unavailable'}),
      'rate limited': (r) async => _json(r, 429, {'error': 'too_soon'}),
      'broken json': (r) async => http.Response(
        '{not json',
        200,
        headers: {'content-type': 'application/json'},
        request: r,
      ),
      'not an object': (r) async => _json(r, 200, ['approved']),
      'unknown state': (r) async => _json(r, 200, {'status': 'granted'}),
      'withdrawn is not a device state': (r) async =>
          _json(r, 200, {'status': 'withdrawn'}),
      'missing state': (r) async => _json(r, 200, <String, dynamic>{}),
      'non-200 success code': (r) async =>
          _json(r, 202, {'status': 'approved'}),
      'network failure': (r) async => throw http.ClientException('offline'),
    };
    failures.forEach((name, handler) {
      test('fail-closed: $name is unavailable and never throws', () async {
        final status = await _client(handler).deviceConsentStatus(_token);
        expect(status.verified, isFalse);
        expect(status.state, MotionParentalConsent.none);
        expect(status.allowsAccount, isFalse);
      });
    });

    test('fail-closed: a stalled server times out as unavailable', () async {
      final never = Completer<http.Response>();
      final client = _client(
        (request) => never.future,
        readTimeout: const Duration(milliseconds: 50),
      );
      final status = await client.deviceConsentStatus(_token);
      expect(status.allowsAccount, isFalse);
      expect(status.verified, isFalse);
    });

    test('unavailable() is unverified and denies', () {
      const status = MotionDeviceConsentStatus.unavailable();
      expect(status.state, MotionParentalConsent.none);
      expect(status.verified, isFalse);
      expect(status.allowsAccount, isFalse);
      // Approved but unverified never allows an account either.
      const forged = MotionDeviceConsentStatus(
        state: MotionParentalConsent.approved,
        verified: false,
      );
      expect(forged.allowsAccount, isFalse);
    });

    test('under-13 sign-up carries the raw token inside motion_age', () async {
      Map<String, dynamic>? sent;
      final client = _client((request) async {
        if (request.url.path.endsWith('/signup')) {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
        }
        return _json(request, 200, {
          'id': '00000000-0000-4000-8000-000000000009',
          'aud': 'authenticated',
          'created_at': '2026-11-16T00:00:00Z',
          'app_metadata': <String, dynamic>{},
        });
      });
      await client.signUpUnderThirteen(
        email: 'child@example.invalid',
        password: 'long-enough',
        age: _born(2015, 1, 'US'),
        deviceConsentToken: _token,
      );
      expect(sent!['data'], {
        'motion_age': {
          'birth_year_month': '2015-01',
          'country': 'US',
          'policy_version': MotionAgePolicy.version,
          'device_consent_token': _token,
        },
      });
      expect(
        () => client.signUpUnderThirteen(
          email: 'child@example.invalid',
          password: 'long-enough',
          age: _born(2015, 1, 'US'),
          deviceConsentToken: 'bad',
        ),
        throwsArgumentError,
      );
      // A 44-char token with whitespace/newline: refused, value never echoed.
      final padded = ' $_token\n';
      Object? caught;
      try {
        await client.signUpUnderThirteen(
          email: 'child@example.invalid',
          password: 'long-enough',
          age: _born(2015, 1, 'US'),
          deviceConsentToken: padded,
        );
      } catch (error) {
        caught = error;
      }
      expect(padded.length, 45);
      expect(caught, isA<ArgumentError>());
      expect('$caught', isNot(contains(_token)));
      expect('$caught', isNot(contains('abcdefgh')));
      expect((caught as ArgumentError).invalidValue, isNull);
    });

    test('ageStatus parses withdrawn; unknown is no consent', () async {
      for (final (raw, expected) in [
        ('withdrawn', MotionParentalConsent.withdrawn),
        ('approved', MotionParentalConsent.approved),
        ('garbage', MotionParentalConsent.none),
      ]) {
        final client = _client((request) async {
          final path = request.url.path;
          if (path.endsWith('/token')) {
            return _json(request, 200, {
              'access_token': 'synthetic-access',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'synthetic-refresh',
              'user': {
                'id': '00000000-0000-4000-8000-000000000009',
                'aud': 'authenticated',
                'created_at': '2026-11-16T00:00:00Z',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            });
          }
          if (path.endsWith('motion_age_declarations')) {
            return _json(request, 200, {
              'birth_year_month': '2012-09',
              'country': 'DE',
              'policy_version': MotionAgePolicy.version,
            });
          }
          return _json(request, 200, {'status': raw});
        });
        await client.signIn(email: 'teen@example.invalid', password: 'x' * 12);
        final status = await client.ageStatus();
        expect(status.consent, expected, reason: raw);
        expect(
          status.restrictedOn(_today),
          expected != MotionParentalConsent.approved,
        );
      }
    });
  });

  test('MotionConsentRequestError keeps old indexes; new values are last', () {
    expect(MotionConsentRequestError.values.map((e) => e.name).toList(), [
      'invalidParentEmail',
      'parentEmailIsTeen',
      'notRequired',
      'alreadyApproved',
      'tooSoon',
      'dailyLimit',
      'mailUnavailable',
      'invalidDeviceToken',
      'alreadyDecided',
    ]);
  });

  group('page hand-off', () {
    testWidgets('flag true: under 13 calls onUnderThirteen only', (
      tester,
    ) async {
      final account = _PageAccount();
      var blocked = 0;
      var under13 = 0;
      await _pump(
        tester,
        account,
        enabled: true,
        onAgeBlocked: () => blocked++,
        onUnderThirteen: () => under13++,
      );
      await _openRegister(tester);
      await _chooseAge(tester, 2015, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump();
      expect(under13, 1);
      expect(blocked, 0);
      expect(account.signUps, 0);
      expect(find.text(_blockedText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flag false (default): today\'s permanent block', (
      tester,
    ) async {
      final account = _PageAccount();
      var blocked = 0;
      var under13 = 0;
      await _pump(
        tester,
        account,
        enabled: false,
        onAgeBlocked: () => blocked++,
        onUnderThirteen: () => under13++,
      );
      await _openRegister(tester);
      await _chooseAge(tester, 2015, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(blocked, 1);
      expect(under13, 0);
      expect(account.signUps, 0);
      expect(find.text(_blockedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flag true without onUnderThirteen keeps the block', (
      tester,
    ) async {
      final account = _PageAccount();
      var blocked = 0;
      await _pump(
        tester,
        account,
        enabled: true,
        onAgeBlocked: () => blocked++,
      );
      await _openRegister(tester);
      await _chooseAge(tester, 2015, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(blocked, 1);
      expect(account.signUps, 0);
      expect(find.text(_blockedText), findsOneWidget);
    });

    testWidgets('flag true: a 13+ sign-up is unchanged', (tester) async {
      final account = _PageAccount();
      var under13 = 0;
      await _pump(
        tester,
        account,
        enabled: true,
        onUnderThirteen: () => under13++,
      );
      await _openRegister(tester);
      await _chooseAge(tester, 1990, 3);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      await tester.pump();
      expect(under13, 0);
      expect(account.signUps, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

const _blockedText =
    "Sorry, you can't create a Motion account. Motion accounts are for "
    'people 13 and older.';

Future<void> _pump(
  WidgetTester tester,
  _PageAccount account, {
  required bool enabled,
  VoidCallback? onAgeBlocked,
  VoidCallback? onUnderThirteen,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        countryCode: 'DE',
        storefrontCountry: () async => null,
        storeAgeSignal: () async => null,
        clock: () => _today,
        onAgeBlocked: onAgeBlocked,
        underThirteenConsentEnabled: enabled,
        onUnderThirteen: onUnderThirteen,
        clearLocalData: (_) async {},
      ),
    ),
  );
}

Future<void> _openRegister(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Email'),
    'child@example.invalid',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Password'),
    'long-enough',
  );
  await tester.tap(find.text('Create a new account'));
  await tester.pump();
}

Future<void> _chooseAge(WidgetTester tester, int year, int month) async {
  await tester.tap(find.byKey(const ValueKey('motion-birth-year')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('$year').last,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('$year').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('motion-birth-month')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(month.toString().padLeft(2, '0')).last);
  await tester.pumpAndSettle();
}

class _PageAccount implements MotionAccountClient {
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  int signUps = 0;

  @override
  SupabaseClient get supabase => throw UnimplementedError();

  @override
  MotionApp get app => MotionApp.lissom;

  @override
  String get emailRedirectTo => 'com.yulalab.lissom://auth/callback';

  @override
  User? get currentUser => null;

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<AuthResponse> signUpWithAge({
    required String email,
    required String password,
    required MotionAgeDeclaration age,
  }) async {
    signUps++;
    return AuthResponse();
  }

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
