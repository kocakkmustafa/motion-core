import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'motion_account_client.dart';
import 'motion_membership_page.dart';
import 'motion_release_policy.dart';

/// A small account surface that inherits the host app's Material theme.
///
/// A host must provide [clearLocalData] before offering common-account
/// deletion. The callback receives the captured user ID after the server
/// confirms deletion. A deletion receipt retries cleanup after a crash.
class MotionAccountPage extends StatefulWidget {
  const MotionAccountPage({
    super.key,
    required this.account,
    this.initialPasswordRecovery = false,
    this.clearLocalData,
    this.onRetryIdentity,
    this.onManageSubscription,
    this.paidFeaturesAvailable = motionPaidFeaturesAvailable,
  });

  final MotionAccountClient account;
  final bool initialPasswordRecovery;
  final Future<void> Function(String userId)? clearLocalData;
  final Future<void> Function()? onRetryIdentity;
  final VoidCallback? onManageSubscription;
  final bool paidFeaturesAvailable;

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
  bool _register = false;
  bool _recovering = false;
  bool _busy = false;
  String? _message;
  String? _lastUserId;
  int _profileRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _recovering = widget.initialPasswordRecovery;
    _lastUserId = widget.account.currentUser?.id;
    _refreshMembership();
    _loadDisplayName();
    _authSubscription = widget.account.authChanges.listen(
      (state) {
        if (!mounted) return;
        final userId = widget.account.currentUser?.id;
        final accountChanged = userId != _lastUserId;
        _lastUserId = userId;
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _recovering = true;
          } else if (state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.signedOut ||
              state.event == AuthChangeEvent.userUpdated) {
            _recovering = false;
          }
          _message = null;
          if (accountChanged || state.event == AuthChangeEvent.userUpdated) {
            _refreshMembership();
          }
        });
        if (accountChanged || state.event == AuthChangeEvent.userUpdated) {
          _loadDisplayName();
        }
      },
      onError: (Object _, StackTrace _) {
        if (!mounted) return;
        // A refresh error is not a deletion or a new verified identity. Stop
        // publishing pending profile/membership observations; keep the form.
        _profileRequestGeneration++;
        setState(() {
          _membership = null;
          _message = _t(
            'Hesabın yenilenemedi. Lütfen tekrar dene.',
            'Could not refresh your account. Please retry.',
          );
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
    _authSubscription?.cancel();
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _refreshMembership() {
    _membership =
        !widget.paidFeaturesAvailable || widget.account.currentUser == null
        ? null
        : widget.account.hasActiveMembership();
  }

  Future<void> _loadDisplayName() async {
    final generation = ++_profileRequestGeneration;
    final userId = widget.account.currentUser?.id;
    if (userId == null) {
      _displayName.clear();
      return;
    }
    try {
      final profile = await widget.account.loadProfile();
      if (mounted &&
          generation == _profileRequestGeneration &&
          widget.account.currentUser?.id == userId) {
        _displayName.text = profile?['display_name'] as String? ?? '';
      }
    } catch (_) {
      // The profile field stays editable when the network is unavailable.
    }
  }

  String _t(String tr, String en) =>
      Localizations.localeOf(context).languageCode == 'tr' ? tr : en;

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
      _message = _t(
        'Gizlilik politikası açılamadı. Bağlantını ve tarayıcını kontrol et.',
        'Could not open the privacy policy. Check your connection and browser.',
      );
    });
  }

  Future<void> _openMembership() async {
    if (!widget.paidFeaturesAvailable) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MotionMembershipPage(account: widget.account),
      ),
    );
    if (!mounted) return;
    setState(_refreshMembership);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _membership =
            !widget.paidFeaturesAvailable || widget.account.currentUser == null
            ? null
            : widget.account.hasActiveMembership();
        _message = success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error is MotionLocalCleanupPending
            ? _t(
                'Motion hesabın silindi. Bu cihazdaki geçmiş şu anda temizlenemedi; uygulama çevrimiçi açıldığında yeniden denenecek.',
                'Your Motion account was deleted. Local history could not be cleared now; cleanup will retry when the app opens online.',
              )
            : _t(
                'İşlem tamamlanamadı. Bilgilerini ve bağlantını kontrol edip tekrar dene.',
                'Could not complete the request. Check your details and connection, then retry.',
              );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCredentials() async {
    final email = _email.text.trim();
    if (!email.contains('@') ||
        _password.text.isEmpty ||
        (_register && _password.text.length < 8)) {
      setState(() {
        _message = _t(
          _register
              ? 'Geçerli e-posta ve en az 8 karakterli şifre gir.'
              : 'E-posta ve şifreni gir.',
          _register
              ? 'Enter a valid email and a password of at least 8 characters.'
              : 'Enter your email and password.',
        );
      });
      return;
    }
    if (_register) {
      await _run(
        () async {
          await widget.account.signUp(email: email, password: _password.text);
        },
        success: _t(
          'Doğrulama e-postanı kontrol et. Ardından giriş yapabilirsin.',
          'Check your verification email, then sign in.',
        ),
      );
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
        String t(String tr, String en) =>
            Localizations.localeOf(dialogContext).languageCode == 'tr' ? tr : en;
        return AlertDialog(
          title: Text(t('Motion hesabını sil', 'Delete Motion account')),
          content: Text(
            t(
              'Ortak hesabın ve beş uygulamadaki üyelik hakların silinir. '
                  'Ardından bu uygulamadaki yerel geçmiş temizlenir. '
                  'Mağaza aboneliğini Apple veya Google hesabından ayrıca iptal etmelisin.',
              'This deletes your shared account and access in all five apps, '
                  'then erases local history in this app. '
                  'Cancel any store subscription separately in your Apple or Google account.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('Vazgeç', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('Hesabı sil', 'Delete account')),
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
    await _run(
      () => account.deleteCommonAccount(afterRemoteDelete: clear),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.account.currentUser;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Motion hesabı', 'Motion account'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_message != null) ...[
              Semantics(liveRegion: true, child: Text(_message!)),
              const SizedBox(height: 16),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_recovering)
              _recoveryForm()
            else if (user == null)
              _signInForm()
            else
              _profile(user),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _openPrivacyPolicy,
              child: Text(_t('Gizlilik politikası', 'Privacy policy')),
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
            ? _t('Hesap oluştur', 'Create account')
            : _t('Giriş yap', 'Sign in'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: InputDecoration(labelText: _t('E-posta', 'Email')),
      ),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: [
          _register ? AutofillHints.newPassword : AutofillHints.password,
        ],
        decoration: InputDecoration(labelText: _t('Şifre', 'Password')),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _submitCredentials,
        child: Text(
          _register
              ? _t('Hesap oluştur', 'Create account')
              : _t('Giriş yap', 'Sign in'),
        ),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _register = !_register;
                _message = null;
              }),
        child: Text(
          _register
              ? _t('Zaten hesabım var', 'I already have an account')
              : _t('Yeni hesap oluştur', 'Create a new account'),
        ),
      ),
      if (_register)
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.account.resendConfirmation(_email.text),
                  success: _t(
                    'Doğrulama e-postanı kontrol et.',
                    'Check your verification email.',
                  ),
                ),
          child: Text(
            _t(
              'Doğrulama e-postasını yeniden gönder',
              'Resend verification email',
            ),
          ),
        ),
      if (!_register)
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.account.sendPasswordReset(_email.text),
                  success: _t(
                    'Şifre sıfırlama e-postanı kontrol et.',
                    'Check your password reset email.',
                  ),
                ),
          child: Text(_t('Şifremi unuttum', 'Forgot password')),
        ),
    ],
  );

  Widget _recoveryForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _t('Yeni şifre', 'New password'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: _t('Yeni şifre', 'New password'),
        ),
      ),
      FilledButton(
        onPressed: _busy
            ? null
            : () {
                if (_password.text.length < 8) {
                  setState(
                    () => _message = _t(
                      'En az 8 karakterli yeni şifre gir.',
                      'Enter a new password of at least 8 characters.',
                    ),
                  );
                  return;
                }
                _run(() async {
                  await widget.account.updatePassword(_password.text);
                  if (mounted) setState(() => _recovering = false);
                });
              },
        child: Text(_t('Şifreyi kaydet', 'Save password')),
      ),
    ],
  );

  Widget _profile(User user) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(user.email ?? '', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      TextField(
        controller: _displayName,
        decoration: InputDecoration(
          labelText: _t('Görünen ad', 'Display name'),
        ),
      ),
      FilledButton.tonal(
        onPressed: _busy
            ? null
            : () => _run(
                () => widget.account.saveDisplayName(_displayName.text),
                success: _t('Profil kaydedildi.', 'Profile saved.'),
              ),
        child: Text(_t('Profili kaydet', 'Save profile')),
      ),
      const SizedBox(height: 16),
      if (widget.paidFeaturesAvailable)
        FutureBuilder<bool>(
          future: _membership,
          builder: (context, snapshot) => Text(
            snapshot.hasError
                ? _t('Üyelik durumu alınamadı.', 'Membership unavailable.')
                : !snapshot.hasData
                ? _t('Üyelik kontrol ediliyor…', 'Checking membership…')
                : snapshot.data!
                ? _t(
                    'Bu uygulamada üyelik aktif.',
                    'Membership active in this app.',
                  )
                : _t(
                    'Bu uygulamada aktif üyelik yok.',
                    'No active membership in this app.',
                  ),
          ),
        ),
      if (widget.paidFeaturesAvailable)
        FilledButton.tonal(
          onPressed: _busy ? null : _openMembership,
          child: Text(_t('Üyelik seçenekleri', 'Membership options')),
        ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                await widget.onRetryIdentity?.call();
              }),
        child: Text(
          widget.paidFeaturesAvailable
              ? _t('Hesabı ve üyeliği yenile', 'Refresh account and membership')
              : _t('Hesabı yenile', 'Refresh account'),
        ),
      ),
      if (widget.onManageSubscription != null)
        TextButton(
          onPressed: widget.onManageSubscription,
          child: Text(
            _t('Mağaza aboneliğini yönet', 'Manage store subscription'),
          ),
        ),
      OutlinedButton(
        onPressed: _busy ? null : () => _run(widget.account.signOut),
        child: Text(_t('Çıkış yap', 'Sign out')),
      ),
      if (widget.clearLocalData != null)
        TextButton(
          onPressed: _busy ? null : _confirmDeletion,
          child: Text(_t('Motion hesabını sil', 'Delete Motion account')),
        ),
    ],
  );
}
