import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    as platform;
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

// CORE-03: a free trial is shown and bought only when the store offers it to
// this user. Play sells the trial as a separate offer; StoreKit 2 lists the
// introductory offer and answers eligibility separately.
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

SubscriptionOfferDetailsWrapper _offer(
  String basePlan,
  String token,
  List<PricingPhaseWrapper> phases, {
  String? offerId,
}) => SubscriptionOfferDetailsWrapper(
  basePlanId: basePlan,
  offerId: offerId,
  offerTags: const [],
  offerIdToken: token,
  pricingPhases: phases,
);

PricingPhaseWrapper _free(String period, {int cycles = 1}) => _phase(
  period,
  0,
  'Free',
  cycles: cycles,
  mode: RecurrenceMode.finiteRecurring,
);

final _monthly = _phase('P1M', 11990000, r'$11.99');
final _yearly = _phase('P1Y', 69990000, r'$69.99');

SK2Product _sk2(String id, List<SK2SubscriptionOffer> offers) => SK2Product(
  id: id,
  displayName: 'Membership',
  displayPrice: r'$11.99',
  description: 'Membership',
  price: 11.99,
  type: SK2ProductType.autoRenewable,
  priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
  subscription: SK2SubscriptionInfo(
    subscriptionGroupID: 'group',
    promotionalOffers: offers,
    subscriptionPeriod: SK2SubscriptionPeriod(
      value: 1,
      unit: SK2SubscriptionPeriodUnit.month,
    ),
  ),
);

SK2SubscriptionOffer _intro(
  int value,
  SK2SubscriptionPeriodUnit unit, {
  SK2SubscriptionOfferPaymentMode mode =
      SK2SubscriptionOfferPaymentMode.freeTrial,
  SK2SubscriptionOfferType type = SK2SubscriptionOfferType.introductory,
}) => SK2SubscriptionOffer(
  price: 0,
  type: type,
  period: SK2SubscriptionPeriod(value: value, unit: unit),
  periodCount: 1,
  paymentMode: mode,
);

