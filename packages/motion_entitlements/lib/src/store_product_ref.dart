enum StorePlatform { ios, android }

/// One offer returned by the platform store. Google Play can return monthly
/// and yearly offers for the same subscription product ID, so [planId] is
/// part of the selection. The localized price comes from the store, never a
/// hard-coded USD amount in the app.
class StoreProductRef {
  const StoreProductRef({
    required this.productId,
    required this.platform,
    required this.planId,
    required this.localizedPrice,
  });

  final String productId;
  final StorePlatform platform;
  final String planId;
  final String localizedPrice;
}
