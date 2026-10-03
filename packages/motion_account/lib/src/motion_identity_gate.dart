import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'motion_account_runtime.dart';

/// Closes new admission until the exact current Auth Session is verified.
///
/// The host key identifies its existing owner/resource ticket and stays stable
/// on ordinary same-owner credential refresh. Already admitted State is hidden,
/// not rebound, while replacement credentials are awaiting proof. Host actions
/// still check their captured Session and ticket before and after every await.
class MotionIdentityGate extends StatelessWidget {
  const MotionIdentityGate({
    super.key,
    required this.runtime,
    required this.child,
  });

  final MotionAccountRuntime runtime;
  final Widget child;

  @override
  Widget build(BuildContext context) => _MotionIdentityGateBody(
    runtime: runtime,
    child: child,
  );
}

class _MotionIdentityGateBody extends StatefulWidget {
  const _MotionIdentityGateBody({required this.runtime, required this.child});

  final MotionAccountRuntime runtime;
  final Widget child;

  @override
  State<_MotionIdentityGateBody> createState() => _MotionIdentityGateBodyState();
}

class _MotionIdentityGateBodyState extends State<_MotionIdentityGateBody> {
  late MotionAccountRuntime _boundRuntime;
  Listenable? _changes;
  VoidCallback? _listener;
  StreamSubscription<AuthState>? _auth;
  // Event classification is independent of proof completion. A fast getUser
  // must not erase the evidence of a distinct fresh signedIn awaiting delivery.
  Session? _handledSession;
  Widget? _retainedChild;
  Key? _slotKey;
  Key? _configurationTicketKey;
  String? _scopeOwner;
  bool _recovery = false;
  bool _authUnavailable = false;
  bool _closed = false;
  Object? _retirementFrame;

  @override
  void initState() {
    super.initState();
    _bind(widget.runtime);
  }

