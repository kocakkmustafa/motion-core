import 'store_product_ref.dart';

enum StorePurchaseKind { pending, purchased, restored, canceled, failed }

/// Opaque purchase proof from StoreKit or Google Play. The server must
/// validate it with that store and derive the Motion user from the current
/// authenticated session, never from data supplied by this object. The server
/// must also compare the store-signed app account token / obfuscated account
/// identifier with that user before granting or transferring a purchase.
class StorePurchaseEvidence {
  const StorePurchaseEvidence({
    required this.platform,
    required this.originatingAppId,
    required this.productId,
    required this.verificationData,
    this.transactionId,
  });

  final StorePlatform platform;
  final String originatingAppId;
  final String productId;
  final String verificationData;
  final String? transactionId;
}

/// A purchase can finish long after the button returns. [localHandle] only
/// identifies the store event for acknowledgement inside this app; it is not
/// sent to the server as proof of payment.
class StorePurchaseUpdate {
  const StorePurchaseUpdate({
    required this.kind,
    required this.localHandle,
    this.evidence,
    this.errorCode,
  });

  final StorePurchaseKind kind;
  final String localHandle;
  final StorePurchaseEvidence? evidence;
  final String? errorCode;
}

/// Abstracts StoreKit / Google Play Billing's asynchronous event stream.
/// Only [ServerAdapter] can turn an event into a verified entitlement.
abstract class PurchaseAdapter {
  Stream<StorePurchaseUpdate> get updates;

  Future<List<StoreProductRef>> fetchProducts(List<String> productIds);
  Future<void> startPurchase(StoreProductRef offer);
  Future<void> restore();
  Future<void> complete(StorePurchaseUpdate update);
}
