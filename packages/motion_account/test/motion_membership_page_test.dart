import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '11111111-1111-1111-1111-111111111111';

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

class _Store implements PurchaseAdapter {
  _Store(this.offers);

  final List<StoreProductRef> offers;
  int fetchCount = 0;
  StoreProductRef? purchased;

  @override
  Stream<StorePurchaseUpdate> get updates => const Stream.empty();

  @override
  Future<List<StoreProductRef>> fetchProducts(List<String> productIds) async {
    fetchCount++;
    expect(productIds, contains('ostinato_individual'));
    return offers;
  }

  @override
  Future<void> startPurchase(StoreProductRef offer) async {
    purchased = offer;
  }

  @override
  Future<void> restore() async {}

  @override
  Future<void> complete(StorePurchaseUpdate update) async {}
}

class _Server implements ServerAdapter {
  @override
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence) async =>
      null;
}

class _MembershipAccount extends MotionAccountClient {
  _MembershipAccount({
    required SupabaseClient client,
    required this.active,
    required this.anyActive,
  }) : super(
         supabase: client,
         app: MotionApp.ostinato,
         emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
       );

  bool active;
  bool anyActive;

  @override
  Future<bool> hasActiveMembership() async => active;

  @override
  Future<MotionMembershipStatus> membershipStatus() async =>
      MotionMembershipStatus(active: active, anyActive: anyActive);
}

Future<_MembershipAccount> _account(bool active, {bool? anyActive}) async {
  final client = SupabaseClient(
    'https://motion.example.invalid',
    'public-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(_session());
  return _MembershipAccount(
    client: client,
    active: active,
    anyActive: anyActive ?? active,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('membership check uses the current Motion token and app', () async {
    final client = SupabaseClient(
      'https://motion.example.invalid',
      'public-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/motion-check-membership'));
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer local-test-token',
        );
        expect((jsonDecode(request.body) as Map)['appId'], 'ostinato');
        return http.Response(
          '{"active":true,"anyActive":true}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(_session());
    final account = MotionAccountClient(
      supabase: client,
      app: MotionApp.ostinato,
      emailRedirectTo: 'com.yulalab.ostinato://auth/callback',
    );
    expect(await account.hasActiveMembership(), isTrue);
    expect((await account.membershipStatus()).anyActive, isTrue);
    client.dispose();
  });

  testWidgets('only a store-returned localized price is offered', (
    tester,
  ) async {
    final account = await _account(false);
    final store = _Store([
      const StoreProductRef(
        productId: 'ostinato_individual',
        platform: StorePlatform.android,
        planId: 'monthly',
        localizedPrice: '₺399,99',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        locale: const Locale('tr'),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MotionMembershipPage(
          account: account,
          purchaseAdapter: store,
          serverAdapter: _Server(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('₺399,99'), findsOneWidget);
    expect(find.text('Aylık'), findsOneWidget);
    expect(store.fetchCount, 1);
    account.supabase.dispose();
  });

  testWidgets('an existing membership hides duplicate sale offers', (
    tester,
  ) async {
    final account = await _account(true);
    final store = _Store(const []);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        locale: const Locale('en'),
        home: MotionMembershipPage(
          account: account,
          purchaseAdapter: store,
          serverAdapter: _Server(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your membership is active in this app.'), findsOneWidget);
    expect(find.text('Choose'), findsNothing);
    expect(store.fetchCount, 0);
    account.supabase.dispose();
  });

  testWidgets('another app membership permits this app but hides Motion+', (
    tester,
  ) async {
    final account = await _account(false, anyActive: true);
    final store = _Store(const [
      StoreProductRef(
        productId: 'ostinato_individual',
        platform: StorePlatform.android,
        planId: 'monthly',
        localizedPrice: '\$9.90',
      ),
      StoreProductRef(
        productId: 'ostinato_motion_plus',
        platform: StorePlatform.android,
        planId: 'monthly',
        localizedPrice: '\$30.00',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        locale: const Locale('en'),
        home: MotionMembershipPage(
          account: account,
          purchaseAdapter: store,
          serverAdapter: _Server(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('separate membership'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
    expect(find.text('\$9.90'), findsOneWidget);
    expect(find.text('\$30.00'), findsNothing);
    expect(store.fetchCount, 1);
    await tester.tap(find.text('Choose'));
    await tester.pump();
    expect(store.purchased?.productId, 'ostinato_individual');
    account.supabase.dispose();
  });

  testWidgets('Motion+ alone is still offered to an unsubscribed account', (
    tester,
  ) async {
    final account = await _account(false);
    final store = _Store(const [
      StoreProductRef(
        productId: 'ostinato_motion_plus',
        platform: StorePlatform.android,
        planId: 'monthly',
        localizedPrice: '\$30.00',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        locale: const Locale('en'),
        home: MotionMembershipPage(
          account: account,
          purchaseAdapter: store,
          serverAdapter: _Server(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Motion+'), findsOneWidget);
    expect(find.text('\$30.00'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
    account.supabase.dispose();
  });

  testWidgets('a newly active membership stops purchase before store opens', (
    tester,
  ) async {
    final account = await _account(false);
    final store = _Store(const [
      StoreProductRef(
        productId: 'ostinato_individual',
        platform: StorePlatform.android,
        planId: 'monthly',
        localizedPrice: '\$9.90',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        locale: const Locale('en'),
        home: MotionMembershipPage(
          account: account,
          purchaseAdapter: store,
          serverAdapter: _Server(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    account.active = true;
    account.anyActive = true;
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(store.purchased, isNull);
    expect(find.textContaining('Membership changed'), findsOneWidget);
    account.supabase.dispose();
  });
}
