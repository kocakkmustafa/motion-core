import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import 'motion_trial_gate.dart';
import 'purchase_adapter.dart';
import 'store_product_ref.dart';

/// Bridges the official Flutter store plugin to Motion's verification boundary.
/// Subscribe to [updates] before starting purchases or requesting a restore.
class FlutterPurchaseAdapter implements PurchaseAdapter {
  FlutterPurchaseAdapter({
    required this.appId,
    required this.currentUserId,
    InAppPurchase? billing,
    Future<bool> Function(String productId)? introductoryOfferEligible,
    MotionTrialGate? trialGate,
  }) : _billing = billing ?? InAppPurchase.instance,
       _introductoryOfferEligible = introductoryOfferEligible,
       _trialGate = trialGate;

  final String appId;
  final String? Function() currentUserId;
  final InAppPurchase _billing;
  final Future<bool> Function(String productId)? _introductoryOfferEligible;

  /// One Motion+ free trial per Motion account. Without a gate the stores'
  /// own eligibility applies unchanged.
  final MotionTrialGate? _trialGate;
  bool _motionPlusTrialAvailable = true;
  final _offers = <(String, String), ProductDetails>{};
  // Play free-trial offer chosen for a base plan; buying uses its token.
  final _trialOffers = <(String, String), GooglePlayProductDetails>{};
  final _uncompleted = <String, PurchaseDetails>{};
  var _nextLocalHandle = 0;