  @override
  void didUpdateWidget(covariant _MotionIdentityGateBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _unbind();
      _retireScope();
      _bind(widget.runtime);
    }
    _synchronize();
  }

  bool _isBound(MotionAccountRuntime runtime) =>
      !_closed && mounted && identical(runtime, _boundRuntime) &&
      identical(runtime, widget.runtime);

  void _bind(MotionAccountRuntime runtime) {
    _boundRuntime = runtime;
    _handledSession = runtime.account.supabase.auth.currentSession;
    _configurationTicketKey = widget.child.key;
    _recovery = runtime.isPasswordRecovery;
    _authUnavailable = false;
    // Disposed phase/ValueNotifiers still have readable snapshots. They must
    // never be used for guest admission or receive new listener registrations.
    if (runtime.isDisposed) return;
    _listener = () {
      if (!_isBound(runtime)) return;
      if (runtime.isCurrentSessionVerified) _authUnavailable = false;
      _changed(runtime); // Includes the final pulse after isDisposed is true.
    };
    _changes = Listenable.merge([
      runtime.phase,
      runtime.identityVerification,
      runtime.passwordRecovery,
    ])..addListener(_listener!);
    _auth = runtime.account.supabase.auth.onAuthStateChange.listen(
      (state) => _handleAuth(runtime, state),
      onError: (Object _, StackTrace __) {
        if (!_isBound(runtime) || runtime.isDisposed) return;
        _authUnavailable = true;
        _changed(runtime);
      },
    );
  }

  void _unbind() {
    final listener = _listener;
    if (listener != null) _changes?.removeListener(listener);
    _changes = null;
    _listener = null;
    final subscription = _auth;
    _auth = null;
    if (subscription != null) {
      // State.dispose cannot await. This owned cancellation always has an error
      // handler; captured-runtime/closed guards fence any queued public event.
      unawaited(_cancelAuth(subscription));
    }
  }

  Future<void> _cancelAuth(StreamSubscription<AuthState> subscription) async {
    try {
      await subscription.cancel();
    } catch (_) {
      // A retired gate must never send work into its successor or an error zone.
    }
  }

  void _handleAuth(MotionAccountRuntime runtime, AuthState state) {
    if (!_isBound(runtime) || runtime.isDisposed) return;
    final actual = runtime.account.supabase.auth.currentSession;
    if (!identical(state.session, actual)) {
      _changed(runtime); // Recompute live owner, never assign a stale event owner.
      return;
    }
    final distinct = !identical(actual, _handledSession);
    if (state.event == AuthChangeEvent.signedOut) {
      if (actual == null || !runtime.isCurrentSessionVerified) _retireScope();
      _handledSession = actual;
    } else if (state.event == AuthChangeEvent.tokenRefreshed) {
      // Public recoverSession can use this label for a different UUID. Equality
      // of the actual owner and the still-current host key are both required.
      if (_retainedChild != null && actual?.user.id != _scopeOwner) {
        _retireScope();
      }
      _handledSession = actual;
    } else if (state.event == AuthChangeEvent.signedIn ||
        state.event == AuthChangeEvent.initialSession ||
        state.event == AuthChangeEvent.passwordRecovery ||
        state.event == AuthChangeEvent.userUpdated) {
      if (distinct) _retireScope();
      _handledSession = actual;
    }
    _changed(runtime);
  }

  void _changed(MotionAccountRuntime runtime) {
    if (!_isBound(runtime)) return;
    _synchronize();
    setState(() {});
  }

  void _retireScope() {
    if (_retainedChild == null) return;
    _retainedChild = null;
    _slotKey = null;
    _scopeOwner = null;
    // First remove the old Element. A same-frame cold admission must not reuse
    // a descendant GlobalKey from a retired runtime/owner/ticket.
    final frame = Object();
    _retirementFrame = frame;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_closed || !mounted || !identical(_retirementFrame, frame)) return;
      _retirementFrame = null;
      setState(() {});
    });
  }

  void _synchronize() {
    final runtime = _boundRuntime;
    if (runtime.isDisposed) {
      _retireScope();
      return;
    }
    final actual = runtime.account.supabase.auth.currentSession;
    if (widget.child.key != _configurationTicketKey) {
      _retireScope();
      _configurationTicketKey = widget.child.key;
      // The host supplied a new ticket: cold admission may classify the actual
      // Session at this new boundary, but still requires this runtime's proof.
      _handledSession = actual;
    }
    if (_retainedChild != null && actual?.user.id != _scopeOwner) {
      _retireScope();
    }
    if (_recovery != runtime.isPasswordRecovery) {
      _retireScope();
      _recovery = runtime.isPasswordRecovery;
    }
    if (!_ready || _retirementFrame != null) return;
    if (_retainedChild == null) {
      _scopeOwner = actual?.user.id; // null is a separately admitted guest scope.
      _slotKey = UniqueKey();
    }
    // Never hand new account-private configuration to an unverified retained
    // Element. Hidden State keeps only its last admitted configuration.
    _retainedChild = widget.child;
  }

  bool get _ready {
    final runtime = _boundRuntime;
    if (runtime.isDisposed || _authUnavailable || _retirementFrame != null) {
      return false;
    }
    final actual = runtime.account.supabase.auth.currentSession;
    if (actual == null) {
      return runtime.phase.value == MotionIdentityPhase.signedOut &&
          !runtime.isPasswordRecovery;
    }
    return runtime.phase.value == MotionIdentityPhase.verified &&
        runtime.isCurrentSessionVerified && identical(actual, _handledSession);
    // Unknown eventless same-UUID replacement is deliberately not classified
    // from UUID/proof alone. The host resets its ticket key or uses its adapter.
  }

  @override
  Widget build(BuildContext context) {
    _synchronize();
    final ready = _ready && _retainedChild != null;
    return Stack(
      alignment: Alignment.topLeft, // Also supports top-level runApp without Directionality.
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: !ready,
          child: ExcludeFocus(
            excluding: !ready,
            child: ExcludeSemantics(
              excluding: !ready,
              child: _retainedChild == null
                  ? const SizedBox.shrink()
                  : KeyedSubtree(key: _slotKey, child: _retainedChild!),
            ),
          ),
        ),
        if (!ready) _blocker(),
      ],
    );
  }

  Widget _blocker() {
    final runtime = _boundRuntime;
    final phase = runtime.phase.value;
    final pending = !runtime.isDisposed && !_authUnavailable &&
        (phase == MotionIdentityPhase.verifying ||
            (phase == MotionIdentityPhase.verified &&
                !runtime.isCurrentSessionVerified));
    return MaterialApp(
      supportedLocales: const [Locale('tr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final tr = Localizations.localeOf(context).languageCode == 'tr';
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pending) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(tr ? 'Hesap doğrulanıyor…' : 'Checking account…'),
                      ] else ...[
                        Text(
                          tr
                              ? 'Hesap doğrulanamadı. Bağlantını kontrol edip yeniden dene.'
                              : 'Could not verify your account. Check your connection and retry.',
                          textAlign: TextAlign.center,
                        ),
                        if (!runtime.isDisposed) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () async {
                              if (!_isBound(runtime) || runtime.isDisposed) return;
                              try {
                                await runtime.refreshIdentity();
                              } catch (_) {
                                // Keep admission closed while retry is unavailable.
                              }
                            },
                            child: Text(tr ? 'Yeniden dene' : 'Retry'),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (!_isBound(runtime) || runtime.isDisposed) return;
                              try {
                                await runtime.continueAsGuest();
                              } catch (_) {
                                // No network/logout result supplies deletion proof.
                              }
                            },
                            child: Text(
                              tr ? 'Misafir olarak devam et' : 'Continue as guest',
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _closed = true;
    _retirementFrame = null;
    _unbind();
    _retainedChild = null;
    super.dispose();
  }
}
