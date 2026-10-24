import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motion_entitlements/motion_entitlements.dart'
    show motionAlpha2Country, motionStorefrontCountry;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'motion_account_client.dart';
import 'motion_account_deadline.dart';
import 'motion_account_localizations.dart';
import 'motion_age_policy.dart';
import 'motion_membership_page.dart';
import 'motion_release_policy.dart';

enum _ProfileReadState { idle, loading, ready, failed }

/// A small account surface that inherits the host app's Material theme.
///
/// A host must provide [clearLocalData] before offering common-account
/// deletion. The callback receives the captured user ID after the server
/// confirms deletion. A deletion receipt retries cleanup after a crash.
///
/// Sign-up asks a neutral birth month/year first (13+, country rules in
/// [MotionAgePolicy]). Under 13 no account is created and [onAgeBlocked] lets
/// the host persist that result; pass it back as [ageBlocked] so re-entering
/// another age on this device does not reopen sign-up.
class MotionAccountPage extends StatefulWidget {
  const MotionAccountPage({
    super.key,
    required this.account,
    this.initialPasswordRecovery = false,
    this.clearLocalData,
    this.onRetryIdentity,
    this.onManageSubscription,
    this.membershipAvailable = motionSubscriptionSalesAvailable,
    @Deprecated('Use membershipAvailable') this.paidFeaturesAvailable,
    this.countryCode,
    this.storefrontCountry = motionStorefrontCountry,
    this.ageBlocked = false,
    this.onAgeBlocked,
    this.clock = DateTime.now,
  });

  final MotionAccountClient account;
  final bool initialPasswordRecovery;
  final Future<void> Function(String userId)? clearLocalData;
  final Future<void> Function()? onRetryIdentity;
  final VoidCallback? onManageSubscription;

  /// Shows the membership row and options (and checks membership on open).
  /// Defaults to [motionSubscriptionSalesAvailable]; pass false for a host
  /// that does not sell in this build.
  final bool membershipAvailable;

  /// Former name of [membershipAvailable]; when non-null it wins.
  @Deprecated('Use membershipAvailable')
  final bool? paidFeaturesAvailable;

  /// Explicit ISO 3166-1 region override (alpha-2 or alpha-3). When null the
  /// page asks [storefrontCountry] (the store account region) once at sign-up
  /// or age confirmation and falls back to the device region; an unknown
  /// region uses [MotionAgePolicy.defaultRule].
  final String? countryCode;

  /// Store region reader; returns null when unavailable. Defaults to the
  /// App Store storefront / Google Play billing country.
  final Future<String?> Function() storefrontCountry;
  final bool ageBlocked;
  final VoidCallback? onAgeBlocked;
  final DateTime Function() clock;

  @override
  State<MotionAccountPage> createState() => _MotionAccountPageState();
}

class _MotionAccountPageState extends State<MotionAccountPage> {
  static final Uri _privacyPolicy = Uri.parse(
    'https://yulalab.com/privacy/motion',
  );
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  StreamSubscription<AuthState>? _authSubscription;
  Future<bool>? _membership;
  // Each membership check belongs to one page lifetime and one owner. A newer
  // check, an owner change or dispose stops an older one from publishing.
  int _membershipGeneration = 0;
  bool _register = false;
  bool _recovering = false;
  bool _busy = false;
  bool _profileSaveBusy = false;
  int _profileSaveGeneration = 0;
  MotionAccountString? _message;
  String? _lastUserId;
  int _profileRequestGeneration = 0;
  // Same-owner refreshes must retain local intent, including a saved draft.
  // Only an owner change starts a clean display-name field again.
  bool _displayNameEdited = false;
  bool _profileReadSucceeded = false;
  _ProfileReadState _profileReadState = _ProfileReadState.idle;
  Timer? _profileReadTimer;
  Completer<Map<String, dynamic>?>? _profileReadDeadline;
  static const _profileReadTimeout = Duration(seconds: 10);
  // A mutation whose outcome is unknown. Every mutation stays disabled until
  // the user acknowledges it or the owner changes; nothing retries it.
  MotionAccountOperation? _unresolved;
  final _parentEmail = TextEditingController();
  int? _birthYear;
  int? _birthMonth;
  late bool _ageBlocked = widget.ageBlocked;
  // Loaded per owner; null while unknown (the server still enforces RLS).
  MotionAgeStatus? _ageStatus;
  int _ageStatusGeneration = 0;

