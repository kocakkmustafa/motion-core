import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'motion_account_client.dart';
import 'motion_account_deadline.dart';

enum MotionIdentityPhase { signedOut, verifying, verified, unavailable }

class _IdentityVerificationNotifier extends ChangeNotifier {
  int _pulseDepth = 0;
  bool _closeRequested = false;
  bool _closed = false;

  void pulse() {
    if (_closeRequested) return;
    _pulseDepth++;
    try {
      notifyListeners();
    } finally {
      _pulseDepth--;
      _closeWhenIdle();
    }
  }

  void close() {
    if (_closeRequested) return;
    _closeRequested = true;
    _closeWhenIdle();
  }

  void _closeWhenIdle() {
    if (!_closeRequested || _pulseDepth != 0 || _closed) return;
    _closed = true;
    super.dispose();
  }
}

/// Public value notifications may synchronously retire their owning runtime.
class _OwnedValueNotifier<T> extends ValueNotifier<T> {
  _OwnedValueNotifier(super.value);
  int _depth = 0;
  bool _closing = false;
  bool _closed = false;

  @override
  set value(T next) {
    if (_closing) return;
    super.value = next;
  }

  @override
  void notifyListeners() {
    if (_closing) return;
    _depth++;
    try {
      super.notifyListeners();
    } finally {
      _depth--;
      _closeWhenIdle();
    }
  }

  void close() {
    _closing = true;
    _closeWhenIdle();
  }