  StorePlatform get _platform {
    if (defaultTargetPlatform == TargetPlatform.iOS) return StorePlatform.ios;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return StorePlatform.android;
    }
    throw UnsupportedError('Motion subscriptions require iOS or Android');
  }

  String _storeAccountId() {
    final userId = currentUserId();
    // Motion Auth identifiers are UUIDs. StoreKit requires this format for
    // appAccountToken; Play receives only a deterministic one-way digest.
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (userId == null || !uuid.hasMatch(userId)) {
      throw StateError('Sign in to a Motion account before purchasing');
    }
    final normalized = userId.toLowerCase();
    if (_platform == StorePlatform.ios) return normalized;
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  @override
  late final Stream<StorePurchaseUpdate> updates = _billing.purchaseStream
      .expand((purchases) => purchases.map(_wrap));

  StorePurchaseUpdate _wrap(PurchaseDetails purchase) {
    final handle = 'purchase-${++_nextLocalHandle}';
    final kind = switch (purchase.status) {
      PurchaseStatus.pending => StorePurchaseKind.pending,
      PurchaseStatus.purchased => StorePurchaseKind.purchased,
      PurchaseStatus.restored => StorePurchaseKind.restored,
      PurchaseStatus.canceled => StorePurchaseKind.canceled,
      PurchaseStatus.error => StorePurchaseKind.failed,
    };
    StorePurchaseEvidence? evidence;
    if (kind == StorePurchaseKind.purchased ||
        kind == StorePurchaseKind.restored) {
      _uncompleted[handle] = purchase;
      evidence = StorePurchaseEvidence(
        platform: _platform,
        originatingAppId: appId,
        productId: purchase.productID,
        verificationData: purchase.verificationData.serverVerificationData,
        transactionId: purchase.purchaseID,
      );
    }
    return StorePurchaseUpdate(
      kind: kind,
      localHandle: handle,
      evidence: evidence,
      errorCode: purchase.error?.code,
    );
  }

  @override
  Future<List<StoreProductRef>> fetchProducts(List<String> productIds) async {
    if (!await _billing.isAvailable()) return const [];
    final response = await _billing.queryProductDetails(productIds.toSet());
    if (response.error != null) {
      throw StateError('Store products could not be loaded');
    }

    _offers.clear();
    _trialOffers.clear();
    final gate = _trialGate;
    _motionPlusTrialAvailable =
        gate == null ||
        !response.productDetails.any((d) => isMotionPlusProduct(d.id)) ||
        await _safeTrialAvailable(gate);
    // Play returns the base plan and every offer the user is eligible for as
    // separate details. A free-trial offer attaches to its base plan; other
    // offers (paid intro prices, promotions) are not sold.
    for (final detail in response.productDetails) {
      if (detail is! GooglePlayProductDetails) continue;
      final plan = _playPlan(detail);
      if (plan == null || plan.offerId == null || plan.offerId!.isEmpty) {
        continue;
      }
      if (_playFreeTrial(plan) == null) continue;
      // Motion+ trial: once per Motion account (developer-determined offer).
      if (isMotionPlusProduct(detail.id) && !_motionPlusTrialAvailable) {
        continue;
      }
      _trialOffers.putIfAbsent((detail.id, plan.basePlanId), () => detail);
    }

    final result = <StoreProductRef>[];
    for (final detail in response.productDetails) {
      String? planId;
      String? trial;
      if (detail is GooglePlayProductDetails) {
        final plan = _playPlan(detail);
        if (plan == null) continue;
        if (plan.offerId != null && plan.offerId!.isNotEmpty) continue;
        planId = plan.basePlanId;
        final trialOffer = _trialOffers[(detail.id, planId)];
        if (trialOffer != null) trial = _playFreeTrial(_playPlan(trialOffer)!);
      } else if (detail.id.endsWith('.monthly')) {
        planId = 'monthly';
      } else if (detail.id.endsWith('.yearly')) {
        planId = 'yearly';
      }
      if (planId == null || (planId != 'monthly' && planId != 'yearly')) {
        continue;
      }
      if (detail is AppStoreProduct2Details &&
          (!isMotionPlusProduct(detail.id) || _motionPlusTrialAvailable)) {
        trial = await _appStoreFreeTrial(detail);
      }

      _offers[(detail.id, planId)] = detail;
      result.add(
        StoreProductRef(
          productId: detail.id,
          platform: _platform,
          planId: planId,
          localizedPrice: detail.price,
          freeTrialPeriod: trial,
        ),
      );
    }
    return result;
  }

  /// App Store `com.yulalab.<app>.motionplus.*` or Play `<app>_motion_plus`.
  static bool isMotionPlusProduct(String productId) =>
      productId.contains('.motionplus.') || productId.endsWith('_motion_plus');

  static Future<bool> _safeTrialAvailable(MotionTrialGate gate) async {
    try {
      return await gate.motionPlusTrialAvailable();
    } on Object {
      return false;
    }
  }

  static SubscriptionOfferDetailsWrapper? _playPlan(
    GooglePlayProductDetails detail,
  ) {
    final index = detail.subscriptionIndex;
    final plans = detail.productDetails.subscriptionOfferDetails;
    if (index == null || plans == null || index >= plans.length) return null;
    return plans[index];
  }

  /// A Play offer is a free trial when its first phase is free, finite, and
  /// followed by a paid phase. Returns the trial length, or null.
  static String? _playFreeTrial(SubscriptionOfferDetailsWrapper plan) {
    final phases = plan.pricingPhases;
    if (phases.length < 2) return null;
    final first = phases.first;
    if (first.priceAmountMicros != 0 ||
        first.recurrenceMode != RecurrenceMode.finiteRecurring ||
        phases.last.priceAmountMicros <= 0) {
      return null;
    }
    return motionStorePeriod(
      first.billingPeriod,
      count: first.billingCycleCount,
    );
  }

  /// StoreKit 2 lists the introductory offer with the product. A free trial is
  /// claimed only when the store also confirms this account is eligible; an
  /// unreadable eligibility claims nothing.
  Future<String?> _appStoreFreeTrial(AppStoreProduct2Details detail) async {
    final offers =
        detail.sk2Product.subscription?.promotionalOffers ?? const [];
    SK2SubscriptionOffer? intro;
    for (final offer in offers) {
      if (offer.type == SK2SubscriptionOfferType.introductory &&
          offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial) {
        intro = offer;
        break;
      }
    }
    if (intro == null) return null;
    final unit = switch (intro.period.unit) {
      SK2SubscriptionPeriodUnit.day => 'D',
      SK2SubscriptionPeriodUnit.week => 'W',
      SK2SubscriptionPeriodUnit.month => 'M',
      SK2SubscriptionPeriodUnit.year => 'Y',
    };
    try {
      final eligible =
          await (_introductoryOfferEligible ??
              _storeKitIntroductoryOfferEligible)(detail.id);
      if (!eligible) return null;
    } catch (_) {
      return null;
    }
    return motionStorePeriod(
      'P${intro.period.value}$unit',
      count: intro.periodCount,
    );
  }

  // StoreKit 2 details only exist in StoreKit 2 mode, where this native
  // check is available (in_app_purchase_storekit 0.4.13).
  static Future<bool> _storeKitIntroductoryOfferEligible(String productId) =>
      SK2Product.isIntroductoryOfferEligible(productId);

  @override
  Future<void> startPurchase(StoreProductRef offer) async {
    if (offer.platform != _platform) {
      throw ArgumentError.value(offer.platform, 'platform');
    }
    final detail = _offers[(offer.productId, offer.planId)];
    if (detail == null) {
      throw StateError('The selected store plan is unavailable');
    }
    final accountId = _storeAccountId();
    // On Play the free trial is a separate offer: buy through its token when
    // the store returned one for this user, otherwise the base plan.
    final trialOffer = _trialOffers[(offer.productId, offer.planId)];
    final param = detail is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: trialOffer ?? detail,
            offerToken: (trialOffer ?? detail).offerToken,
            applicationUserName: accountId,
          )
        : await _appStoreParam(detail, accountId);
    final started = await _billing.buyNonConsumable(purchaseParam: param);
    if (!started) throw StateError('The store did not start the purchase');
  }

  /// App Store: once the account used its Motion+ trial, the purchase carries
  /// the server-signed `allowIntroductoryOffer=false` so Apple does not apply
  /// the trial again in another app. Without a denial (no gate, trial still
  /// available, no app transaction ID) Apple's own eligibility applies.
  Future<PurchaseParam> _appStoreParam(
    ProductDetails detail,
    String accountId,
  ) async {
    final gate = _trialGate;
    if (gate != null &&
        isMotionPlusProduct(detail.id) &&
        !_motionPlusTrialAvailable) {
      String? denial;
      try {
        denial = await gate.appleIntroductoryOfferDenial(detail.id);
      } on Object {
        denial = null;
      }
      if (denial != null) {
        return Sk2PurchaseParam(
          productDetails: detail,
          applicationUserName: accountId,
          introductoryOfferEligibilityCompactJWS: denial,
        );
      }
    }
    return PurchaseParam(
      productDetails: detail,
      applicationUserName: accountId,
    );
  }

  @override
  Future<void> restore() =>
      _billing.restorePurchases(applicationUserName: _storeAccountId());

  @override
  Future<void> complete(StorePurchaseUpdate update) async {
    final purchase = _uncompleted[update.localHandle];
    if (purchase == null) {
      throw StateError('The store transaction is no longer available');
    }
    if (purchase.pendingCompletePurchase) {
      await _billing.completePurchase(purchase);
    }
    _uncompleted.remove(update.localHandle);
  }
}
