import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:motion_entitlements/motion_entitlements.dart';

final _now = DateTime.utc(2026, 9, 24, 12);
const _product = 'com.yulalab.jablab.individual.monthly';

EntitlementStatus _snapshot({
  bool active = true,
  DateTime? verifiedAt,
  DateTime? expiresAt,
  String userId = 'user-a',
  String appId = 'jablab',
  String productId = _product,
}) => EntitlementStatus(
  state: active ? PurchaseState.entitled : PurchaseState.notEntitled,
  userId: userId,
  appId: appId,
  productId: productId,
  expiresAt: expiresAt ?? _now.add(const Duration(days: 30)),
  lastVerifiedAt: verifiedAt ?? _now,
  source: EntitlementSource.server,
);

StorePurchaseUpdate _event(String handle) => StorePurchaseUpdate(
  kind: StorePurchaseKind.restored,
  localHandle: handle,
  evidence: const StorePurchaseEvidence(
    platform: StorePlatform.ios,
    originatingAppId: 'jablab',
    productId: _product,
    verificationData: 'store-signed-proof',
  ),
);

class _Store implements PurchaseAdapter {
  final completed = <String>[];
  Future<void> Function(StorePurchaseUpdate)? onComplete;

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
    await onComplete?.call(update);
  }
}

class _Server implements ServerAdapter {
  _Server(this.callback);
  final Future<EntitlementStatus?> Function(StorePurchaseEvidence) callback;

  @override
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence) =>
      callback(evidence);
}

class _Context {
  _Context({EntitlementCache? cache})
    : cache = cache ?? InMemoryEntitlementCache();

  final EntitlementCache cache;
  final store = _Store();
  String userId = 'user-a';
  DateTime clock = _now;

  EntitlementStatus? get cached =>
      cache.read(userId: 'user-a', appId: 'jablab', productId: _product);

  PurchaseCoordinator coordinator(
    Future<EntitlementStatus?> Function(StorePurchaseEvidence) verify,
  ) => PurchaseCoordinator(
    appId: 'jablab',
    currentUserId: () => userId,
    store: store,
    server: _Server(verify),
    cache: cache,
    now: () => clock,
  );
}

// A public cache implementation may deserialize a fresh object on every read.
class _CopyingCache implements EntitlementCache {
  final _cache = InMemoryEntitlementCache();

  @override
  EntitlementStatus? read({
    required String userId,
    required String appId,
    required String productId,
  }) {
    final value = _cache.read(
      userId: userId,
      appId: appId,
      productId: productId,
    );
    if (value == null) return null;
    return EntitlementStatus(
      state: value.state,
      userId: value.userId,
      appId: value.appId,
      productId: value.productId,
      expiresAt: value.expiresAt,
      lastVerifiedAt: value.lastVerifiedAt,
      source: value.source,
    );
  }

  @override
  void write(EntitlementStatus status) => _cache.write(status);

  @override
  void clearUser(String userId) => _cache.clearUser(userId);
}

