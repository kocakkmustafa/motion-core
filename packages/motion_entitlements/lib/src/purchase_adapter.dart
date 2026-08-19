import 'entitlement_status.dart';
import 'store_product_ref.dart';

/// Abstracts StoreKit 2 / Google Play Billing. No implementation ships in
/// this package — apps wire a platform-specific adapter against this
/// contract.
abstract class PurchaseAdapter {
  Future<List<StoreProductRef>> fetchProducts(List<String> productIds);
  Future<EntitlementStatus> purchase(String productId);
  Future<List<EntitlementStatus>> restore();
}
