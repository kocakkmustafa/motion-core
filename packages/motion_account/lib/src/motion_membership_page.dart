import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:motion_platform_signals/motion_platform_signals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'motion_account_client.dart';
import 'motion_account_localizations.dart';
import 'motion_release_policy.dart';

/// One small store-owned membership surface shared by the five host apps.
/// Prices are shown only after the installed app's store returns real offers.
class MotionMembershipPage extends StatefulWidget {
  const MotionMembershipPage({
    super.key,
    required this.account,
    this.purchaseAdapter,
    this.serverAdapter,
    this.teenPurchasePolicy = MotionTeenPurchasePolicy.parentalConsentRequired,
  });

  final MotionAccountClient account;
  final PurchaseAdapter? purchaseAdapter;
  final ServerAdapter? serverAdapter;

  /// This host's rule for a consent-pending teen (see
  /// [MotionTeenPurchasePolicy]). Defaults to no purchase until approval.
  final MotionTeenPurchasePolicy teenPurchasePolicy;

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
  // A teen below the consent age without parent approval is not offered a
  // purchase unless the host leaves it to the store's family controls.
  // Restoring an existing store purchase stays available.
  bool _consentRequired = false;
  bool _storeFamilyControls = false;
  MotionAccountString? _message;

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
          // One Motion+ free trial per Motion account (server ledger).
          trialGate: SupabaseMotionTrialGate(
            supabase: widget.account.supabase,
            appId: _appId,
            appTransactionId: MotionPlatformSignals.appTransactionId,
          ),
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
          _message = MotionAccountString.storeConnectionFailed;
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
          _message = MotionAccountString.membershipReopen;
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

  String _text(MotionAccountString key) =>
      MotionAccountLocalizations.of(context).text(key);

  String _currentBenefit() => _text(MotionAccountString.guidedBenefit);

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
      final age = await _ageStatus();
      if (!mounted || !_sameUser) return;
      final today = DateTime.now();
      final policy = widget.teenPurchasePolicy;
      _storeFamilyControls =
          age?.storeDecidesPurchaseOn(today, policy) ?? false;
      if (age?.purchaseRestrictedOn(today, policy) ?? false) {
        setState(() {
          _consentRequired = true;
          _offers = const [];
        });
        return;
      }
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
        () => _message = MotionAccountString.membershipDetailsUnavailable,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Unknown status does not invent a restriction; the server's RLS and the
  /// account page still enforce consent for account features.
  Future<MotionAgeStatus?> _ageStatus() async {
    try {
      return await Future.sync(widget.account.ageStatus);
    } catch (_) {
      return null;
    }
  }

