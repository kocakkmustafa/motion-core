import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    as platform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// CORE-R3 K3: one Motion+ free trial per Motion account.
const _userId = '01234567-89ab-cdef-0123-456789abcdef';

class _Billing extends platform.InAppPurchasePlatform {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  List<ProductDetails> products = [];
  PurchaseParam? lastPurchase;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async =>
      ProductDetailsResponse(productDetails: products, notFoundIDs: const []);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    lastPurchase = purchaseParam;
    return true;
  }
}

class _Gate implements MotionTrialGate {
  _Gate({this.available = true, this.denial, this.fails = false});

  final bool available;
  final String? denial;
  final bool fails;
  int availabilityChecks = 0;
  final denialRequests = <String>[];

  @override
  Future<bool> motionPlusTrialAvailable() async {
    availabilityChecks++;
    if (fails) throw StateError('network');
    return available;
  }

  @override
  Future<String?> appleIntroductoryOfferDenial(String productId) async {
    denialRequests.add(productId);
    if (fails) throw StateError('network');
    return denial;
  }
}

PricingPhaseWrapper _phase(
  String period,
  int micros,
  String price, {
  int cycles = 0,
  RecurrenceMode mode = RecurrenceMode.infiniteRecurring,
}) => PricingPhaseWrapper(
  billingCycleCount: cycles,
  billingPeriod: period,
  formattedPrice: price,
  priceAmountMicros: micros,
  priceCurrencyCode: 'USD',
  recurrenceMode: mode,
);

List<ProductDetails> _play(String productId) =>
    GooglePlayProductDetails.fromProductDetails(
      ProductDetailsWrapper(
        description: 'Membership',
        name: 'Membership',
        productId: productId,
        productType: ProductType.subs,
        title: 'Membership',
        subscriptionOfferDetails: [
          SubscriptionOfferDetailsWrapper(
            basePlanId: 'monthly',
            offerTags: const [],
            offerIdToken: 'base-month',
            pricingPhases: [_phase('P1M', 19990000, r'$19.99')],
          ),
          SubscriptionOfferDetailsWrapper(
            basePlanId: 'monthly',
            offerId: 'free-trial',
            offerTags: const ['motion-plus-trial'],
            offerIdToken: 'trial-month',
            pricingPhases: [
              _phase(
                'P14D',
                0,
                'Free',
                cycles: 1,
                mode: RecurrenceMode.finiteRecurring,
              ),
              _phase('P1M', 19990000, r'$19.99'),
            ],
          ),
        ],
      ),
    );

