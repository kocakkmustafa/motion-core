import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'motion_account_client.dart';

enum MotionIdentityPhase { signedOut, verifying, verified, unavailable }

/// One small bootstrap for every Motion app. Hosts only need this package;
/// the publishable key is public configuration, never a service-role secret.
class MotionAccountRuntime with WidgetsBindingObserver {
  MotionAccountRuntime._(
    this.account,
    this._client,
    this._onDeletedAccount,
    this._localAccountIds,
    this._wasAccountDeleted,
    this._receiptClient,
    this._receiptRetryDelay,
  ) : _userId = ValueNotifier<String?>(null),
      _phase = ValueNotifier<MotionIdentityPhase>(
        _client.auth.currentUser == null
            ? MotionIdentityPhase.signedOut
            : MotionIdentityPhase.verifying,
      ),
      _passwordRecovery = ValueNotifier<bool>(false) {
    _subscription = _client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _verificationGeneration++;
          _userId.value = null;
          _phase.value = MotionIdentityPhase.signedOut;
          unawaited(_reconcileWithoutUnhandledError());
        } else if (state.event == AuthChangeEvent.initialSession ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.passwordRecovery) {
          unawaited(_verifyWithoutUnhandledError());
        }
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _passwordRecovery.value = true;
        } else if (state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.userUpdated) {
          _passwordRecovery.value = false;
        }
      },
      onError: (Object _, StackTrace __) {
        _verificationGeneration++;
        _userId.value = null;
        _phase.value = _client.auth.currentUser == null
            ? MotionIdentityPhase.signedOut
            : MotionIdentityPhase.unavailable;
      },
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reconcileWithoutUnhandledError());
  }

  final MotionAccountClient account;
  final SupabaseClient _client;
  final Future<void> Function(String userId) _onDeletedAccount;
  final Future<Iterable<String>> Function() _localAccountIds;
  final Future<bool> Function(String userId) _wasAccountDeleted;
  final SupabaseClient? _receiptClient;
  final Duration _receiptRetryDelay;
  final ValueNotifier<String?> _userId;
  final ValueNotifier<MotionIdentityPhase> _phase;
  final ValueNotifier<bool> _passwordRecovery;
  late final StreamSubscription<AuthState> _subscription;
  int _verificationGeneration = 0;
  Future<void>? _reconciliation;
  Timer? _receiptRetry;
  bool _disposed = false;
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @visibleForTesting
  factory MotionAccountRuntime.forTesting({
    required SupabaseClient client,
    required MotionApp app,
    required Future<void> Function(String userId) onDeletedAccount,
    Future<Iterable<String>> Function()? localAccountIds,
    Future<bool> Function(String userId)? wasAccountDeleted,
    Duration receiptRetryDelay = const Duration(minutes: 2),
  }) => MotionAccountRuntime._(
    MotionAccountClient(
      supabase: client,
      app: app,
      emailRedirectTo: 'com.yulalab.${app.name}://auth/callback',
    ),
    client,
    onDeletedAccount,
    localAccountIds ?? () async => const <String>[],
    wasAccountDeleted ?? (_) async => false,
    null,
    receiptRetryDelay,
  );

  ValueListenable<String?> get userId => _userId;
  ValueListenable<MotionIdentityPhase> get phase => _phase;
  bool get isPasswordRecovery => _passwordRecovery.value;

  /// An offline user may use guest-only data after discarding the unverified
  /// cached session. Local account files are preserved for a later sign-in.
  Future<void> continueAsGuest() async {
    await _client.auth.signOut(scope: SignOutScope.local);
    if (_client.auth.currentUser != null) {
      throw StateError('Cached Motion session could not be cleared');
    }
    _verificationGeneration++;
    _userId.value = null;
    _phase.value = MotionIdentityPhase.signedOut;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reconcileWithoutUnhandledError());
    }
  }

  Future<void> _reconcileWithoutUnhandledError() async {
    try {
      await reconcileDeletedLocalAccounts();
      _receiptRetry?.cancel();
      _receiptRetry = null;
    } catch (_) {
      // An offline lookup is inconclusive. Preserve files and retry while the
      // app remains open, including after the network comes back.
      if (!_disposed) {
        _receiptRetry ??= Timer(_receiptRetryDelay, () {
          _receiptRetry = null;
          unawaited(_reconcileWithoutUnhandledError());
        });
      }
    }
  }

  /// Checks only IDs for which this app still owns local files. A normal
  /// sign-out never deletes history; a server deletion receipt does.
  Future<void> reconcileDeletedLocalAccounts() => _reconciliation ??=
      _scanDeletedLocalAccounts().whenComplete(() => _reconciliation = null);

  Future<void> _scanDeletedLocalAccounts() async {
    final ids = await _localAccountIds();
    for (final id in ids.toSet()) {
      if (_disposed) return;
      if (!_uuid.hasMatch(id)) continue;
      if (!await _wasAccountDeleted(id)) continue;
      if (_disposed) return;
      if (_client.auth.currentUser?.id == id) {
        _verificationGeneration++;
        _userId.value = null;
        _phase.value = MotionIdentityPhase.unavailable;
      }
      await _onDeletedAccount(id);
      if (_client.auth.currentUser?.id == id) {
        try {
          await _client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          // A deleted remote account cannot revoke an expired session.
        }
      }
    }
  }

  Future<void> _verifyWithoutUnhandledError() async {
    try {
      await refreshIdentity();
    } catch (_) {
      // The gate stays closed. The account page can trigger an explicit retry.
    }
  }

  /// Opens local history only after Auth confirms that the stored identity
  /// still exists. An offline/error response leaves the gate closed.
  Future<void> refreshIdentity() async {
    if (_disposed) return;
    final claimedId = _client.auth.currentUser?.id;
    final generation = ++_verificationGeneration;
    if (claimedId == null) {
      _userId.value = null;
      _phase.value = MotionIdentityPhase.signedOut;
      return;
    }
    if (_userId.value != claimedId) {
      _userId.value = null;
      _phase.value = MotionIdentityPhase.verifying;
    }

    try {
      final verified = await _client.auth.getUser();
      if (_disposed ||
          generation != _verificationGeneration ||
          _client.auth.currentUser?.id != claimedId) {
        return;
      }
      if (verified.user?.id != claimedId) {
        throw StateError('Motion account identity mismatch');
      }
      _userId.value = claimedId;
      _phase.value = MotionIdentityPhase.verified;
    } on AuthException catch (error) {
      if (_disposed ||
          generation != _verificationGeneration ||
          _client.auth.currentUser?.id != claimedId) {
        return;
      }
      _userId.value = null;
      _phase.value = MotionIdentityPhase.unavailable;
      if (error.code == 'user_not_found') {
        await _onDeletedAccount(claimedId);
        try {
          await _client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          // The deleted account has no remote session to revoke.
        }
        return;
      }
      rethrow;
    } catch (_) {
      if (!_disposed &&
          generation == _verificationGeneration &&
          _client.auth.currentUser?.id == claimedId) {
        _userId.value = null;
        _phase.value = MotionIdentityPhase.unavailable;
      }
      rethrow;
    }
  }

  static Future<MotionAccountRuntime> initialize({
    required String url,
    required String publishableKey,
    required MotionApp app,
    required String emailRedirectTo,
    required Future<void> Function(String userId) onDeletedAccount,
    required Future<Iterable<String>> Function() localAccountIds,
  }) async {
    final server = Uri.tryParse(url);
    final redirect = Uri.tryParse(emailRedirectTo);
    final localServer =
        server != null &&
        (server.host == 'localhost' || server.host == '127.0.0.1');
    if (server == null ||
        server.host.isEmpty ||
        (server.scheme != 'https' &&
            !(localServer && !kReleaseMode && server.scheme == 'http')) ||
        publishableKey.isEmpty ||
        redirect == null ||
        redirect.scheme != 'com.yulalab.${app.name}' ||
        redirect.host != 'auth' ||
        redirect.path != '/callback') {
      throw ArgumentError('Invalid Motion account configuration');
    }

    final supabase = await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUriPredicate: (uri) =>
            uri.scheme == redirect.scheme &&
            uri.host == redirect.host &&
            uri.path == redirect.path,
      ),
    );
    final client = supabase.client;
    // This client never receives the user's session, so a receipt remains
    // readable after Auth has already discarded an expired cached session.
    final receiptClient = SupabaseClient(
      url,
      publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return MotionAccountRuntime._(
      MotionAccountClient(
        supabase: client,
        app: app,
        emailRedirectTo: emailRedirectTo,
      ),
      client,
      onDeletedAccount,
      localAccountIds,
      (userId) async {
        final result = await receiptClient.rpc(
          'motion_was_account_deleted',
          params: {'p_user_id': userId},
        );
        if (result is! bool) throw StateError('Invalid deletion receipt');
        return result;
      },
      receiptClient,
      const Duration(minutes: 2),
    );
  }

  void dispose() {
    _disposed = true;
    _receiptRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _receiptClient?.dispose();
    _userId.dispose();
    _phase.dispose();
    _passwordRecovery.dispose();
  }
}
