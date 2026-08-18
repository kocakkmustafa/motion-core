import 'entitlement_status.dart';

/// Local offline-cache of the last known entitlement per product.
/// Fail-closed: an unread/unknown product returns `null`, never a
/// fabricated status that could be mistaken for a real (dis)entitlement.
abstract class EntitlementCache {
  EntitlementStatus? read(String productId);
  void write(EntitlementStatus status);
}

class InMemoryEntitlementCache implements EntitlementCache {
  final _byProductId = <String, EntitlementStatus>{};

  @override
  EntitlementStatus? read(String productId) => _byProductId[productId];

  @override
  void write(EntitlementStatus status) {
    _byProductId[status.productId] = status;
  }
}