ProductDetails _apple(String id) => AppStoreProduct2Details.fromSK2Product(
  SK2Product(
    id: id,
    displayName: 'Membership',
    displayPrice: r'$19.99',
    description: 'Membership',
    price: 19.99,
    type: SK2ProductType.autoRenewable,
    priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
    subscription: SK2SubscriptionInfo(
      subscriptionGroupID: 'group',
      promotionalOffers: [
        SK2SubscriptionOffer(
          price: 0,
          type: SK2SubscriptionOfferType.introductory,
          period: SK2SubscriptionPeriod(
            value: 2,
            unit: SK2SubscriptionPeriodUnit.week,
          ),
          periodCount: 1,
          paymentMode: SK2SubscriptionOfferPaymentMode.freeTrial,
        ),
      ],
      subscriptionPeriod: SK2SubscriptionPeriod(
        value: 1,
        unit: SK2SubscriptionPeriodUnit.month,
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  InAppPurchase.instance;
  debugDefaultTargetPlatformOverride = null;
  late _Billing billing;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    billing = _Billing();
    platform.InAppPurchasePlatform.instance = billing;
  });

  tearDown(() async {
    await billing.events.close();
    debugDefaultTargetPlatformOverride = null;
  });

  FlutterPurchaseAdapter adapter(MotionTrialGate? gate) =>
      FlutterPurchaseAdapter(
        appId: 'app',
        currentUserId: () => _userId,
        introductoryOfferEligible: (_) async => true,
        trialGate: gate,
      );

  test('Motion+ product naming', () {
    expect(FlutterPurchaseAdapter.isMotionPlusProduct('app_motion_plus'), true);
    expect(
      FlutterPurchaseAdapter.isMotionPlusProduct(
        'com.yulalab.app.motionplus.yearly',
      ),
      true,
    );
    expect(FlutterPurchaseAdapter.isMotionPlusProduct('app_individual'), false);
    expect(
      FlutterPurchaseAdapter.isMotionPlusProduct(
        'com.yulalab.app.individual.yearly',
      ),
      false,
    );
  });

  group('Google Play Motion+', () {
    test('a used trial is neither shown nor bought', () async {
      billing.products = _play('app_motion_plus');
      final gate = _Gate(available: false);
      final offers = await adapter(gate).fetchProducts(['app_motion_plus']);
      expect(offers.single.freeTrialPeriod, isNull);
      expect(gate.availabilityChecks, 1);
    });

    test(
      'an unused trial is shown and bought through the trial offer',
      () async {
        billing.products = _play('app_motion_plus');
        final a = adapter(_Gate());
        final offers = await a.fetchProducts(['app_motion_plus']);
        expect(offers.single.freeTrialPeriod, 'P14D');
        await a.startPurchase(offers.single);
        expect(
          (billing.lastPurchase! as GooglePlayPurchaseParam).offerToken,
          'trial-month',
        );
      },
    );

    test('an unknown answer claims and buys no trial', () async {
      billing.products = _play('app_motion_plus');
      final a = adapter(_Gate(fails: true));
      final offers = await a.fetchProducts(['app_motion_plus']);
      expect(offers.single.freeTrialPeriod, isNull);
      await a.startPurchase(offers.single);
      expect(
        (billing.lastPurchase! as GooglePlayPurchaseParam).offerToken,
        'base-month',
      );
    });

    test('the individual plan is never gated', () async {
      billing.products = _play('app_individual');
      final gate = _Gate(available: false);
      final offers = await adapter(gate).fetchProducts(['app_individual']);
      expect(offers.single.freeTrialPeriod, 'P14D');
      expect(gate.availabilityChecks, 0);
    });
  });

  group('App Store Motion+', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    const id = 'com.yulalab.app.motionplus.monthly';

    test('a used trial buys with the signed eligibility denial', () async {
      billing.products = [_apple(id)];
      final gate = _Gate(available: false, denial: 'signed.denial.jws');
      final a = adapter(gate);
      final offers = await a.fetchProducts([id]);
      expect(offers.single.freeTrialPeriod, isNull);
      await a.startPurchase(offers.single);
      final param = billing.lastPurchase! as Sk2PurchaseParam;
      expect(param.introductoryOfferEligibilityCompactJWS, 'signed.denial.jws');
      expect(param.applicationUserName, _userId);
      expect(gate.denialRequests, [id]);
    });

    test('without a denial Apple decides (no JWS, no trial claim)', () async {
      billing.products = [_apple(id)];
      for (final gate in [_Gate(available: false), _Gate(fails: true)]) {
        final a = adapter(gate);
        final offers = await a.fetchProducts([id]);
        expect(offers.single.freeTrialPeriod, isNull);
        await a.startPurchase(offers.single);
        expect(billing.lastPurchase, isNot(isA<Sk2PurchaseParam>()));
      }
    });

    test('an unused trial is claimed and bought normally', () async {
      billing.products = [_apple(id)];
      final gate = _Gate();
      final a = adapter(gate);
      final offers = await a.fetchProducts([id]);
      expect(offers.single.freeTrialPeriod, 'P14D');
      await a.startPurchase(offers.single);
      expect(billing.lastPurchase, isNot(isA<Sk2PurchaseParam>()));
      expect(gate.denialRequests, isEmpty);
    });
  });

  group('SupabaseMotionTrialGate', () {
    Future<SupabaseClient> client(
      Future<http.Response> Function(http.Request) handler,
    ) async {
      final c = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        httpClient: MockClient(handler),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await c.auth.setInitialSession(
        jsonEncode({
          'access_token': 'local-test-token',
          'token_type': 'bearer',
          'user': {
            'id': _userId,
            'aud': 'authenticated',
            'created_at': '2026-09-24T00:00:00Z',
            'app_metadata': <String, dynamic>{},
          },
        }),
      );
      return c;
    }

    test('the own ledger row decides availability', () async {
      for (final (status, body, expected) in [
        (200, '[]', true),
        (200, '[{"user_id":"$_userId"}]', false),
        (500, '{"message":"down"}', false),
      ]) {
        final requests = <Uri>[];
        final c = await client((request) async {
          requests.add(request.url);
          return http.Response(
            body,
            status,
            headers: {'content-type': 'application/json'},
          );
        });
        final gate = SupabaseMotionTrialGate(
          supabase: c,
          appId: 'app',
          appTransactionId: () async => null,
        );
        expect(await gate.motionPlusTrialAvailable(), expected, reason: body);
        expect(requests.single.path, '/rest/v1/motion_trial_ledger');
        await c.dispose();
      }
    });

    test('the denial needs an app transaction ID and a used trial', () async {
      final bodies = <Map<String, dynamic>>[];
      final c = await client((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        expect(request.url.path, '/functions/v1/motion-offer-eligibility');
        expect(request.headers['Authorization'], 'Bearer local-test-token');
        return http.Response(
          jsonEncode({
            'trialAvailable': false,
            'introductoryOfferEligibilityJws': 'signed.denial.jws',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final withId = SupabaseMotionTrialGate(
        supabase: c,
        appId: 'app',
        appTransactionId: () async => '704289572311429985',
      );
      expect(
        await withId.appleIntroductoryOfferDenial(
          'com.yulalab.app.motionplus.monthly',
        ),
        'signed.denial.jws',
      );
      expect(bodies.single, {
        'appId': 'app',
        'productId': 'com.yulalab.app.motionplus.monthly',
        'appTransactionId': '704289572311429985',
      });
      final withoutId = SupabaseMotionTrialGate(
        supabase: c,
        appId: 'app',
        appTransactionId: () async => null,
      );
      expect(
        await withoutId.appleIntroductoryOfferDenial(
          'com.yulalab.app.motionplus.monthly',
        ),
        isNull,
      );
      expect(bodies, hasLength(1));
      await c.dispose();
    });
  });
}
