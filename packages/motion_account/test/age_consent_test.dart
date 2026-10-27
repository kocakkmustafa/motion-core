// 13+ age policy, neutral sign-up age screen and parental consent surfaces.
// Synthetic data only; the SQL parity check reads the migration source.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _today = DateTime(2026, 10, 21);

MotionAgeDeclaration _born(int year, int month, String? country) =>
    MotionAgeDeclaration(
      birthYear: year,
      birthMonth: month,
      countryCode: country,
      policyVersion: MotionAgePolicy.version,
    );

MotionAgeBand _band(int year, int month, String? country) =>
    MotionAgePolicy.bandFor(_born(year, month, country), today: _today);

void main() {
  group('policy', () {
    test('under 13 is blocked everywhere, including the US', () {
      for (final country in ['US', 'GB', 'DE', 'TR', null]) {
        expect(_band(2014, 1, country), MotionAgeBand.blocked);
      }
    });

    test('the birth month counts as birthday not yet reached', () {
      // Born October 2013: 13 only from November 2026 on this conservative rule.
      expect(MotionAgePolicy.ageOn(2013, 10, _today), 12);
      expect(_band(2013, 10, 'US'), MotionAgeBand.blocked);
      expect(_band(2013, 9, 'US'), MotionAgeBand.teen);
    });

    test('country consent ages split consent-required and teen', () {
      // 14 years old (born Sep 2012).
      expect(_band(2012, 9, 'US'), MotionAgeBand.teen);
      expect(_band(2012, 9, 'GB'), MotionAgeBand.teen);
      expect(_band(2012, 9, 'ES'), MotionAgeBand.teen);
      expect(_band(2012, 9, 'FR'), MotionAgeBand.parentalConsentRequired);
      expect(_band(2012, 9, 'DE'), MotionAgeBand.parentalConsentRequired);
      expect(_band(2012, 9, 'KR'), MotionAgeBand.teen);
      // 16: Germany opens, India/Turkey still need a guardian.
      expect(_band(2010, 9, 'DE'), MotionAgeBand.teen);
      expect(_band(2010, 9, 'IN'), MotionAgeBand.parentalConsentRequired);
      expect(_band(2010, 9, 'TR'), MotionAgeBand.parentalConsentRequired);
      // Unknown region uses the strictest GDPR value (16).
      expect(_band(2011, 9, null), MotionAgeBand.parentalConsentRequired);
      expect(_band(2010, 9, 'ZZ'), MotionAgeBand.teen);
      expect(_band(2008, 9, 'IN'), MotionAgeBand.adult);
    });

    test('teen purchase policy differs only for a consent-pending teen', () {
      const consent = MotionTeenPurchasePolicy.parentalConsentRequired;
      const store = MotionTeenPurchasePolicy.storeFamilyControls;
      MotionAgeStatus status(
        int year,
        String country,
        MotionParentalConsent c,
      ) => MotionAgeStatus(declaration: _born(year, 9, country), consent: c);
      // (status, restricted under consent, restricted under store, store note)
      final cases = <(MotionAgeStatus, bool, bool, bool)>[
        (status(2012, 'DE', MotionParentalConsent.none), true, false, true),
        (status(2012, 'DE', MotionParentalConsent.pending), true, false, true),
        (status(2012, 'DE', MotionParentalConsent.denied), true, false, true),
        (status(2012, 'DE', MotionParentalConsent.expired), true, false, true),
        (
          status(2012, 'DE', MotionParentalConsent.approved),
          false,
          false,
          false,
        ),
        (status(2012, 'US', MotionParentalConsent.none), false, false, false),
        (status(1990, 'TR', MotionParentalConsent.none), false, false, false),
        // An under-13 band never buys, whatever the host chose.
        (status(2014, 'US', MotionParentalConsent.none), true, true, false),
      ];
      for (final (age, underConsent, underStore, note) in cases) {
        expect(age.purchaseRestrictedOn(_today, consent), underConsent);
        expect(age.purchaseRestrictedOn(_today, store), underStore);
        expect(age.storeDecidesPurchaseOn(_today, store), note);
        expect(age.storeDecidesPurchaseOn(_today, consent), isFalse);
      }
      const undeclared = MotionAgeStatus(
        declaration: null,
        consent: MotionParentalConsent.none,
      );
      expect(undeclared.purchaseRestrictedOn(_today, consent), isFalse);
      expect(undeclared.storeDecidesPurchaseOn(_today, store), isFalse);
    });

    test('teens get no marketing and opt-in analytics only', () {
      for (final band in MotionAgeBand.values) {
        expect(
          MotionAgePolicy.marketingAllowed(band),
          band == MotionAgeBand.adult,
        );
        expect(
          MotionAgePolicy.analyticsNeedsOptIn(band),
          band != MotionAgeBand.adult,
        );
      }
    });

    test('declaration JSON carries only YYYY-MM, country and version', () {
      final json = _born(2011, 3, 'DE').toJson();
      expect(json, {
        'birth_year_month': '2011-03',
        'country': 'DE',
        'policy_version': MotionAgePolicy.version,
      });
      final back = MotionAgeDeclaration.fromJson(json)!;
      expect(back.birthYearMonth, '2011-03');
      expect(back.countryCode, 'DE');
      for (final bad in [
        {'birth_year_month': '2011-13', 'policy_version': 'v'},
        {'birth_year_month': '2011-3', 'policy_version': 'v'},
        {'birth_year_month': '2011-03', 'country': 'de', 'policy_version': 'v'},
        {'birth_year_month': '2011-03'},
        'not a map',
      ]) {
        expect(MotionAgeDeclaration.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('the SQL consent-age table matches the Dart table exactly', () {
      final sql = File(
        '../../supabase/migrations/20261021190000_motion_age_consent_retention.sql',
      ).readAsStringSync();
      final pairs = RegExp(r"when '([A-Z]{2})' then (\d+)").allMatches(sql);
      final fromSql = {
        for (final match in pairs) match.group(1)!: int.parse(match.group(2)!),
      };
      expect(fromSql, {
        for (final entry in MotionAgePolicy.rules.entries)
          entry.key: entry.value.consentAge,
      });
      expect(
        RegExp(r'else (\d+)\s+end;').firstMatch(sql)!.group(1),
        '${MotionAgePolicy.defaultRule.consentAge}',
      );
      expect(sql, contains('< 13'));
      expect(sql, contains('< 18'));
    });
  });

  group('client', () {
    test('sign-up sends the declaration as metadata, nothing more', () async {
      Map<String, dynamic>? sent;
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/signup')) {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response(
            jsonEncode({
              'id': '00000000-0000-4000-8000-000000000009',
              'aud': 'authenticated',
              'created_at': '2026-10-21T00:00:00Z',
              'app_metadata': <String, dynamic>{},
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await MotionAccountClient(
        supabase: client,
        app: MotionApp.lissom,
        emailRedirectTo: 'com.yulalab.lissom://auth/callback',
      ).signUpWithAge(
        email: 'teen@example.invalid',
        password: 'long-enough',
        age: _born(2011, 3, 'DE'),
      );
      expect(sent!['data'], {
        'motion_age': {
          'birth_year_month': '2011-03',
          'country': 'DE',
          'policy_version': MotionAgePolicy.version,
        },
      });
    });

    test('a runtime-built client exposes its receipt probe to wrappers', () {
      final client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.dispose);
      final runtime = MotionAccountRuntime.forTesting(
        client: client,
        app: MotionApp.gravita,
        onDeletedAccount: (_) async {},
      );
      addTearDown(runtime.dispose);
      expect(runtime.account.deletionReceipt, isNotNull);
      expect(
        MotionAccountClient(
          supabase: client,
          app: MotionApp.gravita,
          emailRedirectTo: 'com.yulalab.gravita://auth/callback',
        ).deletionReceipt,
        isNull,
      );
    });

    test('status restriction follows band and approval', () {
      final teen = _born(2012, 9, 'DE');
      expect(
        const MotionAgeStatus(
          declaration: null,
          consent: MotionParentalConsent.none,
        ).restrictedOn(_today),
        isFalse,
      );
      for (final consent in MotionParentalConsent.values) {
        expect(
          MotionAgeStatus(
            declaration: teen,
            consent: consent,
          ).restrictedOn(_today),
          consent != MotionParentalConsent.approved,
        );
      }
      expect(
        MotionAgeStatus(
          declaration: _born(2010, 9, 'DE'),
          consent: MotionParentalConsent.none,
        ).restrictedOn(_today),
        isFalse,
      );
    });
  });

  group('page', () {
    testWidgets('sign-up requires an age first and sends it', (tester) async {
      final account = _AgeAccount(userId: null);
      await _pump(tester, account);
      await _openRegister(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(
        find.text('Choose your birth month and year first.'),
        findsOneWidget,
      );
      expect(account.signUps, isEmpty);

      await _chooseAge(tester, 2011, 3);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(account.signUps.single.birthYearMonth, '2011-03');
      expect(account.signUps.single.countryCode, 'DE');
      expect(tester.takeException(), isNull);
    });

    for (final (label, explicit, store, device, expected) in [
      ('store region wins over device', null, 'TUR', 'US', 'TR'),
      ('explicit override wins over store', 'gb', 'TUR', 'US', 'GB'),
      ('device region when the store is unknown', null, null, 'FR', 'FR'),
      ('unknown everywhere stays null', null, null, null, null),
    ]) {
      testWidgets('country source: $label', (tester) async {
        tester.platformDispatcher.localeTestValue = Locale('en', device);
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        var storeReads = 0;
        final account = _AgeAccount(userId: null);
        await _pump(
          tester,
          account,
          countryCode: explicit,
          storefront: () async {
            storeReads++;
            return store;
          },
        );
        await _openRegister(tester);
        await _chooseAge(tester, 2011, 3);
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pump();
        await tester.pump();
        expect(account.signUps.single.countryCode, expected);
        expect(storeReads, explicit == null ? 1 : 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('under 13 creates nothing and stays blocked', (tester) async {
      final account = _AgeAccount(userId: null);
      var blocked = 0;
      await _pump(tester, account, onAgeBlocked: () => blocked++);
      await _openRegister(tester);
      await _chooseAge(tester, 2015, 1);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(
        find.text(
          "Sorry, you can't create a Motion account. Motion accounts are for people 13 and older.",
        ),
        findsOneWidget,
      );
      expect(blocked, 1);
      expect(account.signUps, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create account'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    group('store age signal (Declared Age Range / Play Age Signals)', () {
      MotionStoreAgeSignal signal(
        int? lower,
        int? upper, {
        bool shared = true,
      }) => MotionStoreAgeSignal(
        source: 'apple',
        shared: shared,
        lower: lower,
        upper: upper,
      );

      test('a store range only tightens the declared age', () {
        final cases = <(int, MotionStoreAgeSignal?, MotionStoreAgeCheck)>[
          (30, null, MotionStoreAgeCheck.proceed),
          (30, signal(null, null, shared: false), MotionStoreAgeCheck.proceed),
          (30, signal(18, null), MotionStoreAgeCheck.proceed),
          (14, signal(18, null), MotionStoreAgeCheck.proceed),
          (14, signal(13, 15), MotionStoreAgeCheck.proceed),
          (16, signal(13, 15), MotionStoreAgeCheck.mismatch),
          (30, signal(16, 17), MotionStoreAgeCheck.mismatch),
          (30, signal(null, 12), MotionStoreAgeCheck.under13),
          (14, signal(0, 12), MotionStoreAgeCheck.under13),
        ];
        for (final (age, store, expected) in cases) {
          expect(
            MotionAgePolicy.storeCheck(age, store),
            expected,
            reason: '$age vs ${store?.lower}-${store?.upper}',
          );
        }
      });

      testWidgets('a store range under 13 blocks sign-up permanently', (
        tester,
      ) async {
        final account = _AgeAccount(userId: null);
        var blocked = 0;
        await _pump(
          tester,
          account,
          onAgeBlocked: () => blocked++,
          storeAge: () async => signal(null, 12),
        );
        await _openRegister(tester);
        await _chooseAge(tester, 1990, 3);
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pump();
        await tester.pump();
        expect(account.signUps, isEmpty);
        expect(blocked, 1);
        expect(find.text(_blockedText), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an older declaration than the store range is refused', (
        tester,
      ) async {
        final account = _AgeAccount(userId: null);
        var reads = 0;
        await _pump(
          tester,
          account,
          storeAge: () async {
            reads++;
            return signal(13, 15);
          },
        );
        await _openRegister(tester);
        await _chooseAge(tester, 1990, 3);
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pump();
        await tester.pump();
        expect(account.signUps, isEmpty);
        expect(
          find.text(
            "This birth date doesn't match the age range shared by your store "
            'account. Check your birth month and year.',
          ),
          findsOneWidget,
        );

        // A second attempt reuses the page's one store read.
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pump();
        await tester.pump();
        expect(account.signUps, isEmpty);
        expect(reads, 1);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a declaration inside the store range proceeds', (
        tester,
      ) async {
        final account = _AgeAccount(userId: null);
        await _pump(tester, account, storeAge: () async => signal(13, 15));
        await _openRegister(tester);
        await _chooseAge(tester, 2011, 3);
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await tester.pump();
        await tester.pump();
        expect(account.signUps.single.birthYearMonth, '2011-03');
        expect(tester.takeException(), isNull);
      });

      testWidgets('no store signal keeps the declaration flow', (tester) async {
        for (final store in <MotionStoreAgeSignal?>[
          null,
          signal(null, null, shared: false),
        ]) {
          final account = _AgeAccount(userId: null);
          await _pump(tester, account, storeAge: () async => store);
          await _openRegister(tester);
          await _chooseAge(tester, 1990, 3);
          await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
          await tester.pump();
          await tester.pump();
          expect(account.signUps.single.birthYearMonth, '1990-03');
          await tester.pumpWidget(const SizedBox.shrink());
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a host-persisted block keeps sign-up closed', (tester) async {
      final account = _AgeAccount(userId: null);
      await _pump(tester, account, ageBlocked: true);
      await _openRegister(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create account'),
            )
            .onPressed,
        isNull,
      );
      // The reason is shown on reopening too (Lissom LIS-01 report), once.
      expect(find.text(_blockedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('consent-pending teen sees the request form; profile save is '
        'closed', (tester) async {
      final account = _AgeAccount(
        userId: 'teen-a',
        status: MotionAgeStatus(
          declaration: _born(2012, 9, 'DE'),
          consent: MotionParentalConsent.none,
        ),
      );
      await _pump(tester, account);
      await tester.pump();
      expect(
        find.text(
          'A parent or guardian needs to approve this account before account features open. Practice on this device keeps working.',
        ),
        findsOneWidget,
      );
      await tester.enterText(_displayName, 'Teen');
      await tester.pump();
      expect(_saveProfile(tester).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Parent or guardian email'),
        'parent@example.invalid',
      );
      await tester.tap(find.text('Send approval request'));
      await tester.pump();
      expect(account.consentRequests.single, ('parent@example.invalid', 'en'));
      account.status = MotionAgeStatus(
        declaration: _born(2012, 9, 'DE'),
        consent: MotionParentalConsent.pending,
      );
      account.consentReply.single.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Approval request sent. Ask your parent or guardian to check their email. The link works for 7 days.',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rate-limited request is explained, not retried', (
      tester,
    ) async {
      final account = _AgeAccount(
        userId: 'teen-a',
        status: MotionAgeStatus(
          declaration: _born(2012, 9, 'DE'),
          consent: MotionParentalConsent.pending,
        ),
      );
      await _pump(tester, account);
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Parent or guardian email'),
        'parent@example.invalid',
      );
      await tester.tap(find.text('Send approval request'));
      await tester.pump();
      account.consentReply.single.completeError(
        const MotionConsentRequestRefused(MotionConsentRequestError.tooSoon),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'A request was sent recently. Wait a few minutes before sending another.',
        ),
        findsOneWidget,
      );
      expect(account.consentRequests, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an undeclared legacy account confirms its age once', (
      tester,
    ) async {
      final account = _AgeAccount(
        userId: 'legacy-a',
        status: const MotionAgeStatus(
          declaration: null,
          consent: MotionParentalConsent.none,
        ),
      );
      await _pump(tester, account);
      await tester.pump();
      expect(
        find.text(
          'Confirm your birth month and year to keep using your Motion account.',
        ),
        findsOneWidget,
      );
      await _chooseAge(tester, 1990, 5);
      await tester.tap(find.text('Confirm age'));
      await tester.pump();
      expect(account.declarations.single.birthYearMonth, '1990-05');
      expect(tester.takeException(), isNull);
    });

    testWidgets('deletion dialog explains other apps and offline devices', (
      tester,
    ) async {
      final account = _AgeAccount(userId: 'adult-a');
      await _pump(tester, account);
      await tester.tap(find.text('Delete Motion account'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Other Motion apps and devices remove this account's history the next time they open online.",
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Finder get _displayName => find.widgetWithText(TextField, 'Display name');

FilledButton _saveProfile(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Save profile'),
);

Future<void> _pump(
  WidgetTester tester,
  _AgeAccount account, {
  VoidCallback? onAgeBlocked,
  bool ageBlocked = false,
  String? countryCode = 'DE',
  Future<String?> Function()? storefront,
  Future<MotionStoreAgeSignal?> Function()? storeAge,
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
        countryCode: countryCode,
        storefrontCountry: storefront ?? () async => null,
        storeAgeSignal: storeAge ?? () async => null,
        clock: () => _today,
        ageBlocked: ageBlocked,
        onAgeBlocked: onAgeBlocked,
        clearLocalData: (_) async {},
      ),
    ),
  );
}

Future<void> _openRegister(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Email'),
    'teen@example.invalid',
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

class _AgeAccount implements MotionAccountClient {
  _AgeAccount({required String? userId, this.status}) : _userId = userId;

  final _changes = StreamController<AuthState>.broadcast(sync: true);
  final String? _userId;
  MotionAgeStatus? status;
  final signUps = <MotionAgeDeclaration>[];
  final declarations = <MotionAgeDeclaration>[];
  final consentRequests = <(String, String)>[];
  final consentReply = <Completer<void>>[];

  @override
  SupabaseClient get supabase => const _Supabase();

  @override
  MotionApp get app => MotionApp.lissom;

  @override
  String get emailRedirectTo => 'com.yulalab.lissom://auth/callback';

  @override
  User? get currentUser => _userId == null
      ? null
      : User(
          id: _userId,
          appMetadata: const {},
          userMetadata: null,
          aud: 'authenticated',
          createdAt: '2026-10-21T00:00:00Z',
          email: '$_userId@example.invalid',
        );

  @override
  Stream<AuthState> get authChanges => _changes.stream;

  @override
  Future<Map<String, dynamic>?> loadProfile() async => {'display_name': ''};

  @override
  Future<MotionAgeStatus> ageStatus() async =>
      status ?? (throw StateError('no status fixture'));

  @override
  Future<AuthResponse> signUpWithAge({
    required String email,
    required String password,
    required MotionAgeDeclaration age,
  }) async {
    signUps.add(age);
    return AuthResponse();
  }

  @override
  Future<MotionAgeBand> recordAgeDeclaration(
    MotionAgeDeclaration declaration,
  ) async {
    declarations.add(declaration);
    return MotionAgeBand.adult;
  }

  @override
  Future<void> requestParentalConsent({
    required String parentEmail,
    required String locale,
  }) {
    consentRequests.add((parentEmail, locale));
    final reply = Completer<void>();
    consentReply.add(reply);
    return reply.future;
  }

  Future<void> dispose() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Supabase implements SupabaseClient {
  const _Supabase();

  @override
  GoTrueClient get auth => const _Auth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements GoTrueClient {
  const _Auth();

  @override
  Session? get currentSession => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _blockedText =
    "Sorry, you can't create a Motion account. Motion accounts are for "
    'people 13 and older.';
