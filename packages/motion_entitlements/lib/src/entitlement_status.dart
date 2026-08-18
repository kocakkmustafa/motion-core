import 'purchase_state.dart';

enum EntitlementSource { localCache, store, server }

/// A point-in-time snapshot of one product's entitlement. `expiresAt` of
/// `null` means non-expiring; a non-null value must be checked against the
/// current time — see [grantsAccessAt].
class EntitlementStatus {
  const EntitlementStatus({
    required this.state,
    required this.productId,
    this.expiresAt,
    required this.lastVerifiedAt,
    required this.source,
  });

  final PurchaseState state;
  final String productId;
  final DateTime? expiresAt;
  final DateTime lastVerifiedAt;
  final EntitlementSource source;

  /// Whether this status grants access at [now]. Fail-closed: only
  /// [PurchaseState.entitled] can ever return true, and even then an
  /// [expiresAt] in the past denies access. Every other state — including
  /// [PurchaseState.recoverableError] — denies access unconditionally, so a
  /// transient store/network error can never be misread as a paid user.
  bool grantsAccessAt(DateTime now) {
    if (state != PurchaseState.entitled) return false;
    final expiry = expiresAt;
    if (expiry == null) return true;
    return now.isBefore(expiry);
  }

  bool get grantsAccess => grantsAccessAt(DateTime.now());
}
