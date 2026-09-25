import 'entitlement_cache.dart';
import 'entitlement_status.dart';
import 'purchase_adapter.dart';
import 'purchase_state.dart';
import 'server_adapter.dart';

/// Connects a store event to server verification without granting access from
/// a local receipt, a stale account, or another app's transaction.
class PurchaseCoordinator {
  const PurchaseCoordinator({
    required this.appId,
    required this.currentUserId,
    required this.store,
    required this.server,
    required this.cache,
    required this.now,
  });

  final String appId;
  final String Function() currentUserId;
  final PurchaseAdapter store;
  final ServerAdapter server;
  final EntitlementCache cache;
  final DateTime Function() now;

  /// Returns a verified right only for a purchased/restored event. A failed
  /// check leaves the transaction unacknowledged so it can be retried after
  /// the account or verification service recovers.
  Future<EntitlementStatus?> verifyAndComplete(
    StorePurchaseUpdate update,
  ) async {
    if (update.kind != StorePurchaseKind.purchased &&
        update.kind != StorePurchaseKind.restored) {
      return null;
    }
    final evidence = update.evidence;
    final userId = currentUserId();
    if (userId.isEmpty ||
        evidence == null ||
        evidence.originatingAppId != appId ||
        evidence.productId.isEmpty ||
        evidence.verificationData.isEmpty) {
      return null;
    }

    final verified = await server.verify(evidence);
    if (currentUserId() != userId ||
        verified == null ||
        verified.userId != userId ||
        verified.productId != evidence.productId ||
        (verified.appId != appId && verified.appId != motionPlusScope) ||
        verified.source != EntitlementSource.server ||
        (verified.state != PurchaseState.entitled &&
            verified.state != PurchaseState.notEntitled)) {
      return null;
    }
    final hasAccess = verified.grantsAccessAt(
      now(),
      userId: userId,
      appId: appId,
    );
    if (hasAccess) cache.write(verified);
    // A verified expired/refunded restore is terminal but never unlocks a
    // course. Unverified or temporarily unavailable checks stay retryable.
    await store.complete(update);
    return hasAccess ? verified : null;
  }
}
