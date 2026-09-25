import 'entitlement_status.dart';

/// Local cache scoped to a signed-in user, app, and product. An unknown
/// combination returns null; consumers must still call grantsAccessAt.
abstract class EntitlementCache {
  EntitlementStatus? read({
    required String userId,
    required String appId,
    required String productId,
  });
  void write(EntitlementStatus status);
  void clearUser(String userId);
}

class InMemoryEntitlementCache implements EntitlementCache {
  final _entries = <(String, String, String), EntitlementStatus>{};

  @override
  EntitlementStatus? read({
    required String userId,
    required String appId,
    required String productId,
  }) => _entries[(userId, appId, productId)];

  @override
  void write(EntitlementStatus status) {
    _entries[(status.userId, status.appId, status.productId)] = status;
  }

  @override
  void clearUser(String userId) {
    _entries.removeWhere((key, _) => key.$1 == userId);
  }
}
