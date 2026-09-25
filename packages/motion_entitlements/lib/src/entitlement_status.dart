import 'purchase_state.dart';

enum EntitlementSource { localCache, store, server }

const String motionPlusScope = 'motion_plus';
const Set<String> motionConsumerAppIds = <String>{
  'ostinato',
  'gravita',
  'choreia',
  'jablab',
  'lissom',
};

/// A point-in-time snapshot for one user's product in one Motion scope.
/// Only a server-verified, unexpired subscription can grant access.
class EntitlementStatus {
  const EntitlementStatus({
    required this.state,
    required this.userId,
    required this.appId,
    required this.productId,
    this.expiresAt,
    required this.lastVerifiedAt,
    required this.source,
  });

  final PurchaseState state;
  final String userId;
  final String appId;
  final String productId;
  final DateTime? expiresAt;
  final DateTime lastVerifiedAt;
  final EntitlementSource source;

  /// Requires the *current* signed-in user and app as explicit inputs.
  /// Store and local-only observations are never purchase verification.
  bool grantsAccessAt(
    DateTime now, {
    required String userId,
    required String appId,
  }) {
    if (userId.isEmpty ||
        !motionConsumerAppIds.contains(appId) ||
        this.userId != userId ||
        (this.appId != appId && this.appId != motionPlusScope)) {
      return false;
    }
    if (state != PurchaseState.entitled || source != EntitlementSource.server) {
      return false;
    }
    if (lastVerifiedAt.isAfter(now)) {
      return false;
    }
    final expiry = expiresAt;
    if (expiry == null) {
      return false;
    }
    return now.isBefore(expiry);
  }
}
