import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'motion_account_client.dart';

/// One small store-owned membership surface shared by the five host apps.
/// Prices are shown only after the installed app's store returns real offers.
class MotionMembershipPage extends StatefulWidget {
  const MotionMembershipPage({
    super.key,
    required this.account,
    this.purchaseAdapter,
    this.serverAdapter,
  });

  final MotionAccountClient account;
  final PurchaseAdapter? purchaseAdapter;
  final ServerAdapter? serverAdapter;

  @override
  State<MotionMembershipPage> createState() => _MotionMembershipPageState();
}

class _MotionMembershipPageState extends State<MotionMembershipPage> {
  late final PurchaseAdapter _store;
  late final PurchaseCoordinator _coordinator;
  StreamSubscription<StorePurchaseUpdate>? _subscription;
  StreamSubscription<AuthState>? _authSubscription;
  late final String? _openingUserId;
  late final Session? _openingSession;
  List<StoreProductRef> _offers = const [];
  bool _busy = true;
  bool _active = false;
  bool _anyActive = false;
  bool _authStreamFailed = false;
  String? _message;

  String get _appId => widget.account.app.name;
  bool get _sameUser =>
      !_authStreamFailed &&
      _openingUserId != null &&
      identical(widget.account.supabase.auth.currentSession, _openingSession) &&
      widget.account.currentUser?.id == _openingUserId;