  Future<void> _buy(StoreProductRef offer) async {
    if (_busy ||
        _active ||
        _consentRequired ||
        !_sameUser ||
        (_anyActive && _isMotionPlus(offer)))
      return;
    setState(() {
      _busy = true;
      _message = MotionAccountString.openingStore;
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
          _message = MotionAccountString.membershipChanged;
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
        _message = MotionAccountString.purchaseStartFailed;
      });
    }
  }

  Future<void> _restore() async {
    if (_busy || !_sameUser) return;
    setState(() {
      _busy = true;
      _message = MotionAccountString.lookingForPurchases;
    });
    try {
      await _store.restore();
      if (!mounted || !_sameUser) return;
      setState(() {
        _busy = false;
        _message = MotionAccountString.foundPurchases;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = MotionAccountString.restoreFailed;
      });
    }
  }

  Future<void> _handleUpdate(StorePurchaseUpdate update) async {
    if (!mounted || !_sameUser) return;
    if (update.kind == StorePurchaseKind.pending) {
      setState(() => _message = MotionAccountString.waitingStore);
      return;
    }
    if (update.kind == StorePurchaseKind.canceled ||
        update.kind == StorePurchaseKind.failed) {
      setState(() {
        _busy = false;
        _message = update.kind == StorePurchaseKind.canceled
            ? MotionAccountString.purchaseCanceled
            : MotionAccountString.storePurchaseFailed;
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
          _message = MotionAccountString.membershipActive;
        } else {
          _message = MotionAccountString.purchaseNotVerified;
        }
      });
    } catch (_) {
      if (!mounted || !_sameUser) return;
      setState(() {
        _busy = false;
        _message = MotionAccountString.verificationUnavailable;
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
    setState(() => _message = MotionAccountString.storeSubscriptionOpenFailed);
  }

  Future<void> _openLegal(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Browser availability is outside the purchase flow.
    }
    if (!mounted) return;
    setState(() => _message = MotionAccountString.linkOpenFailed);
  }

  bool _isMotionPlus(StoreProductRef offer) =>
      offer.productId.contains('motionplus') ||
      offer.productId.endsWith('_motion_plus');

  Widget _offer(StoreProductRef offer) {
    final period = offer.planId == 'yearly'
        ? _text(MotionAccountString.yearly)
        : _text(MotionAccountString.monthly);
    // A free trial is shown only when the store offered it to this account
    // (StoreProductRef.freeTrialPeriod); the recurring price follows it.
    final trialDays = offer.freeTrialDays;
    return ListTile(
      title: Text(period),
      subtitle: Text(
        trialDays == null
            ? offer.localizedPrice
            : MotionAccountLocalizations.of(context).trialThenPrice(
                yearly: offer.planId == 'yearly',
                days: trialDays,
                price: offer.localizedPrice,
              ),
      ),
      trailing: FilledButton(
        onPressed: _busy ? null : () => _buy(offer),
        child: Text(_text(MotionAccountString.choose)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appName = _appId[0].toUpperCase() + _appId.substring(1);
    return Scaffold(
      appBar: AppBar(title: Text(_text(MotionAccountString.membershipTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_text(_message!))),
            ],
            if (!_sameUser)
              Text(_text(MotionAccountString.signInFirst))
            else if (_consentRequired)
              Text(_text(MotionAccountString.parentalConsentNeeded))
            else if (_active)
              Text(_text(MotionAccountString.yourMembershipActive))
            else if (!_busy &&
                (_anyActive
                    ? _offers.where((offer) => !_isMotionPlus(offer)).isEmpty
                    : _offers.isEmpty))
              Text(_text(MotionAccountString.storeMembershipsUnavailable))
            else ...[
              Text(
                MotionAccountLocalizations.of(
                  context,
                ).membershipForApp(appName),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(_currentBenefit()),
              for (final offer in _offers.where((o) => !_isMotionPlus(o)))
                _offer(offer),
              const SizedBox(height: 16),
              if (_anyActive)
                Text(_text(MotionAccountString.otherSubscription))
              else ...[
                Text('Motion+', style: Theme.of(context).textTheme.titleLarge),
                Text(_text(MotionAccountString.motionPlusBenefit)),
                for (final offer in _offers.where(_isMotionPlus)) _offer(offer),
              ],
              const SizedBox(height: 12),
              Text(_text(MotionAccountString.autoRenewTerms)),
              if (_storeFamilyControls)
                Text(_text(MotionAccountString.storeFamilyControlsNote)),
              if (_offers.any((offer) => offer.freeTrialDays != null))
                Text(_text(MotionAccountString.trialRenewTerms)),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy || !_sameUser ? null : _restore,
              child: Text(_text(MotionAccountString.restorePurchases)),
            ),
            TextButton(
              onPressed: _busy ? null : _load,
              child: Text(_text(MotionAccountString.refreshStatus)),
            ),
            TextButton(
              onPressed: _manage,
              child: Text(_text(MotionAccountString.manageInStore)),
            ),
            TextButton(
              onPressed: () =>
                  _openLegal(Uri.parse('https://yulalab.com/terms')),
              child: Text(_text(MotionAccountString.termsOfUse)),
            ),
            TextButton(
              onPressed: () =>
                  _openLegal(Uri.parse('https://yulalab.com/privacy/motion')),
              child: Text(_text(MotionAccountString.privacyPolicyTitle)),
            ),
            Text(_text(MotionAccountString.subscriptionDisclosure)),
          ],
        ),
      ),
    );
  }
}
