import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

EntitlementStatus _status(String userId, String appId) => EntitlementStatus(
  state: PurchaseState.entitled,
  userId: userId,
  appId: appId,
  productId: 'monthly',
  expiresAt: DateTime(2026, 7, 1),
  lastVerifiedAt: DateTime(2026, 6, 1),
  source: EntitlementSource.server,
);

void main() {
  group('InMemoryEntitlementCache', () {
    test('unknown product returns null', () {
      final cache = InMemoryEntitlementCache();
      expect(
        cache.read(userId: 'user-a', appId: 'jablab', productId: 'monthly'),
        isNull,
      );
    });

    test('same product never crosses account or app boundary', () {
      final cache = InMemoryEntitlementCache();
      final status = _status('user-a', 'jablab');
      cache.write(status);
      expect(
        cache.read(userId: 'user-a', appId: 'jablab', productId: 'monthly'),
        same(status),
      );
      expect(
        cache.read(userId: 'user-b', appId: 'jablab', productId: 'monthly'),
        isNull,
      );
      expect(
        cache.read(userId: 'user-a', appId: 'gravita', productId: 'monthly'),
        isNull,
      );
    });

    test('recheck can revoke one account without touching another', () {
      final cache = InMemoryEntitlementCache();
      cache.write(_status('user-a', 'jablab'));
      final other = _status('user-b', 'jablab');
      cache.write(other);
      final revoked = EntitlementStatus(
        state: PurchaseState.notEntitled,
        userId: 'user-a',
        appId: 'jablab',
        productId: 'monthly',
        lastVerifiedAt: DateTime(2026, 6, 2),
        source: EntitlementSource.server,
      );
      cache.write(revoked);
      expect(
        cache.read(userId: 'user-a', appId: 'jablab', productId: 'monthly'),
        same(revoked),
      );
      expect(
        cache.read(userId: 'user-b', appId: 'jablab', productId: 'monthly'),
        same(other),
      );
      cache.clearUser('user-a');
      expect(
        cache.read(userId: 'user-a', appId: 'jablab', productId: 'monthly'),
        isNull,
      );
      expect(
        cache.read(userId: 'user-b', appId: 'jablab', productId: 'monthly'),
        same(other),
      );
    });
  });
}
