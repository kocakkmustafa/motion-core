import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

void main() {
  group('InMemoryEntitlementCache', () {
    test('fail-closed: an unknown product returns null, never a fabricated status', () {
      final cache = InMemoryEntitlementCache();
      expect(cache.read('never-written'), isNull);
    });

    test('write then read returns exactly what was written', () {
      final cache = InMemoryEntitlementCache();
      final status = EntitlementStatus(
        state: PurchaseState.entitled,
        productId: 'jablab.premium.monthly',
        expiresAt: DateTime(2026, 7, 1),
        lastVerifiedAt: DateTime(2026, 6, 1),
        source: EntitlementSource.store,
      );
      cache.write(status);
      expect(cache.read('jablab.premium.monthly'), same(status));
    });

    test('writing again for the same productId replaces the cached value', () {
      final cache = InMemoryEntitlementCache();
      cache.write(EntitlementStatus(
        state: PurchaseState.entitled,
        productId: 'gravita.premium.monthly',
        lastVerifiedAt: DateTime(2026, 6, 1),
        source: EntitlementSource.store,
      ));
      final revoked = EntitlementStatus(
        state: PurchaseState.notEntitled,
        productId: 'gravita.premium.monthly',
        lastVerifiedAt: DateTime(2026, 6, 2),
        source: EntitlementSource.server,
      );
      cache.write(revoked);
      expect(cache.read('gravita.premium.monthly'), same(revoked));
    });
  });
}