  @override
  void initState() {
    super.initState();
    _openingUserId = widget.account.currentUser?.id;
    _openingSession = widget.account.supabase.auth.currentSession;
    _store =
        widget.purchaseAdapter ??
        FlutterPurchaseAdapter(
          appId: _appId,
          currentUserId: () => widget.account.currentUser?.id,
        );
    _coordinator = PurchaseCoordinator(
      appId: _appId,
      currentUserId: () => _sameUser ? _openingUserId! : '',
      store: _store,
      server:
          widget.serverAdapter ??
          SupabasePurchaseServerAdapter(widget.account.supabase),
      cache: InMemoryEntitlementCache(),
      now: DateTime.now,
    );
    _subscription = _store.updates.listen(
      (update) => unawaited(_handleUpdate(update)),
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = _t(
            'Mağaza bağlantısı kesildi. Yeniden dene.',
            'Store connection failed. Try again.',
          );
        });
      },
    );
    _authSubscription = widget.account.authChanges.listen(
      (_) {
        if (!mounted || _authStreamFailed || _sameUser) return;
        setState(() {
          _offers = const [];
          _active = false;
          _anyActive = false;
          _busy = false;
          _message = null;
        });
      },
      onError: (Object _, StackTrace _) {
        if (!mounted) return;
        setState(() {
          // Cached same-UUID auth events do not reauthorize this page. The host
          // must retry verified identity and open a new membership lifetime.
          _authStreamFailed = true;
          _offers = const [];
          _active = false;
          _anyActive = false;
          _busy = false;
          _message = _t(
            'Hesabın yenilenemedi. Hesabını tekrar doğrulayıp üyelik ekranını yeniden aç.',
            'Could not refresh your account. Reopen membership after retrying your account.',
          );
        });
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  String _t(String tr, String en) =>
      Localizations.localeOf(context).languageCode == 'tr' ? tr : en;

  String _currentBenefit() => _t(
    'Bu uygulamadaki kullanılabilir rehberli seanslara erişim sağlar. Satın almadan önce kataloğu incele.',
    'Provides access to available guided sessions in this app. Check the catalog before purchasing.',
  );

  List<String> _productIds() =>
      Theme.of(context).platform == TargetPlatform.android
      ? ['${_appId}_individual', '${_appId}_motion_plus']
      : [
          for (final scope in ['individual', 'motionplus'])
            for (final period in ['monthly', 'yearly'])
              'com.yulalab.$_appId.$scope.$period',
        ];

  Future<void> _load() async {
    if (!_sameUser) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await widget.account.membershipStatus();
      if (!mounted || !_sameUser) return;
      final offers = status.active
          ? const <StoreProductRef>[]
          : await _store.fetchProducts(_productIds());
      if (!mounted || !_sameUser) return;
      setState(() {
        _active = status.active;
        _anyActive = status.anyActive;
        _offers = offers;
      });
    } catch (_) {
      if (!mounted || !_sameUser) return;
      setState(
        () => _message = _t(
          'Üyelik veya mağaza bilgisi alınamadı. Yeniden dene.',
          'Membership or store details are unavailable. Try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(StoreProductRef offer) async {
    if (_busy || _active || !_sameUser || (_anyActive && _isMotionPlus(offer)))
      return;
    setState(() {
      _busy = true;
      _message = _t('Mağaza açılıyor…', 'Opening the store…');
    });
    try {
      // Another app may have purchased since this page loaded. Recheck before
      // opening the platform payment sheet, while preserving separate app
      // subscriptions when only a different app is active.
      final status = await widget.account.membershipStatus();
      if (!mounted || !_sameUser) return;
      if (status.active || (status.anyActive && _isMotionPlus(offer))) {
        setState(() {
          _active = status.active;
          _anyActive = status.anyActive;
          _busy = false;
          _message = _t(
            'Üyelik durumu değişti. Seçenekleri yenile.',
            'Membership changed. Refresh the options.',
          );
        });
        return;
      }
      setState(() {
        _active = status.active;
        _anyActive = status.anyActive;
      });
      await _store.startPurchase(offer);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _t(
          'Satın alma başlatılamadı. Yeniden dene.',
          'Could not start the purchase. Try again.',
        );
      });
    }
  }

  Future<void> _restore() async {
    if (_busy || !_sameUser) return;
    setState(() {
      _busy = true;
      _message = _t('Satın almalar aranıyor…', 'Looking for purchases…');
    });
    try {
      await _store.restore();
      if (!mounted || !_sameUser) return;
      setState(() {
        _busy = false;
        _message = _t(
          'Bulunan satın almalar doğrulanacak. Üyelik görünmüyorsa durumu yenile.',
          'Found purchases will be verified. Refresh status if membership does not appear.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _t(
          'Satın almalar geri yüklenemedi. Yeniden dene.',
          'Could not restore purchases. Try again.',
        );
      });
    }
  }

  Future<void> _handleUpdate(StorePurchaseUpdate update) async {
    if (!mounted || !_sameUser) return;
    if (update.kind == StorePurchaseKind.pending) {
      setState(
        () => _message = _t(
          'Mağaza işlemi bekleniyor…',
          'Waiting for the store…',
        ),
      );
      return;
    }
    if (update.kind == StorePurchaseKind.canceled ||
        update.kind == StorePurchaseKind.failed) {
      setState(() {
        _busy = false;
        _message = update.kind == StorePurchaseKind.canceled
            ? _t('Satın alma iptal edildi.', 'Purchase canceled.')
            : _t('Mağaza işlemi başarısız oldu.', 'Store purchase failed.');
      });
      return;
    }
    try {
      final result = await _coordinator.verifyAndComplete(update);
      if (!mounted || !_sameUser) return;
      setState(() {
        _busy = false;
        if (result != null) {
          _active = true;
          _anyActive = true;
          _offers = const [];
          _message = _t('Üyelik etkin.', 'Membership active.');
        } else {
          _message = _t(
            'Satın alma henüz doğrulanamadı. Bağlantını kontrol edip tekrar dene.',
            'Purchase could not be verified yet. Check your connection and try again.',
          );
        }
      });
    } catch (_) {
      if (!mounted || !_sameUser) return;
      setState(() {
        _busy = false;
        _message = _t(
          'Doğrulama şu anda kullanılamıyor. Tekrar dene veya satın almaları geri yükle.',
          'Verification is unavailable. Try again or restore purchases.',
        );
      });
    }
  }

  Future<void> _manage() async {
    final uri = Uri.parse(
      Theme.of(context).platform == TargetPlatform.android
          ? 'https://play.google.com/store/account/subscriptions'
          : 'https://apps.apple.com/account/subscriptions',
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // The store app or a browser may be unavailable on this device.
    }
    if (!mounted) return;
    setState(
      () => _message = _t(
        'Mağaza abonelik sayfası açılamadı.',
        'Could not open the store subscription page.',
      ),
    );
  }

  Future<void> _openLegal(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Browser availability is outside the purchase flow.
    }
    if (!mounted) return;
    setState(
      () => _message = _t(
        'Bağlantı açılamadı. Daha sonra tekrar dene.',
        'Could not open the link. Try again later.',
      ),
    );
  }

  bool _isMotionPlus(StoreProductRef offer) =>
      offer.productId.contains('motionplus') ||
      offer.productId.endsWith('_motion_plus');

  Widget _offer(StoreProductRef offer) {
    final period = offer.planId == 'yearly'
        ? _t('Yıllık', 'Yearly')
        : _t('Aylık', 'Monthly');
    return ListTile(
      title: Text(period),
      subtitle: Text(offer.localizedPrice),
      trailing: FilledButton(
        onPressed: _busy ? null : () => _buy(offer),
        child: Text(_t('Seç', 'Choose')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appName = _appId[0].toUpperCase() + _appId.substring(1);
    return Scaffold(
      appBar: AppBar(title: Text(_t('Üyelik', 'Membership'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_message!)),
            ],
            if (!_sameUser)
              Text(
                _t(
                  'Önce Motion hesabına giriş yap.',
                  'Sign in to your Motion account first.',
                ),
              )
            else if (_active)
              Text(
                _t(
                  'Bu uygulamada üyeliğin aktif.',
                  'Your membership is active in this app.',
                ),
              )
            else if (!_busy &&
                (_anyActive
                    ? _offers.where((offer) => !_isMotionPlus(offer)).isEmpty
                    : _offers.isEmpty))
              Text(
                _t(
                  'Mağaza üyelikleri şu anda sunmuyor. Daha sonra tekrar dene.',
                  'Store memberships are unavailable right now. Try again later.',
                ),
              )
            else ...[
              Text(
                '$appName ${_t('üyeliği', 'membership')}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(_currentBenefit()),
              for (final offer in _offers.where((o) => !_isMotionPlus(o)))
                _offer(offer),
              const SizedBox(height: 16),
              if (_anyActive)
                Text(
                  _t(
                    'Başka bir Motion uygulamasında aktif aboneliğin var. Bu uygulamanın ayrı üyeliğini alabilirsin. Çift ödeme riskini önlemek için Motion+ seçeneği mevcut aboneliğin bitene kadar kapalı; aboneliğini mağazada yönet.',
                    'You have a subscription in another Motion app. You can buy this app\'s separate membership. Motion+ is unavailable until the existing subscription ends to avoid overlapping charges; manage it in the store.',
                  ),
                )
              else ...[
                Text('Motion+', style: Theme.of(context).textTheme.titleLarge),
                Text(
                  _t(
                    'Beş Motion uygulamasındaki bugün açık olan canlı çalışmalara erişim. Gelecek dersler bu sürümde yok.',
                    'Access the live practice currently available in all five Motion apps. Future lessons are not in this release.',
                  ),
                ),
                for (final offer in _offers.where(_isMotionPlus)) _offer(offer),
              ],
              const SizedBox(height: 12),
              Text(
                _t(
                  'Aylık veya yıllık paket, mağazada gösterilen tutardan iptal edilene kadar aynı dönemle otomatik yenilenir. İptali mağaza hesabından yönetebilirsin.',
                  'Monthly or yearly plans renew automatically for the same period at the displayed store price until canceled. Manage cancellation in your store account.',
                ),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy || !_sameUser ? null : _restore,
              child: Text(_t('Satın almaları geri yükle', 'Restore purchases')),
            ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(_t('Durumu yenile', 'Refresh status')),
            ),
            TextButton(
              onPressed: _manage,
              child: Text(
                _t(
                  'Mağazada aboneliği yönet',
                  'Manage subscription in the store',
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  _openLegal(Uri.parse('https://yulalab.com/terms')),
              child: Text(_t('Kullanım şartları', 'Terms of Use')),
            ),
            TextButton(
              onPressed: () =>
                  _openLegal(Uri.parse('https://yulalab.com/privacy/motion')),
              child: Text(_t('Gizlilik politikası', 'Privacy Policy')),
            ),
            Text(
              _t(
                'Abonelik seçtiğin dönemde otomatik yenilenir. Tutar ve para birimi mağazada gösterilir; iptal işlemi mağaza hesabından yapılır.',
                'Subscriptions renew automatically for the selected period. The store shows the amount and currency; cancel from your store account.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