  bool get _canSaveProfile => _displayNameEdited || _profileReadSucceeded;
  // ignore: deprecated_member_use_from_same_package
  bool get _sells => widget.paidFeaturesAvailable ?? widget.membershipAvailable;
  bool get _isBusy => _busy || _profileSaveBusy || _unresolved != null;

  @override
  void initState() {
    super.initState();
    _recovering = widget.initialPasswordRecovery;
    _lastUserId = widget.account.currentUser?.id;
    _refreshMembership();
    _loadDisplayName();
    _loadAgeStatus();
    _authSubscription = widget.account.authChanges.listen(
      (state) {
        if (!mounted) return;
        final userId = widget.account.currentUser?.id;
        final accountChanged = userId != _lastUserId;
        _lastUserId = userId;
        if (accountChanged) {
          // A pending profile write belongs to the old form lifetime. Its
          // eventual outcome cannot hold or publish into the new owner's UI.
          _profileSaveGeneration++;
          _profileSaveBusy = false;
          // The visible account is now the current state (for example a late
          // sign-in reply); the old unknown outcome no longer applies here.
          _unresolved = null;
        }
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _recovering = true;
          } else if (state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.signedOut ||
              state.event == AuthChangeEvent.userUpdated) {
            _recovering = false;
          }
          // An unacknowledged unknown outcome keeps its explanation visible
          // across same-owner events such as token refresh.
          if (_unresolved == null) _message = null;
          if (accountChanged || state.event == AuthChangeEvent.userUpdated) {
            _refreshMembership();
          }
        });
        if (accountChanged || state.event == AuthChangeEvent.userUpdated) {
          _loadDisplayName(resetDraft: accountChanged);
        }
        if (accountChanged) _loadAgeStatus();
      },
      onError: (Object _, StackTrace _) {
        if (!mounted) return;
        // A refresh error is not a deletion or a new verified identity. Stop
        // publishing pending profile/membership observations; keep the form.
        _profileRequestGeneration++;
        _cancelProfileRead();
        _membershipGeneration++;
        setState(() {
          _membership = null;
          _profileReadState = _ProfileReadState.failed;
          _message = MotionAccountString.accountRefreshFailed;
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant MotionAccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPasswordRecovery != widget.initialPasswordRecovery) {
      _recovering = widget.initialPasswordRecovery;
    }
  }

  @override
  void dispose() {
    _profileSaveGeneration++;
    _membershipGeneration++;
    _cancelProfileRead();
    _authSubscription?.cancel();
    _parentEmail.dispose();
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<String?>? _storeCountry;

  /// Explicit override, then the store account region, then device region.
  Future<String?> _country() async {
    final explicit = motionAlpha2Country(widget.countryCode);
    if (explicit != null) return explicit;
    String? store;
    try {
      store = motionAlpha2Country(
        await (_storeCountry ??= widget.storefrontCountry()),
      );
    } catch (_) {
      store = null;
    }
    return store ??
        motionAlpha2Country(
          WidgetsBinding.instance.platformDispatcher.locale.countryCode,
        );
  }

  Future<MotionAgeDeclaration?> _declaration() async {
    final year = _birthYear;
    final month = _birthMonth;
    if (year == null || month == null) return null;
    return MotionAgeDeclaration(
      birthYear: year,
      birthMonth: month,
      countryCode: await _country(),
      policyVersion: MotionAgePolicy.version,
    );
  }

  bool get _restricted => _ageStatus?.restrictedOn(widget.clock()) ?? false;

  /// Owner-scoped status read. Failure shows nothing extra: the server's RLS
  /// still closes restricted writes, and no unobserved state is invented.
  Future<void> _loadAgeStatus() async {
    final generation = ++_ageStatusGeneration;
    final userId = widget.account.currentUser?.id;
    _ageStatus = null;
    if (userId == null) return;
    try {
      final status = await Future<MotionAgeStatus>.sync(
        widget.account.ageStatus,
      );
      if (!mounted ||
          generation != _ageStatusGeneration ||
          widget.account.currentUser?.id != userId) {
        return;
      }
      setState(() => _ageStatus = status);
    } catch (_) {
      // Unknown status: keep the page usable; enforcement is server-side.
    }
  }

  void _blockAge() {
    _ageBlocked = true;
    _message = MotionAccountString.ageBlocked;
    widget.onAgeBlocked?.call();
  }

  /// Under 13 is blocked in every country, so the gate needs no region.
  bool get _declaredUnder13 =>
      MotionAgePolicy.ageOn(_birthYear!, _birthMonth!, widget.clock()) <
      MotionAgePolicy.minimumAge;

  Future<void> _confirmDeclaredAge() async {
    if (_birthYear == null || _birthMonth == null) {
      setState(() => _message = MotionAccountString.ageRequired);
      return;
    }
    if (_declaredUnder13) {
      setState(_blockAge);
      return;
    }
    // The region read runs inside the busy action: no second dispatch.
    await _run(() async {
      final declaration = await _declaration();
      if (declaration == null) return;
      await widget.account.recordAgeDeclaration(declaration);
    });
    if (mounted) await _loadAgeStatus();
  }

  Future<void> _requestConsent() async {
    if (_isBusy) return;
    final owner = widget.account.currentUser?.id;
    // The resolved catalog locale (en, es-419, pt-BR, zh-Hans, …) selects the
    // parent email copy; a raw device tag like en-US would miss variants.
    final locale = MotionAccountLocalizations.of(
      context,
    ).locale.toLanguageTag();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.account.requestParentalConsent(
        parentEmail: _parentEmail.text,
        locale: locale,
      );
      if (!mounted || widget.account.currentUser?.id != owner) return;
      setState(() => _message = MotionAccountString.consentPending);
      await _loadAgeStatus();
    } on MotionConsentRequestRefused catch (refused) {
      if (!mounted || widget.account.currentUser?.id != owner) return;
      setState(() {
        _message = switch (refused.reason) {
          MotionConsentRequestError.tooSoon ||
          MotionConsentRequestError.dailyLimit =>
            MotionAccountString.consentTooSoon,
          MotionConsentRequestError.invalidParentEmail ||
          MotionConsentRequestError.parentEmailIsTeen =>
            MotionAccountString.consentEmailInvalid,
          MotionConsentRequestError.mailUnavailable =>
            MotionAccountString.requestFailed,
          MotionConsentRequestError.notRequired ||
          MotionConsentRequestError.alreadyApproved => null,
        };
      });
      await _loadAgeStatus();
    } on MotionOperationUnknown {
      if (!mounted || widget.account.currentUser?.id != owner) return;
      setState(() {
        _unresolved = MotionAccountOperation.parentalConsent;
        _message = MotionAccountString.emailRequestUnknown;
      });
    } catch (_) {
      if (!mounted || widget.account.currentUser?.id != owner) return;
      setState(() => _message = MotionAccountString.requestFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshMembership() {
    _membership = _startMembershipCheck();
  }

  /// Starts one owner-scoped membership check. Its result or error reaches
  /// the FutureBuilder only while this check is still the current one for the
  /// same owner on a mounted page; a superseded check is observed and dropped,
  /// never left as an uncaught zone error.
  Future<bool>? _startMembershipCheck() {
    final generation = ++_membershipGeneration;
    final owner = widget.account.currentUser?.id;
    if (!_sells || owner == null) return null;
    bool current() =>
        mounted &&
        generation == _membershipGeneration &&
        widget.account.currentUser?.id == owner;
    final published = Completer<bool>();
    Future<bool>.sync(widget.account.hasActiveMembership).then(
      (active) {
        if (current()) published.complete(active);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (current()) published.completeError(error, stackTrace);
      },
    );
    // The FutureBuilder still receives the error; a page state that is not
    // showing the builder (for example password recovery) does not leak it.
    return published.future..ignore();
  }

  Future<void> _loadDisplayName({bool resetDraft = false}) async {
    _cancelProfileRead();
    final generation = ++_profileRequestGeneration;
    final userId = widget.account.currentUser?.id;
    if (resetDraft || userId == null) {
      _displayNameEdited = false;
      _profileReadSucceeded = false;
      _displayName.clear();
    }
    if (userId == null) {
      _profileReadState = _ProfileReadState.idle;
      return;
    }
    // The read has a UI deadline; it does not cancel the underlying transport
    // or provide authority to roll back a remote mutation.
    _profileReadState = _ProfileReadState.loading;
    final deadline = Completer<Map<String, dynamic>?>();
    _profileReadDeadline = deadline;
    final timer = Timer(_profileReadTimeout, () {
      deadline.completeError(TimeoutException('Profile read timed out'));
    });
    _profileReadTimer = timer;
    try {
      final profile = await Future.any([
        Future<Map<String, dynamic>?>.sync(widget.account.loadProfile),
        deadline.future,
      ]);
      if (mounted &&
          generation == _profileRequestGeneration &&
          widget.account.currentUser?.id == userId) {
        setState(() {
          if (!_displayNameEdited) {
            _displayName.text = profile?['display_name'] as String? ?? '';
          }
          _profileReadSucceeded = true;
          _profileReadState = _ProfileReadState.ready;
        });
      }
    } catch (_) {
      if (mounted &&
          generation == _profileRequestGeneration &&
          widget.account.currentUser?.id == userId) {
        // An unobserved blank field is not permission to overwrite a profile.
        // Explicit user edits, including clearing a name, remain usable.
        setState(() => _profileReadState = _ProfileReadState.failed);
      }
    } finally {
      timer.cancel();
      if (identical(_profileReadTimer, timer)) _profileReadTimer = null;
      if (identical(_profileReadDeadline, deadline))
        _profileReadDeadline = null;
    }
  }

  void _cancelProfileRead() {
    _profileReadTimer?.cancel();
    _profileReadTimer = null;
    final deadline = _profileReadDeadline;
    _profileReadDeadline = null;
    if (deadline != null && !deadline.isCompleted) {
      // Settle only this local wait. Future.any still observes the transport's
      // eventual result/error, while generation/owner/mounted reject publication.
      deadline.completeError(StateError('Profile read superseded'));
    }
  }

  String _text(MotionAccountString key) =>
      MotionAccountLocalizations.of(context).text(key);

  Future<void> _openPrivacyPolicy() async {
    try {
      if (await launchUrl(
        _privacyPolicy,
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // The device may not have a browser. Keep the account page usable.
    }
    if (!mounted) return;
    setState(() {
      _message = MotionAccountString.privacyOpenFailed;
    });
  }

  Future<void> _openMembership() async {
    if (!_sells) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MotionMembershipPage(account: widget.account),
      ),
    );
    if (!mounted) return;
    setState(_refreshMembership);
  }

  Future<void> _run(
    Future<void> Function() action, {
    MotionAccountString? success,
  }) async {
    if (_isBusy) return;
    final owner = widget.account.currentUser?.id;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _refreshMembership();
        _message = success;
      });
    } on MotionOperationUnknown catch (unknown) {
      if (!mounted) return;
      final operation = unknown.operation;
      final current = widget.account.currentUser?.id;
      setState(() {
        if (operation == MotionAccountOperation.signOut && current == null) {
          // Local discard is observed; only remote revocation is unconfirmed.
          _message = MotionAccountString.signedOutOnDevice;
        } else if (current == owner) {
          _unresolved = operation;
          _message = _unknownMessage(operation);
        }
        // Otherwise the account already changed: the new state is visible
        // and the old unknown outcome is not published into it.
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is MotionLocalCleanupPending
            ? MotionAccountString.cleanupPending
            : MotionAccountString.requestFailed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static MotionAccountString _unknownMessage(
    MotionAccountOperation operation,
  ) => switch (operation) {
    MotionAccountOperation.signUp ||
    MotionAccountOperation.passwordReset ||
    MotionAccountOperation.resendConfirmation ||
    MotionAccountOperation.parentalConsent =>
      MotionAccountString.emailRequestUnknown,
    MotionAccountOperation.updatePassword =>
      MotionAccountString.passwordUpdateUnknown,
    MotionAccountOperation.deleteAccount => MotionAccountString.deletionUnknown,
    MotionAccountOperation.saveProfile =>
      MotionAccountString.profileSaveUnknown,
    _ => MotionAccountString.operationUnknown,
  };

  void _acknowledgeUnknown() {
    if (!mounted || _unresolved == null) return;
    setState(() {
      _unresolved = null;
      _message = null;
    });
  }

  bool _canPublishProfileSave(int generation, String userId) =>
      mounted &&
      generation == _profileSaveGeneration &&
      widget.account.currentUser?.id == userId;

  Future<void> _saveDisplayName(String userId) async {
    // The button closure captures the user rendered by _profile. A retained
    // callback from A is not authority to dispatch a write for current user B.
    if (!mounted ||
        _isBusy ||
        !_canSaveProfile ||
        widget.account.currentUser?.id != userId)
      return;
    final generation = ++_profileSaveGeneration;
    _displayNameEdited = true;
    _profileRequestGeneration++;
    _cancelProfileRead();
    _profileReadState = _ProfileReadState.idle;
    final displayName = _displayName.text;
    setState(() {
      _profileSaveBusy = true;
      _message = null;
    });
    try {
      await widget.account.saveDisplayName(displayName);
      if (!_canPublishProfileSave(generation, userId)) return;
      setState(() => _message = MotionAccountString.profileSaved);
    } on MotionOperationUnknown {
      if (!_canPublishProfileSave(generation, userId)) return;
      await _checkUnknownSave(generation, userId, displayName.trim());
    } catch (_) {
      if (!_canPublishProfileSave(generation, userId)) return;
      setState(() => _message = MotionAccountString.requestFailed);
    } finally {
      if (_canPublishProfileSave(generation, userId)) {
        setState(() => _profileSaveBusy = false);
      }
    }
  }

  /// Reads the owner's current profile once after an unknown save. Equality is
  /// the current postcondition, not an exactly-once acknowledgement. The draft
  /// is never overwritten and no write is replayed.
  Future<void> _checkUnknownSave(
    int generation,
    String userId,
    String sent,
  ) async {
    final deadline = MotionDeadline(_profileReadTimeout);
    try {
      final profile = await deadline.race(
        Future<Map<String, dynamic>?>.sync(widget.account.loadProfile),
      );
      if (!_canPublishProfileSave(generation, userId)) return;
      final current = (profile?['display_name'] as String? ?? '').trim();
      setState(() {
        _message = current == sent
            ? MotionAccountString.profileSaveMatches
            : MotionAccountString.profileSaveDiffers;
      });
    } catch (_) {
      if (!_canPublishProfileSave(generation, userId)) return;
      setState(() {
        _unresolved = MotionAccountOperation.saveProfile;
        _message = MotionAccountString.profileSaveUnknown;
      });
    } finally {
      deadline.close();
    }
  }

  Future<void> _submitCredentials() async {
    final email = _email.text.trim();
    if (!email.contains('@') ||
        _password.text.isEmpty ||
        (_register && _password.text.length < 8)) {
      setState(() {
        _message = _register
            ? MotionAccountString.invalidRegistration
            : MotionAccountString.invalidCredentials;
      });
      return;
    }
    if (_register) {
      if (_ageBlocked) {
        setState(() => _message = MotionAccountString.ageBlocked);
        return;
      }
      if (_birthYear == null || _birthMonth == null) {
        setState(() => _message = MotionAccountString.ageRequired);
        return;
      }
      if (_declaredUnder13) {
        setState(_blockAge);
        return;
      }
      await _run(() async {
        final age = await _declaration();
        if (age == null) return;
        await widget.account.signUpWithAge(
          email: email,
          password: _password.text,
          age: age,
        );
      }, success: MotionAccountString.verificationThenSignIn);
      return;
    }
    await _run(
      () async => widget.account.signIn(email: email, password: _password.text),
    );
  }

  Future<void> _confirmDeletion() async {
    final account = widget.account;
    final clear = widget.clearLocalData;
    final userId = account.currentUser?.id;
    final initiatingSession = account.supabase.auth.currentSession;
    if (clear == null || userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final strings = MotionAccountLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(strings.text(MotionAccountString.deleteMotionAccount)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.text(MotionAccountString.deleteExplanation)),
              const SizedBox(height: 12),
              Text(strings.text(MotionAccountString.deleteOtherDevices)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.text(MotionAccountString.cancel)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                strings.text(MotionAccountString.confirmDeleteAccount),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true ||
        !mounted ||
        !identical(widget.account.supabase, account.supabase) ||
        !identical(account.supabase.auth.currentSession, initiatingSession) ||
        account.currentUser?.id != userId)
      return;
    await _run(() => account.deleteCommonAccount(afterRemoteDelete: clear));
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.account.currentUser;
    return Scaffold(
      appBar: AppBar(title: Text(_text(MotionAccountString.accountTitle))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_message != null) ...[
              Semantics(liveRegion: true, child: Text(_text(_message!))),
              if (_unresolved != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _acknowledgeUnknown,
                    child: Text(_text(MotionAccountString.acknowledgeUnknown)),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            if (_isBusy) const LinearProgressIndicator(),
            if (_recovering)
              _recoveryForm()
            else if (user == null)
              _signInForm()
            else
              _profile(user),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _openPrivacyPolicy,
              child: Text(_text(MotionAccountString.privacyPolicy)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signInForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _register
            ? _text(MotionAccountString.createAccount)
            : _text(MotionAccountString.signIn),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.email),
        ),
      ),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: [
          _register ? AutofillHints.newPassword : AutofillHints.password,
        ],
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.password),
        ),
      ),
      if (_register) ...[const SizedBox(height: 16), ..._ageFields()],
      // A block persisted by the host (for example after a restart) must say
      // why sign-up is closed, not only disable the button.
      if (_register &&
          _ageBlocked &&
          _message != MotionAccountString.ageBlocked) ...[
        const SizedBox(height: 16),
        Text(_text(MotionAccountString.ageBlocked)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _isBusy || (_register && _ageBlocked)
            ? null
            : _submitCredentials,
        child: Text(
          _register
              ? _text(MotionAccountString.createAccount)
              : _text(MotionAccountString.signIn),
        ),
      ),
      TextButton(
        onPressed: _isBusy
            ? null
            : () => setState(() {
                _register = !_register;
                _message = null;
              }),
        child: Text(
          _register
              ? _text(MotionAccountString.alreadyHaveAccount)
              : _text(MotionAccountString.newAccount),
        ),
      ),
      if (_register)
        TextButton(
          onPressed: _isBusy
              ? null
              : () => _run(
                  () => widget.account.resendConfirmation(_email.text),
                  success: MotionAccountString.verificationEmail,
                ),
          child: Text(_text(MotionAccountString.resendVerification)),
        ),
      if (!_register)
        TextButton(
          onPressed: _isBusy
              ? null
              : () => _run(
                  () => widget.account.sendPasswordReset(_email.text),
                  success: MotionAccountString.passwordResetEmail,
                ),
          child: Text(_text(MotionAccountString.forgotPassword)),
        ),
    ],
  );

  Widget _recoveryForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _text(MotionAccountString.newPassword),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.newPassword),
        ),
      ),
      FilledButton(
        onPressed: _isBusy
            ? null
            : () {
                if (_password.text.length < 8) {
                  setState(
                    () => _message = MotionAccountString.invalidNewPassword,
                  );
                  return;
                }
                _run(() async {
                  await widget.account.updatePassword(_password.text);
                  if (mounted) setState(() => _recovering = false);
                });
              },
        child: Text(_text(MotionAccountString.savePassword)),
      ),
    ],
  );

  /// Neutral age screen: no preselected values, no hint of a cutoff, no day.
  List<Widget> _ageFields() {
    final thisYear = widget.clock().year;
    return [
      Text(_text(MotionAccountString.ageIntro)),
      DropdownButtonFormField<int>(
        key: const ValueKey('motion-birth-year'),
        initialValue: _birthYear,
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.birthYear),
        ),
        items: [
          for (var year = thisYear; year >= thisYear - 100; year--)
            DropdownMenuItem(value: year, child: Text('$year')),
        ],
        onChanged: _isBusy || _ageBlocked
            ? null
            : (year) => setState(() => _birthYear = year),
      ),
      DropdownButtonFormField<int>(
        key: const ValueKey('motion-birth-month'),
        initialValue: _birthMonth,
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.birthMonth),
        ),
        items: [
          for (var month = 1; month <= 12; month++)
            DropdownMenuItem(
              value: month,
              child: Text(month.toString().padLeft(2, '0')),
            ),
        ],
        onChanged: _isBusy || _ageBlocked
            ? null
            : (month) => setState(() => _birthMonth = month),
      ),
    ];
  }

  List<Widget> _ageSection() {
    final status = _ageStatus;
    if (status == null) return const [];
    if (!status.declared) {
      return [
        Text(_text(MotionAccountString.ageUndeclared)),
        ..._ageFields(),
        FilledButton.tonal(
          onPressed: _isBusy || _ageBlocked ? null : _confirmDeclaredAge,
          child: Text(_text(MotionAccountString.confirmAge)),
        ),
        const SizedBox(height: 16),
      ];
    }
    if (!_restricted) return const [];
    return [
      Semantics(
        liveRegion: true,
        child: Text(
          _text(switch (status.consent) {
            MotionParentalConsent.pending => MotionAccountString.consentPending,
            MotionParentalConsent.expired => MotionAccountString.consentExpired,
            _ => MotionAccountString.parentalConsentNeeded,
          }),
        ),
      ),
      TextField(
        controller: _parentEmail,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.parentEmail),
        ),
      ),
      FilledButton.tonal(
        onPressed: _isBusy ? null : _requestConsent,
        child: Text(_text(MotionAccountString.sendConsentRequest)),
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _profile(User user) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(user.email ?? '', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      ..._ageSection(),
      TextField(
        controller: _displayName,
        onChanged: (_) => setState(() => _displayNameEdited = true),
        decoration: InputDecoration(
          labelText: _text(MotionAccountString.displayName),
        ),
      ),
      if (_profileReadState == _ProfileReadState.loading)
        Semantics(
          liveRegion: true,
          child: Text(_text(MotionAccountString.profileLoading)),
        ),
      if (_profileReadState == _ProfileReadState.failed) ...[
        Semantics(
          liveRegion: true,
          child: Text(_text(MotionAccountString.profileReadFailed)),
        ),
        TextButton(
          onPressed: _isBusy
              ? null
              : () {
                  setState(() {
                    _loadDisplayName();
                  });
                },
          child: Text(_text(MotionAccountString.retryProfile)),
        ),
      ],
      FilledButton.tonal(
        // A consent-pending account cannot write the shared profile (RLS).
        onPressed: _isBusy || !_canSaveProfile || _restricted
            ? null
            : () => _saveDisplayName(user.id),
        child: Text(_text(MotionAccountString.saveProfile)),
      ),
      const SizedBox(height: 16),
      if (_sells)
        FutureBuilder<bool>(
          future: _membership,
          builder: (context, snapshot) => Text(
            snapshot.hasError
                ? _text(MotionAccountString.membershipUnavailable)
                : !snapshot.hasData
                ? _text(MotionAccountString.membershipChecking)
                : snapshot.data!
                ? _text(MotionAccountString.membershipActiveInApp)
                : _text(MotionAccountString.noMembershipInApp),
          ),
        ),
      if (_sells)
        FilledButton.tonal(
          onPressed: _isBusy ? null : _openMembership,
          child: Text(_text(MotionAccountString.membershipOptions)),
        ),
      TextButton(
        onPressed: _isBusy
            ? null
            : () => _run(() async {
                await widget.onRetryIdentity?.call();
              }),
        child: Text(
          _sells
              ? _text(MotionAccountString.refreshAccountAndMembership)
              : _text(MotionAccountString.refreshAccount),
        ),
      ),
      if (widget.onManageSubscription != null)
        TextButton(
          onPressed: widget.onManageSubscription,
          child: Text(_text(MotionAccountString.manageStoreSubscription)),
        ),
      OutlinedButton(
        onPressed: _isBusy ? null : () => _run(widget.account.signOut),
        child: Text(_text(MotionAccountString.signOut)),
      ),
      if (widget.clearLocalData != null)
        TextButton(
          onPressed: _isBusy ? null : _confirmDeletion,
          child: Text(_text(MotionAccountString.deleteMotionAccount)),
        ),
    ],
  );
}
