import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'purchase_adapter.dart';
import 'store_product_ref.dart';

/// Bridges the official Flutter store plugin to Motion's verification boundary.
/// Subscribe to [updates] before starting purchases or requesting a restore.
class FlutterPurchaseAdapter implements PurchaseAdapter {
  FlutterPurchaseAdapter({
    required this.appId,
    required this.currentUserId,
    InAppPurchase? billing,
  }) : _billing = billing ?? InAppPurchase.instance;

  final String appId;
  final String? Function() currentUserId;
  final InAppPurchase _billing;
  final _offers = <(String, String), ProductDetails>{};
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
    final result = <StoreProductRef>[];
    for (final detail in response.productDetails) {
      String? planId;
      if (detail is GooglePlayProductDetails) {
        final index = detail.subscriptionIndex;
        final plans = detail.productDetails.subscriptionOfferDetails;
        if (index == null || plans == null || index >= plans.length) continue;
        final plan = plans[index];
        // v1 sells only the ordinary monthly/yearly base plans, not offers.
        if (plan.offerId != null && plan.offerId!.isNotEmpty) continue;
        planId = plan.basePlanId;
      } else if (detail.id.endsWith('.monthly')) {
        planId = 'monthly';
      } else if (detail.id.endsWith('.yearly')) {
        planId = 'yearly';
      }
      if (planId == null || (planId != 'monthly' && planId != 'yearly')) {
        continue;
      }

      _offers[(detail.id, planId)] = detail;
      result.add(
        StoreProductRef(
          productId: detail.id,
          platform: _platform,
          planId: planId,
          localizedPrice: detail.price,
        ),
      );
    }
    return result;
  }

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
    final param = detail is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: detail,
            offerToken: detail.offerToken,
            applicationUserName: accountId,
          )
        : PurchaseParam(productDetails: detail, applicationUserName: accountId);
    final started = await _billing.buyNonConsumable(purchaseParam: param);
    if (!started) throw StateError('The store did not start the purchase');
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
