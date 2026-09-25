import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    as platform;
import 'package:motion_entitlements/motion_entitlements.dart';

class _Billing extends platform.InAppPurchasePlatform {
  final events = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  List<ProductDetails> products = [];
  PurchaseParam? lastPurchase;
  PurchaseDetails? completed;
  bool restored = false;
  String? restoredAccountName;

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

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restored = true;
    restoredAccountName = applicationUserName;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed = purchase;
  }
}

SubscriptionOfferDetailsWrapper _plan(
  String id,
  String token,
  String price, {
  String? offerId,
}) => SubscriptionOfferDetailsWrapper(
  basePlanId: id,
  offerId: offerId,
  offerTags: const [],
  offerIdToken: token,
  pricingPhases: [
    PricingPhaseWrapper(
      billingCycleCount: 0,
      billingPeriod: id == 'yearly' ? 'P1Y' : 'P1M',
      formattedPrice: price,
      priceAmountMicros: id == 'yearly' ? 74840000 : 9900000,
      priceCurrencyCode: 'USD',
      recurrenceMode: RecurrenceMode.infiniteRecurring,
    ),
  ],
);

void main() {
  const userId = '01234567-89AB-CDEF-0123-456789ABCDEF';
  var signedInUser = userId;
  TestWidgetsFlutterBinding.ensureInitialized();
  // Create the facade without registering a native store inside the test VM.
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  InAppPurchase.instance;
  debugDefaultTargetPlatformOverride = null;
  late _Billing billing;

  setUp(() {
    signedInUser = userId;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    billing = _Billing();
    platform.InAppPurchasePlatform.instance = billing;
  });

  tearDown(() async {
    await billing.events.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'one Play product exposes monthly/yearly base plans and their prices',
    () async {
      const productId = 'jablab_motion_plus';
      final wrapper = ProductDetailsWrapper(
        description: 'Motion+ access',
        name: 'Motion+',
        productId: productId,
        productType: ProductType.subs,
        title: 'Motion+',
        subscriptionOfferDetails: [
          _plan('monthly', 'token-month', r'$30.00'),
          _plan('yearly', 'token-year', r'$226.80'),
          _plan('monthly', 'intro-token', r'$1.00', offerId: 'intro'),
        ],
      );
      billing.products = GooglePlayProductDetails.fromProductDetails(wrapper);
      final adapter = FlutterPurchaseAdapter(
        appId: 'jablab',
        currentUserId: () => signedInUser,
      );

      final offers = await adapter.fetchProducts([productId]);
      expect(offers.map((offer) => offer.planId), ['monthly', 'yearly']);
      expect(offers.map((offer) => offer.localizedPrice), [
        r'$30.00',
        r'$226.80',
      ]);

      await adapter.startPurchase(offers.last);
      expect(billing.lastPurchase, isA<GooglePlayPurchaseParam>());
      expect(
        (billing.lastPurchase! as GooglePlayPurchaseParam).offerToken,
        'token-year',
      );
      final playAccountId = billing.lastPurchase!.applicationUserName;
      expect(playAccountId, hasLength(64));
      expect(playAccountId, isNot(contains(userId.toLowerCase())));
      await adapter.restore();
      expect(billing.restoredAccountName, playAccountId);
    },
  );

  test(
    'purchase stream carries server proof and completes exact event',
    () async {
      final adapter = FlutterPurchaseAdapter(
        appId: 'jablab',
        currentUserId: () => signedInUser,
      );
      final next = adapter.updates.first;
      final purchase = PurchaseDetails(
        purchaseID: 'txn-1',
        productID: 'jablab_motion_plus',
        verificationData: PurchaseVerificationData(
          localVerificationData: 'local-only',
          serverVerificationData: 'play-token',
          source: 'google_play',
        ),
        transactionDate: '1',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true;
      billing.events.add([purchase]);

      final update = await next;
      expect(update.kind, StorePurchaseKind.purchased);
      expect(update.evidence?.verificationData, 'play-token');
      expect(update.evidence?.originatingAppId, 'jablab');
      expect(billing.completed, isNull);
      await adapter.complete(update);
      expect(billing.completed, same(purchase));

      await adapter.restore();
      expect(billing.restored, isTrue);
    },
  );

  test(
    'Apple purchase uses the Motion Auth UUID as app account token',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      billing.products = [
        ProductDetails(
          id: 'com.yulalab.jablab.individual.monthly',
          title: 'JabLab Monthly',
          description: 'JabLab access',
          price: r'$9.90',
          rawPrice: 9.9,
          currencyCode: 'USD',
        ),
      ];
      final adapter = FlutterPurchaseAdapter(
        appId: 'jablab',
        currentUserId: () => signedInUser,
      );
      final offers = await adapter.fetchProducts([
        'com.yulalab.jablab.individual.monthly',
      ]);

      await adapter.startPurchase(offers.single);
      expect(billing.lastPurchase!.applicationUserName, userId.toLowerCase());
      await adapter.restore();
      expect(billing.restoredAccountName, userId.toLowerCase());
    },
  );

  test('purchase and restore require a signed-in UUID account', () async {
    billing.products = GooglePlayProductDetails.fromProductDetails(
      ProductDetailsWrapper(
        description: 'Motion+ access',
        name: 'Motion+',
        productId: 'jablab_motion_plus',
        productType: ProductType.subs,
        title: 'Motion+',
        subscriptionOfferDetails: [_plan('monthly', 'token-month', r'$30.00')],
      ),
    );
    final adapter = FlutterPurchaseAdapter(
      appId: 'jablab',
      currentUserId: () => signedInUser,
    );
    final offers = await adapter.fetchProducts(['jablab_motion_plus']);

    signedInUser = '';
    await expectLater(adapter.startPurchase(offers.single), throwsStateError);
    expect(() => adapter.restore(), throwsStateError);
    expect(billing.lastPurchase, isNull);
    expect(billing.restored, isFalse);

    signedInUser = 'not-a-uuid';
    await expectLater(adapter.startPurchase(offers.single), throwsStateError);
  });
}