void main() {
  const userId = '01234567-89ab-cdef-0123-456789abcdef';
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

  test('store periods normalise to ISO-8601 days', () {
    expect(motionStorePeriod('P14D'), 'P14D');
    expect(motionStorePeriod('P2W'), 'P14D');
    expect(motionStorePeriod('P1W', count: 2), 'P14D');
    expect(motionStorePeriod('P1M'), 'P1M');
    expect(motionStorePeriod('P1Y', count: 2), 'P2Y');
    expect(motionStorePeriod('14 days'), isNull);
    expect(motionStorePeriod('P0D'), isNull);
    expect(motionStorePeriod('P14D', count: 0), isNull);
    const ref = StoreProductRef(
      productId: 'p',
      platform: StorePlatform.android,
      planId: 'monthly',
      localizedPrice: r'$11.99',
      freeTrialPeriod: 'P14D',
    );
    expect(ref.freeTrialDays, 14);
    expect(
      const StoreProductRef(
        productId: 'p',
        platform: StorePlatform.ios,
        planId: 'monthly',
        localizedPrice: r'$11.99',
        freeTrialPeriod: 'P1M',
      ).freeTrialDays,
      isNull,
    );
  });

  group('Google Play', () {
    test(
      'a free-trial offer attaches to its base plan and is bought',
      () async {
        billing.products = GooglePlayProductDetails.fromProductDetails(
          ProductDetailsWrapper(
            description: 'Membership',
            name: 'Membership',
            productId: 'app_individual',
            productType: ProductType.subs,
            title: 'Membership',
            subscriptionOfferDetails: [
              _offer('monthly', 'base-month', [_monthly]),
              _offer('yearly', 'base-year', [_yearly]),
              _offer('monthly', 'trial-month', [
                _free('P2W'),
                _monthly,
              ], offerId: 'free-trial'),
              // A paid introductory price is not a free trial and is not sold.
              _offer('yearly', 'paid-intro', [
                _phase(
                  'P1M',
                  990000,
                  r'$0.99',
                  cycles: 1,
                  mode: RecurrenceMode.finiteRecurring,
                ),
                _yearly,
              ], offerId: 'intro-price'),
            ],
          ),
        );
        final adapter = FlutterPurchaseAdapter(
          appId: 'app',
          currentUserId: () => userId,
        );

        final offers = await adapter.fetchProducts(['app_individual']);
        expect(offers.map((offer) => offer.planId), ['monthly', 'yearly']);
        expect(offers.map((offer) => offer.localizedPrice), [
          r'$11.99',
          r'$69.99',
        ]);
        expect(offers.map((offer) => offer.freeTrialPeriod), ['P14D', null]);

        await adapter.startPurchase(offers.first);
        final monthly = billing.lastPurchase! as GooglePlayPurchaseParam;
        expect(monthly.offerToken, 'trial-month');
        expect(
          (monthly.productDetails as GooglePlayProductDetails)
              .productDetails
              .productId,
          'app_individual',
        );

        await adapter.startPurchase(offers.last);
        expect(
          (billing.lastPurchase! as GooglePlayPurchaseParam).offerToken,
          'base-year',
        );
      },
    );

    test(
      'a two-week trial billed as two weekly cycles reads as 14 days',
      () async {
        billing.products = GooglePlayProductDetails.fromProductDetails(
          ProductDetailsWrapper(
            description: 'Membership',
            name: 'Membership',
            productId: 'app_motion_plus',
            productType: ProductType.subs,
            title: 'Membership',
            subscriptionOfferDetails: [
              _offer('yearly', 'base-year', [_yearly]),
              _offer('yearly', 'trial-year', [
                _free('P1W', cycles: 2),
                _yearly,
              ], offerId: 'free-trial'),
            ],
          ),
        );
        final adapter = FlutterPurchaseAdapter(
          appId: 'app',
          currentUserId: () => userId,
        );

        final offers = await adapter.fetchProducts(['app_motion_plus']);
        expect(offers.single.freeTrialPeriod, 'P14D');
        expect(offers.single.localizedPrice, r'$69.99');
      },
    );

    test('without an eligible trial offer the base plan is bought', () async {
      // Play omits offers the user is not eligible for (trial already used).
      billing.products = GooglePlayProductDetails.fromProductDetails(
        ProductDetailsWrapper(
          description: 'Membership',
          name: 'Membership',
          productId: 'app_individual',
          productType: ProductType.subs,
          title: 'Membership',
          subscriptionOfferDetails: [
            _offer('monthly', 'base-month', [_monthly]),
          ],
        ),
      );
      final adapter = FlutterPurchaseAdapter(
        appId: 'app',
        currentUserId: () => userId,
      );

      final offers = await adapter.fetchProducts(['app_individual']);
      expect(offers.single.freeTrialPeriod, isNull);
      await adapter.startPurchase(offers.single);
      expect(
        (billing.lastPurchase! as GooglePlayPurchaseParam).offerToken,
        'base-month',
      );
    });
  });

  group('App Store (StoreKit 2)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    Future<StoreProductRef> fetch(
      List<SK2SubscriptionOffer> offers,
      Future<bool> Function(String) eligible,
    ) async {
      const id = 'com.yulalab.app.individual.monthly';
      billing.products = [
        AppStoreProduct2Details.fromSK2Product(_sk2(id, offers)),
      ];
      final adapter = FlutterPurchaseAdapter(
        appId: 'app',
        currentUserId: () => userId,
        introductoryOfferEligible: eligible,
      );
      return (await adapter.fetchProducts([id])).single;
    }

    test('an eligible two-week free trial is claimed', () async {
      final checked = <String>[];
      final offer = await fetch([_intro(2, SK2SubscriptionPeriodUnit.week)], (
        id,
      ) async {
        checked.add(id);
        return true;
      });
      expect(offer.freeTrialPeriod, 'P14D');
      expect(offer.localizedPrice, r'$11.99');
      expect(checked, ['com.yulalab.app.individual.monthly']);
    });

    test('no trial is claimed when the account is not eligible', () async {
      final offer = await fetch([
        _intro(14, SK2SubscriptionPeriodUnit.day),
      ], (_) async => false);
      expect(offer.freeTrialPeriod, isNull);
    });

    test('no trial is claimed when eligibility cannot be read', () async {
      final offer = await fetch([
        _intro(14, SK2SubscriptionPeriodUnit.day),
      ], (_) async => throw StateError('storekit2_eligibility_check_failed'));
      expect(offer.freeTrialPeriod, isNull);
    });

    test(
      'a paid introductory price or a promotion is not a free trial',
      () async {
        var checks = 0;
        final offer = await fetch(
          [
            _intro(
              1,
              SK2SubscriptionPeriodUnit.month,
              mode: SK2SubscriptionOfferPaymentMode.payUpFront,
            ),
            _intro(
              14,
              SK2SubscriptionPeriodUnit.day,
              type: SK2SubscriptionOfferType.promotional,
            ),
          ],
          (_) async {
            checks++;
            return true;
          },
        );
        expect(offer.freeTrialPeriod, isNull);
        expect(checks, 0);
      },
    );
  });
}