void main() {
  for (final olderActive in [true, false]) {
    test('older ${olderActive ? 'grant' : 'denial'} cannot replace a newer '
        'shared-cache observation', () async {
      final context = _Context();
      final olderResponse = Completer<EntitlementStatus?>();
      final newerResponse = Completer<EntitlementStatus?>();
      final olderCoordinator = context.coordinator((_) => olderResponse.future);
      final newerCoordinator = context.coordinator((_) => newerResponse.future);
      expect(identical(olderCoordinator, newerCoordinator), isFalse);
      final older = olderCoordinator.verifyAndComplete(_event('older'));
      final newer = newerCoordinator.verifyAndComplete(_event('newer'));
      final newerStatus = _snapshot(
        active: !olderActive,
        verifiedAt: _now.subtract(const Duration(seconds: 1)),
      );
      newerResponse.complete(newerStatus);
      expect(await newer, olderActive ? isNull : same(newerStatus));
      expect(context.cached, same(newerStatus));
      olderResponse.complete(
        _snapshot(
          active: olderActive,
          verifiedAt: _now.subtract(const Duration(seconds: 2)),
        ),
      );
      expect(await older, isNull);
      expect(context.cached, same(newerStatus));
      expect(context.store.completed, ['newer', 'older']);
    });
  }

  for (final denial in ['revoked', 'expired']) {
    for (final denialFirst in [true, false]) {
      test(
        'equal timestamp $denial wins with denialFirst=$denialFirst',
        () async {
          final context = _Context();
          final denied = _snapshot(
            active: denial != 'revoked',
            expiresAt: denial == 'expired' ? _now : null,
          );
          final granted = _snapshot();
          final first = denialFirst ? denied : granted;
          final second = denialFirst ? granted : denied;
          await context
              .coordinator((_) async => first)
              .verifyAndComplete(_event('first'));
          final result = await context
              .coordinator((_) async => second)
              .verifyAndComplete(_event('second'));
          expect(result, isNull);
          expect(context.cached, same(denied));
          expect(context.store.completed, ['first', 'second']);
        },
      );
    }
  }

  test('strictly newer grant can recover a verified denial', () async {
    final context = _Context();
    context.cache.write(
      _snapshot(
        active: false,
        verifiedAt: _now.subtract(const Duration(seconds: 1)),
      ),
    );
    final recovered = _snapshot();
    expect(
      await context
          .coordinator((_) async => recovered)
          .verifyAndComplete(_event('recovered')),
      same(recovered),
    );
    expect(context.cached, same(recovered));
  });

  for (final shorterFirst in [true, false]) {
    test('equal active timestamp cannot extend expiry with '
        'shorterFirst=$shorterFirst', () async {
      final context = _Context();
      final shorter = _snapshot(expiresAt: _now.add(const Duration(days: 1)));
      final longer = _snapshot(expiresAt: _now.add(const Duration(days: 2)));
      final first = shorterFirst ? shorter : longer;
      final second = shorterFirst ? longer : shorter;
      context.cache.write(first);
      final result = await context
          .coordinator((_) async => second)
          .verifyAndComplete(_event('tie'));
      expect(context.cached, same(shorter));
      expect(result, shorterFirst ? isNull : same(shorter));
    });
  }

  test(
    'unrelated owner app and product cannot block this older observation',
    () async {
      final context = _Context();
      final unrelated = [
        _snapshot(userId: 'user-b', active: false),
        _snapshot(appId: 'lissom', active: false),
        _snapshot(productId: 'another-product', active: false),
      ];
      for (final value in unrelated) {
        context.cache.write(value);
      }
      final mine = _snapshot(
        verifiedAt: _now.subtract(const Duration(seconds: 1)),
      );
      expect(
        await context
            .coordinator((_) async => mine)
            .verifyAndComplete(_event('mine')),
        same(mine),
      );
      expect(context.cached, same(mine));
      for (final value in unrelated) {
        expect(
          context.cache.read(
            userId: value.userId,
            appId: value.appId,
            productId: value.productId,
          ),
          same(value),
        );
      }
    },
  );

  test(
    'late provider error preserves a newer denial and pending store work',
    () async {
      final context = _Context();
      final failedResponse = Completer<EntitlementStatus?>();
      final failed = context
          .coordinator((_) => failedResponse.future)
          .verifyAndComplete(_event('failed'));
      final error = expectLater(failed, throwsStateError);
      final denied = _snapshot(active: false);
      await context
          .coordinator((_) async => denied)
          .verifyAndComplete(_event('denied'));
      failedResponse.completeError(StateError('provider unavailable'));
      await error;
      expect(context.cached, same(denied));
      expect(context.store.completed, ['denied']);
    },
  );

  test('cached snapshot comparison supports a deserializing cache', () async {
    final context = _Context(cache: _CopyingCache());
    final granted = _snapshot();
    expect(
      await context
          .coordinator((_) async => granted)
          .verifyAndComplete(_event('copy')),
      same(granted),
    );
    expect(identical(context.cached, granted), isFalse);
    expect(
      context.cached?.grantsAccessAt(_now, userId: 'user-a', appId: 'jablab'),
      isTrue,
    );
  });

  for (final newerActive in [true, false]) {
    test('newer ${newerActive ? 'grant' : 'denial'} during store completion '
        'prevents publishing the old grant', () async {
      final context = _Context();
      final completing = Completer<void>();
      final release = Completer<void>();
      context.store.onComplete = (update) async {
        if (update.localHandle == 'old') {
          completing.complete();
          await release.future;
        }
      };
      final oldStatus = _snapshot(
        verifiedAt: _now.subtract(const Duration(seconds: 1)),
      );
      final older = context
          .coordinator((_) async => oldStatus)
          .verifyAndComplete(_event('old'));
      await completing.future;
      final newest = _snapshot(active: newerActive);
      expect(
        await context
            .coordinator((_) async => newest)
            .verifyAndComplete(_event('new')),
        newerActive ? same(newest) : isNull,
      );
      release.complete();
      expect(await older, isNull);
      expect(context.cached, same(newest));
      expect(context.store.completed, ['old', 'new']);
    });
  }

  test(
    'account switch during store completion cannot publish the old grant',
    () async {
      final context = _Context();
      final completing = Completer<void>();
      final release = Completer<void>();
      context.store.onComplete = (_) {
        completing.complete();
        return release.future;
      };
      final granting = context
          .coordinator((_) async => _snapshot())
          .verifyAndComplete(_event('switch'));
      await completing.future;
      context.userId = 'user-b';
      release.complete();
      expect(await granting, isNull);
      expect(context.store.completed, ['switch']);
    },
  );

  test('expiry during store completion cannot publish a grant', () async {
    final context = _Context();
    final completing = Completer<void>();
    final release = Completer<void>();
    context.store.onComplete = (_) {
      completing.complete();
      return release.future;
    };
    final granting = context
        .coordinator(
          (_) async =>
              _snapshot(expiresAt: _now.add(const Duration(seconds: 1))),
        )
        .verifyAndComplete(_event('expiry'));
    await completing.future;
    context.clock = _now.add(const Duration(seconds: 2));
    release.complete();
    expect(await granting, isNull);
    expect(context.store.completed, ['expiry']);
  });
}