  void _closeWhenIdle() {
    if (!_closing || _depth != 0 || _closed) return;
    _closed = true;
    super.dispose();
  }
}

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
    this._identityVerificationTimeout,
    this._identityTotalTimeout,
    this._receiptReadTimeout,
    this._reconcileTimeout,
    this._guestTimeout,
  ) : _userId = _OwnedValueNotifier<String?>(null),
      _phase = _OwnedValueNotifier<MotionIdentityPhase>(
        _client.auth.currentUser == null
            ? MotionIdentityPhase.signedOut
            : MotionIdentityPhase.verifying,
      ),
      _passwordRecovery = _OwnedValueNotifier<bool>(false) {
    _observedSession = _client.auth.currentSession;
    _subscription = _client.auth.onAuthStateChange.listen(
      (state) {
        if (_disposed) return;
        _observeCurrentSession();
        if (_disposed) return;
        if (state.event == AuthChangeEvent.signedOut) {
          _verificationGeneration++;
          _clearIdentityProof();
          _userId.value = null;
          _phase.value = MotionIdentityPhase.signedOut;
          _notifyIdentityVerification();
          if (_disposed) return;
          unawaited(_reconcileWithoutUnhandledError());
        } else if (state.event == AuthChangeEvent.initialSession ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.passwordRecovery ||
            state.event == AuthChangeEvent.userUpdated) {
          unawaited(_verifyWithoutUnhandledError());
        }
        if (_disposed) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _recoveryUserId = _client.auth.currentUser?.id;
          _passwordRecovery.value = true;
        } else if (state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.userUpdated ||
            _client.auth.currentUser?.id != _recoveryUserId) {
          _recoveryUserId = null;
          _passwordRecovery.value = false;
        }
      },
      onError: (Object _, StackTrace __) {
        if (_disposed) return;
        _observeCurrentSession();
        if (_disposed) return;
        _verificationGeneration++;
        _clearIdentityProof();
        _userId.value = null;
        _phase.value = _client.auth.currentUser == null
            ? MotionIdentityPhase.signedOut
            : MotionIdentityPhase.unavailable;
        _notifyIdentityVerification();
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
  final Duration _identityVerificationTimeout;
  // One budget covers getUser plus any admitted cleanup/logout it triggers.
  final Duration _identityTotalTimeout;
  // Per-UUID receipt read and the whole reconciliation pass.
  final Duration _receiptReadTimeout;
  final Duration _reconcileTimeout;
  final Duration _guestTimeout;
  // Admitted per-UUID cleanup. A UUID's erase runs at most once at a time:
  // identity, receipt and retried passes join the same ticket. A caller's
  // deadline ends only its own wait, never the admitted cleanup.
  final Map<String, Future<void>> _admittedCleanups = {};
  final _OwnedValueNotifier<bool> _cleanupPending = _OwnedValueNotifier<bool>(
    false,
  );
  final _OwnedValueNotifier<String?> _userId;
  final _OwnedValueNotifier<MotionIdentityPhase> _phase;
  final _OwnedValueNotifier<bool> _passwordRecovery;
  final _IdentityVerificationNotifier _identityVerification =
      _IdentityVerificationNotifier();
  Session? _acceptedSession;
  String? _acceptedUserId;
  String? _acceptedAccessToken;
  // Observation only: this reference is neither proof nor a host storage epoch.
  Session? _observedSession;
  late final StreamSubscription<AuthState> _subscription;
  int _verificationGeneration = 0;
  String? _recoveryUserId;
  Future<void>? _reconciliation;
  Object? _reconciliationPass;
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
    Duration identityVerificationTimeout = const Duration(seconds: 10),
    Duration identityTotalTimeout = const Duration(seconds: 20),
    Duration receiptReadTimeout = const Duration(seconds: 10),
    Duration reconcileTimeout = const Duration(seconds: 20),
    Duration guestTimeout = const Duration(seconds: 20),
    Duration operationTimeout = const Duration(seconds: 20),
  }) {
    final receipt = wasAccountDeleted ?? (_) async => false;
    return MotionAccountRuntime._(
      MotionAccountClient(
        supabase: client,
        app: app,
        emailRedirectTo: 'com.yulalab.${app.name}://auth/callback',
        deletionReceipt: receipt,
        operationTimeout: operationTimeout,
        readTimeout: receiptReadTimeout,
      ),
      client,
      onDeletedAccount,
      localAccountIds ?? () async => const <String>[],
      receipt,
      null,
      receiptRetryDelay,
      identityVerificationTimeout,
      identityTotalTimeout,
      receiptReadTimeout,
      reconcileTimeout,
      guestTimeout,
    );
  }

  ValueListenable<String?> get userId => _userId;

  /// True while an admitted, server-confirmed local cleanup is still running
  /// after its caller stopped waiting. Hosts may show "cleanup pending"; this
  /// is never a success receipt and never authority to erase anything else.
  ValueListenable<bool> get localCleanupPending => _cleanupPending;
  ValueListenable<MotionIdentityPhase> get phase => _phase;

  /// Runtime retirement is distinct from a temporarily absent Auth proof.
  /// The final identityVerification notification observes this as true.
  bool get isDisposed => _disposed;

  /// Whether Auth has verified the exact Session that is current now.
  ///
  /// A same-UUID/token replacement has no inherited proof. A valid proof for
  /// the unchanged Session stays usable while an ordinary refresh is pending.
  /// This is current proof, not evidence that a particular awaited call won.
  bool get isCurrentSessionVerified {
    final current = _client.auth.currentSession;
    return !_disposed &&
        current != null &&
        _acceptedSession != null &&
        identical(current, _acceptedSession) &&
        current.user.id == _acceptedUserId &&
        current.accessToken == _acceptedAccessToken &&
        _userId.value == _acceptedUserId &&
        _phase.value == MotionIdentityPhase.verified;
  }

  /// Notifies after accepted proof, invalidation, or observed replacement.
  ///
  /// Query isCurrentSessionVerified when notified and at admission boundaries.
  /// An eventless external SDK mutation cannot notify until it is observed.
  /// This listenable carries no Session, token, or host storage epoch.
  Listenable get identityVerification => _identityVerification;

  void _clearIdentityProof() {
    _acceptedSession = null;
    _acceptedUserId = null;
    _acceptedAccessToken = null;
  }

  void _notifyIdentityVerification() {
    if (!_disposed) _identityVerification.pulse();
  }

  void _observeCurrentSession() {
    if (_disposed) return;
    final current = _client.auth.currentSession;
    if (identical(current, _observedSession)) return;
    _observedSession = current;
    _clearIdentityProof();
    _notifyIdentityVerification();
  }

  /// Hosts listen to this even when a recovery callback keeps the same user.
  /// Successful password updates, sign-out, and account changes clear it.
  ValueListenable<bool> get passwordRecovery => _passwordRecovery;
  bool get isPasswordRecovery => _passwordRecovery.value;

  /// An offline user may use guest-only data after discarding the unverified
  /// cached session. Local account files are preserved for a later sign-in.
  Future<void> continueAsGuest() async {
    _verificationGeneration++;
    _clearIdentityProof();
    _notifyIdentityVerification();
    if (_disposed) return;
    // The SDK discards the memory Session before remote logout. A stalled
    // logout ends this wait as unknown: no guest success is fabricated, and a
    // later explicit retry completes locally because no token remains.
    final deadline = MotionDeadline(_guestTimeout);
    try {
      await deadline.race(_client.auth.signOut(scope: SignOutScope.local));
    } on TimeoutException {
      throw const MotionOperationUnknown(
        MotionAccountOperation.continueAsGuest,
      );
    } finally {
      deadline.close();
    }
    if (_disposed) return;
    _observeCurrentSession();
    if (_disposed) return;
    if (_client.auth.currentSession != null) {
      throw StateError('Cached Motion session could not be cleared');
    }
    _userId.value = null;
    _phase.value = MotionIdentityPhase.signedOut;
    _notifyIdentityVerification();
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
  ///
  /// One pass has a total budget. A stalled listing, receipt or cleanup ends
  /// the pass as inconclusive (it throws), releases single-flight and lets the
  /// retry timer run. A receipt read that times out or fails is never a
  /// negative receipt; other UUIDs still progress. An admitted cleanup keeps
  /// running in its per-UUID ticket and a later pass joins it.
  Future<void> reconcileDeletedLocalAccounts() {
    final existing = _reconciliation;
    if (existing != null) return existing;
    final pass = Object();
    final deadline = MotionDeadline(_reconcileTimeout);
    final future = deadline
        .race(_scanDeletedLocalAccounts(pass, deadline))
        .whenComplete(() {
          deadline.close();
          if (identical(_reconciliationPass, pass)) {
            _reconciliationPass = null;
            _reconciliation = null;
          }
        });
    _reconciliationPass = pass;
    _reconciliation = future;
    return future;
  }

  bool _isCurrentPass(Object pass, MotionDeadline deadline) =>
      !_disposed && !deadline.isExpired && identical(_reconciliationPass, pass);

  Future<void> _scanDeletedLocalAccounts(
    Object pass,
    MotionDeadline deadline,
  ) async {
    final ids = await _localAccountIds();
    Object? inconclusive;
    StackTrace? inconclusiveStack;
    for (final id in ids.toSet()) {
      if (!_isCurrentPass(pass, deadline)) return;
      if (!_uuid.hasMatch(id)) continue;
      final bool deleted;
      try {
        deleted = await deadline.raceWithin(
          _receiptReadTimeout,
          Future.sync(() => _wasAccountDeleted(id)),
        );
      } catch (error, stack) {
        // Unavailable or late: keep this UUID's files, try the next one.
        inconclusive ??= error;
        inconclusiveStack ??= stack;
        continue;
      }
      // A late positive from an abandoned pass admits nothing; the next pass
      // reads the receipt again under its own budget.
      if (!_isCurrentPass(pass, deadline)) return;
      if (!deleted) continue;
      await _admitDeletedAccount(id);
    }
    if (inconclusive != null) {
      Error.throwWithStackTrace(inconclusive, inconclusiveStack!);
    }
  }

  /// Admits confirmed cleanup for [id] once; concurrent callers join it.
  Future<void> _admitDeletedAccount(String id) {
    final existing = _admittedCleanups[id];
    if (existing != null) return existing;
    final ticket = _runDeletedAccountCleanup(id);
    _admittedCleanups[id] = ticket;
    _cleanupPending.value = true;
    ticket.ignore(); // Observed by every waiter; never an unhandled error.
    ticket.whenComplete(() {
      if (identical(_admittedCleanups[id], ticket))
        _admittedCleanups.remove(id);
      if (!_disposed) _cleanupPending.value = _admittedCleanups.isNotEmpty;
    }).ignore();
    return ticket;
  }

  Future<void> _runDeletedAccountCleanup(String id) async {
    _observeCurrentSession();
    int? deletionGeneration;
    String? deletionToken;
    Session? deletionSession;
    // Receipt admission already succeeded. A proof callback may retire the
    // runtime; skip its bookkeeping then, but retain this UUID's cleanup.
    if (!_disposed && _client.auth.currentUser?.id == id) {
      deletionSession = _client.auth.currentSession;
      deletionToken = deletionSession?.accessToken;
      deletionGeneration = ++_verificationGeneration;
      _clearIdentityProof();
      _userId.value = null;
      _phase.value = MotionIdentityPhase.unavailable;
      _notifyIdentityVerification();
    }
    await _onDeletedAccount(id);
    _observeCurrentSession();
    // Bound to the exact deleted Session, not to the verification generation
    // that opened this ticket: a later Retry joins the ticket instead of
    // starting a second erase, and the dead Session must still be discarded.
    // A replacement Session (even same UUID/token) is never signed out.
    if (deletionGeneration != null &&
        !_disposed &&
        _client.auth.currentUser?.id == id &&
        identical(_client.auth.currentSession, deletionSession) &&
        _client.auth.currentSession?.accessToken == deletionToken) {
      // The SDK drops the memory Session before remote logout; a stalled
      // logout must not keep this ticket (and its joiners) pending forever.
      final deadline = MotionDeadline(_guestTimeout);
      try {
        await deadline.race(_client.auth.signOut(scope: SignOutScope.local));
      } catch (_) {
        // A deleted remote account cannot revoke an expired session.
      } finally {
        deadline.close();
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

  bool _isCurrentVerification(
    int generation,
    String id,
    String? token,
    Session? session,
  ) =>
      !_disposed &&
      generation == _verificationGeneration &&
      _client.auth.currentUser?.id == id &&
      identical(_client.auth.currentSession, session) &&
      _client.auth.currentSession?.accessToken == token;

  /// Refreshes Auth proof for the captured current Session.
  ///
  /// Completion can also mean this request was superseded. Hosts query
  /// isCurrentSessionVerified and recheck their captured Session/storage ticket.
  /// An unchanged, already verified Session keeps its previous proof pending
  /// refresh; a latest matching error or timeout invalidates it.
  Future<void> refreshIdentity() async {
    if (_disposed) return;
    _observeCurrentSession();
    if (_disposed) return;
    final claimedSession = _client.auth.currentSession;
    final claimedId = claimedSession?.user.id;
    final claimedToken = claimedSession?.accessToken;
    final generation = ++_verificationGeneration;
    if (claimedId == null) {
      _clearIdentityProof();
      _userId.value = null;
      _phase.value = MotionIdentityPhase.signedOut;
      _notifyIdentityVerification();
      return;
    }
    if (_userId.value != claimedId) {
      _userId.value = null;
      _phase.value = MotionIdentityPhase.verifying;
    }

    if (_disposed) return;
    // One total budget for getUser and any cleanup/logout it admits.
    final deadline = MotionDeadline(_identityTotalTimeout);
    try {
      final verified = await deadline.raceWithin(
        _identityVerificationTimeout,
        _client.auth.getUser(claimedToken),
      );
      // Observe the actual Session, not the stale request's Session. A newer
      // accepted proof for the actual Session must survive this completion.
      _observeCurrentSession();
      if (!_isCurrentVerification(
        generation,
        claimedId,
        claimedToken,
        claimedSession,
      )) {
        return;
      }
      if (verified.user?.id != claimedId) {
        throw StateError('Motion account identity mismatch');
      }
      // Only a latest matching Auth success may capture accepted credentials.
      _acceptedSession = claimedSession;
      _acceptedUserId = claimedId;
      _acceptedAccessToken = claimedToken;
      _observedSession = claimedSession;
      _userId.value = claimedId;
      _phase.value = MotionIdentityPhase.verified;
      _notifyIdentityVerification();
    } on AuthException catch (error) {
      _observeCurrentSession();
      if (!_isCurrentVerification(
        generation,
        claimedId,
        claimedToken,
        claimedSession,
      )) {
        return;
      }
      _clearIdentityProof();
      _userId.value = null;
      _phase.value = MotionIdentityPhase.unavailable;
      _notifyIdentityVerification();
      if (error.code == 'user_not_found') {
        // Explicit matching user_not_found admits this UUID's cleanup. When the
        // budget ends first the cleanup keeps running; this call reports it as
        // pending (not success) and the gate stays closed.
        try {
          await deadline.race(_admitDeletedAccount(claimedId));
        } on TimeoutException {
          throw const MotionLocalCleanupPending();
        }
        return;
      }
      rethrow;
    } catch (_) {
      _observeCurrentSession();
      if (_isCurrentVerification(
        generation,
        claimedId,
        claimedToken,
        claimedSession,
      )) {
        _clearIdentityProof();
        _userId.value = null;
        _phase.value = MotionIdentityPhase.unavailable;
        _notifyIdentityVerification();
      }
      rethrow;
    } finally {
      deadline.close();
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
    const receiptReadTimeout = Duration(seconds: 10);
    Future<bool> wasAccountDeleted(String userId) async {
      // Abort releases the anonymous read; callers also race their own budget.
      final deadline = MotionDeadline(receiptReadTimeout);
      try {
        final result = await deadline.race(
          receiptClient
              .rpc('motion_was_account_deleted', params: {'p_user_id': userId})
              .abortSignal(deadline.signal),
        );
        if (result is! bool) throw StateError('Invalid deletion receipt');
        return result;
      } finally {
        deadline.close();
      }
    }

    return MotionAccountRuntime._(
      MotionAccountClient(
        supabase: client,
        app: app,
        emailRedirectTo: emailRedirectTo,
        deletionReceipt: wasAccountDeleted,
      ),
      client,
      onDeletedAccount,
      localAccountIds,
      wasAccountDeleted,
      receiptClient,
      const Duration(minutes: 2),
      const Duration(seconds: 10),
      const Duration(seconds: 20),
      receiptReadTimeout,
      const Duration(seconds: 20),
      const Duration(seconds: 20),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearIdentityProof();
    // Fence before callbacks. close() defers notifier disposal until every
    // owned pulse has unwound, including a listener's reentrant dispose().
    _identityVerification.pulse();
    _identityVerification.close();
    _receiptRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _receiptClient?.dispose();
    _userId.close();
    _phase.close();
    _passwordRecovery.close();
    _cleanupPending.close();
  }
}
