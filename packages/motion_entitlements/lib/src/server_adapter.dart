import 'entitlement_status.dart';
import 'purchase_adapter.dart';

/// Server-side verification boundary. The implementation must derive userId
/// from the authenticated token, not trust a client-supplied account ID.
/// A server-verified notEntitled result is terminal but cannot grant access.
/// Null means the purchase could not be verified and remains retryable.
abstract class ServerAdapter {
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence);
}
