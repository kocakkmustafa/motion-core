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
    final previous = cache.read(
      userId: userId,
      appId: verified.appId,
      productId: verified.productId,
    );
    // Keep this shared-key read/check/write synchronous: separate coordinators
    // may finish out of order. Equal observations favor denial/shorter expiry.
    // Server verification time orders observations, not provider store events.
    if (_shouldReplace(verified, previous, now())) cache.write(verified);
    // A verified expired/refunded restore is terminal but never unlocks a
    // course. Unverified or temporarily unavailable checks stay retryable.
    await store.complete(update);
    // Store acknowledgement can yield to a revoke, account change or expiry.
    // Publish only the snapshot still accepted for this owner and product.
    if (currentUserId() != userId ||
        !_sameSnapshot(
          verified,
          cache.read(
            userId: userId,
            appId: verified.appId,
            productId: verified.productId,
          ),
        )) {
      return null;
    }
    return verified.grantsAccessAt(now(), userId: userId, appId: appId)
        ? verified
        : null;
  }

  bool _shouldReplace(
    EntitlementStatus next,
    EntitlementStatus? previous,
    DateTime observedNow,
  ) {
    if (previous == null ||
        previous.userId != next.userId ||
        previous.appId != next.appId ||
        previous.productId != next.productId ||
        previous.source != EntitlementSource.server ||
        (previous.state != PurchaseState.entitled &&
            previous.state != PurchaseState.notEntitled)) {
      return true;
    }
    final order = next.lastVerifiedAt.compareTo(previous.lastVerifiedAt);
    if (order != 0) return order > 0;
    final previousGrants = previous.grantsAccessAt(
      observedNow,
      userId: next.userId,
      appId: appId,
    );
    final nextGrants = next.grantsAccessAt(
      observedNow,
      userId: next.userId,
      appId: appId,
    );
    if (previousGrants != nextGrants) return !nextGrants;
    return nextGrants && next.expiresAt!.isBefore(previous.expiresAt!);
  }

  static bool _sameSnapshot(
    EntitlementStatus expected,
    EntitlementStatus? actual,
  ) =>
      actual != null &&
      actual.userId == expected.userId &&
      actual.appId == expected.appId &&
      actual.productId == expected.productId &&
      actual.source == expected.source &&
      actual.state == expected.state &&
      actual.lastVerifiedAt.isAtSameMomentAs(expected.lastVerifiedAt) &&
      (actual.expiresAt == null
          ? expected.expiresAt == null
          : expected.expiresAt != null &&
                actual.expiresAt!.isAtSameMomentAs(expected.expiresAt!));
}
