import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

EntitlementStatus _status(
  PurchaseState state, {
  String appId = 'jablab',
  DateTime? expiresAt,
  EntitlementSource source = EntitlementSource.server,
}) => EntitlementStatus(
  state: state,
  userId: 'user-a',
  appId: appId,
  productId: 'jablab.premium.monthly',
  expiresAt: expiresAt,
  lastVerifiedAt: DateTime(2026, 6, 1),
  source: source,
);

void main() {
  group('EntitlementStatus.grantsAccessAt', () {
    final now = DateTime(2026, 6, 2);
    bool grants(
      EntitlementStatus status, {
      String userId = 'user-a',
      String appId = 'jablab',
    }) => status.grantsAccessAt(now, userId: userId, appId: appId);

    test('only server-verified, unexpired access for this user and app', () {
      final status = _status(
        PurchaseState.entitled,
        expiresAt: now.add(const Duration(days: 1)),
      );
      expect(grants(status), isTrue);
      expect(grants(status, userId: 'user-b'), isFalse);
      expect(grants(status, appId: 'gravita'), isFalse);
      expect(grants(status, userId: ''), isFalse);
    });

    test('Motion+ grants the five named apps and nothing else', () {
      final status = _status(
        PurchaseState.entitled,
        appId: motionPlusScope,
        expiresAt: now.add(const Duration(days: 1)),
      );
      for (final appId in motionConsumerAppIds) {
        expect(grants(status, appId: appId), isTrue, reason: appId);
      }
      expect(grants(status, appId: 'unknown'), isFalse);
      expect(grants(status, appId: motionPlusScope), isFalse);
      expect(grants(status, userId: 'user-b'), isFalse);
      expect(
        grants(
          _status(
            PurchaseState.entitled,
            appId: motionPlusScope,
            expiresAt: now.subtract(const Duration(seconds: 1)),
          ),
          appId: 'ostinato',
        ),
        isFalse,
      );
    });

    test('store or local cache cannot independently unlock content', () {
      for (final source in [
        EntitlementSource.store,
        EntitlementSource.localCache,
      ]) {
        expect(
          grants(
            _status(
              PurchaseState.entitled,
              expiresAt: now.add(const Duration(days: 1)),
              source: source,
            ),
          ),
          isFalse,
        );
      }
    });

    test(
      'subscription without expiry, expired, or future verification fails closed',
      () {
        expect(grants(_status(PurchaseState.entitled)), isFalse);
        expect(
          grants(_status(PurchaseState.entitled, expiresAt: now)),
          isFalse,
        );
        expect(
          grants(
            _status(
              PurchaseState.entitled,
              expiresAt: now.subtract(const Duration(days: 1)),
            ),
          ),
          isFalse,
        );
        expect(
          _status(
            PurchaseState.entitled,
            expiresAt: now.add(const Duration(days: 1)),
          ).grantsAccessAt(
            now.subtract(const Duration(days: 2)),
            userId: 'user-a',
            appId: 'jablab',
          ),
          isFalse,
        );
      },
    );

    test('every non-entitled state denies access', () {
      for (final state in PurchaseState.values.where(
        (value) => value != PurchaseState.entitled,
      )) {
        expect(
          grants(_status(state, expiresAt: now.add(const Duration(days: 365)))),
          isFalse,
        );
      }
    });
  });
}
