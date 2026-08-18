import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

EntitlementStatus _status(PurchaseState state, {DateTime? expiresAt}) => EntitlementStatus(
      state: state,
      productId: 'lissom.premium.monthly',
      expiresAt: expiresAt,
      lastVerifiedAt: DateTime(2026, 1, 1),
      source: EntitlementSource.store,
    );

void main() {
  group('EntitlementStatus.grantsAccessAt — fail-closed access grant', () {
    final now = DateTime(2026, 6, 1);

    test('entitled with no expiry (non-expiring) grants access', () {
      expect(_status(PurchaseState.entitled).grantsAccessAt(now), isTrue);
    });

    test('entitled with a future expiry grants access', () {
      final future = now.add(const Duration(days: 1));
      expect(_status(PurchaseState.entitled, expiresAt: future).grantsAccessAt(now), isTrue);
    });

    test('fail-closed: entitled with a past expiry does NOT grant access', () {
      final past = now.subtract(const Duration(days: 1));
      expect(_status(PurchaseState.entitled, expiresAt: past).grantsAccessAt(now), isFalse);
    });

    test('fail-closed: every non-entitled state denies access, regardless of expiresAt', () {
      final future = now.add(const Duration(days: 365));
      for (final state in PurchaseState.values.where((s) => s != PurchaseState.entitled)) {
        expect(
          _status(state, expiresAt: future).grantsAccessAt(now),
          isFalse,
          reason: '$state must never grant access, even with a far-future expiresAt',
        );
      }
    });
  });
}
