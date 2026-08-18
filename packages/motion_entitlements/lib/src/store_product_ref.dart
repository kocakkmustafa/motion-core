enum StorePlatform { ios, android }

/// An opaque reference to a store product. Deliberately carries no price or
/// display text — paywall copy and pricing are an app/UI concern, not this
/// package's.
class StoreProductRef {
  const StoreProductRef({required this.productId, required this.platform});

  final String productId;
  final StorePlatform platform;
}
