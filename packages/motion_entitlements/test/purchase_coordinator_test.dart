import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

final _now = DateTime.utc(2026, 9, 24);

class _Store implements PurchaseAdapter {
  final completed = <String>[];

  @override
  Stream<StorePurchaseUpdate> get updates => const Stream.empty();

  @override
  Future<List<StoreProductRef>> fetchProducts(List<String> productIds) async =>
      const [];

  @override
  Future<void> startPurchase(StoreProductRef offer) async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> complete(StorePurchaseUpdate update) async {
    completed.add(update.localHandle);
  }
}

class _Server implements ServerAdapter {
  _Server(this.verifyPurchase);

  final Future<EntitlementStatus?> Function(StorePurchaseEvidence)
  verifyPurchase;
  int calls = 0;

  @override
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence) {
    calls++;
    return verifyPurchase(evidence);
  }
}

StorePurchaseUpdate _event({
  StorePurchaseKind kind = StorePurchaseKind.purchased,
  String appId = 'jablab',
  String productId = 'com.yulalab.jablab.motionplus.monthly',
  String proof = 'store-signed-proof',
}) => StorePurchaseUpdate(
  kind: kind,
  localHandle: 'local-1',
  evidence: StorePurchaseEvidence(
    platform: StorePlatform.ios,
    originatingAppId: appId,
    productId: productId,
    verificationData: proof,
  ),
);

EntitlementStatus _verified({
  String userId = 'user-a',
  String appId = motionPlusScope,
  String productId = 'com.yulalab.jablab.motionplus.monthly',
  EntitlementSource source = EntitlementSource.server,
  DateTime? expiresAt,
}) => EntitlementStatus(
  state: PurchaseState.entitled,
  userId: userId,
  appId: appId,
  productId: productId,
  expiresAt: expiresAt ?? _now.add(const Duration(days: 30)),
  lastVerifiedAt: _now,
  source: source,
);

void main() {
  late String signedInUser;
  late _Store store;
  late InMemoryEntitlementCache cache;

  PurchaseCoordinator coordinator(_Server server) => PurchaseCoordinator(
    appId: 'jablab',
    currentUserId: () => signedInUser,
    store: store,
    server: server,
    cache: cache,
    now: () => _now,
  );

  setUp(() {
    signedInUser = 'user-a';
    store = _Store();
    cache = InMemoryEntitlementCache();
  });

  test(
    'verified Motion+ purchase is cached and completed only after server',
    () async {
      final server = _Server((_) async => _verified());
      final result = await coordinator(server).verifyAndComplete(_event());

      expect(
        result?.grantsAccessAt(_now, userId: 'user-a', appId: 'lissom'),
        isTrue,
      );
      expect(server.calls, 1);
      expect(store.completed, ['local-1']);
      expect(
        cache.read(
          userId: 'user-a',
          appId: motionPlusScope,
          productId: 'com.yulalab.jablab.motionplus.monthly',
        ),
        same(result),
      );
    },
  );

  test('pending and failed store events never reach verification', () async {
    final server = _Server((_) async => _verified());
    for (final kind in [StorePurchaseKind.pending, StorePurchaseKind.failed]) {
      expect(
        await coordinator(server).verifyAndComplete(_event(kind: kind)),
        isNull,
      );
    }
    expect(server.calls, 0);
    expect(store.completed, isEmpty);
  });

  test('wrong app or missing proof is rejected before the server', () async {
    final server = _Server((_) async => _verified());
    expect(
      await coordinator(server).verifyAndComplete(_event(appId: 'gravita')),
      isNull,
    );
    expect(
      await coordinator(server).verifyAndComplete(_event(proof: '')),
      isNull,
    );
    expect(server.calls, 0);
    expect(store.completed, isEmpty);
  });

  test('store assertion, wrong product and wrong user fail closed', () async {
    for (final status in [
      _verified(source: EntitlementSource.store),
      _verified(productId: 'another-product'),
      _verified(userId: 'user-b'),
    ]) {
      final server = _Server((_) async => status);
      expect(await coordinator(server).verifyAndComplete(_event()), isNull);
    }
    expect(store.completed, isEmpty);
    expect(
      cache.read(
        userId: 'user-a',
        appId: motionPlusScope,
        productId: 'com.yulalab.jablab.motionplus.monthly',
      ),
      isNull,
    );
  });

  test(
    'verified expired restore completes without unlocking a course',
    () async {
      final server = _Server((_) async => _verified(expiresAt: _now));
      expect(
        await coordinator(
          server,
        ).verifyAndComplete(_event(kind: StorePurchaseKind.restored)),
        isNull,
      );
      expect(store.completed, ['local-1']);
      expect(
        cache.read(
          userId: 'user-a',
          appId: motionPlusScope,
          productId: 'com.yulalab.jablab.motionplus.monthly',
        ),
        isNull,
      );
    },
  );

  test(
    'account switch while verification is in flight cannot grant purchase',
    () async {
      final response = Completer<EntitlementStatus?>();
      final server = _Server((_) => response.future);
      final pending = coordinator(server).verifyAndComplete(_event());
      signedInUser = 'user-b';
      response.complete(_verified());

      expect(await pending, isNull);
      expect(store.completed, isEmpty);
      expect(
        cache.read(
          userId: 'user-a',
          appId: motionPlusScope,
          productId: 'com.yulalab.jablab.motionplus.monthly',
        ),
        isNull,
      );
    },
  );
}
