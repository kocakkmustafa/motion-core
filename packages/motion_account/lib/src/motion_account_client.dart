import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixed product boundary. One login works across all five apps. Individual
/// rights stay in one app; a verified Motion+ right covers all five.
enum MotionApp { ostinato, gravita, choreia, jablab, lissom }

/// Store-refreshed rights for the selected app and the whole Motion account.
/// [anyActive] lets the purchase screen prevent an overlapping subscription.
class MotionMembershipStatus {
  const MotionMembershipStatus({required this.active, required this.anyActive});

  final bool active;
  final bool anyActive;
}

/// Remote deletion succeeded, but this device could not clear its own files.
/// The server receipt lets the app retry cleanup when it next opens online.
class MotionLocalCleanupPending implements Exception {
  const MotionLocalCleanupPending();
}

/// A thin client around Supabase Auth and the RLS-protected Motion tables.
///
/// Initialize Supabase once in the host app with the same Motion project URL
/// and publishable key. Never put a service-role key in a mobile build.
class MotionAccountClient {
  MotionAccountClient({
    required SupabaseClient supabase,
    required this.app,
    required this.emailRedirectTo,
  }) : _supabase = supabase;

  final SupabaseClient _supabase;
  SupabaseClient get supabase => _supabase;
  final MotionApp app;
  final String emailRedirectTo;

  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authChanges => _supabase.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _supabase.auth.signUp(
    email: email.trim(),
    password: password,
    emailRedirectTo: emailRedirectTo,
  );

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => _supabase.auth.signInWithPassword(
    email: email.trim(),
    password: password,
  );

  Future<void> sendPasswordReset(String email) => _supabase.auth
      .resetPasswordForEmail(email.trim(), redirectTo: emailRedirectTo);

  Future<void> resendConfirmation(String email) async {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: emailRedirectTo,
    );
  }

  Future<UserResponse> updatePassword(String password) =>
      _supabase.auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => _supabase.auth.signOut();

  /// Deletes the common identity across all five apps. The host app must
  /// remove its own local journal after this method confirms deletion, and explain
  /// that store subscriptions are managed in Apple/Google account settings.
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    final user = _requireUser();
    final initiatingSession = _supabase.auth.currentSession;
    final token = initiatingSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException('Sign in required');
    }
    final response = await _supabase.functions.invoke(
      'motion-delete-account',
      // Encoding and dispatch may yield while another auth callback arrives.
      // This authorization belongs to the account that requested deletion.
      headers: {'Authorization': 'Bearer $token'},
      body: {'confirmation': 'DELETE', 'expectedUserId': user.id},
    );
    if (response.status != 200 ||
        response.data is! Map ||
        response.data['deleted'] != true ||
        response.data['userId'] != user.id) {
      throw StateError('Account deletion was not confirmed by the server');
    }
    Object? localCleanupError;
    try {
      await afterRemoteDelete?.call(user.id);
    } catch (error) {
      localCleanupError = error;
    } finally {
      if (currentUser?.id == user.id &&
          identical(_supabase.auth.currentSession, initiatingSession) &&
          _supabase.auth.currentSession?.accessToken == token) {
        try {
          await _supabase.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          // GoTrue may reject /logout after the server deleted the user.
          // The receipt retries any failed local cleanup on the next launch.
        }
      }
    }
    if (localCleanupError != null) {
      throw const MotionLocalCleanupPending();
    }
  }

  Future<Map<String, dynamic>?> loadProfile() async {
    final user = _requireUser();
    return _supabase
        .from('motion_profiles')
        .select('user_id,display_name,created_at,updated_at')
        .eq('user_id', user.id)
        .maybeSingle();
  }

  Future<void> saveDisplayName(String name) async {
    final user = _requireUser();
    final trimmed = name.trim();
    if (trimmed.length > 80) {
      throw ArgumentError.value(name, 'name', 'Maximum 80 characters');
    }
    await _supabase.from('motion_profiles').upsert({
      'user_id': user.id,
      'display_name': trimmed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Refreshes each currently granting purchase with its store before
  /// answering. Network/provider errors propagate so the UI can retry; an old
  /// database row never becomes an implicit success during an outage.
  Future<MotionMembershipStatus> membershipStatus() async {
    final userId = _requireUser().id;
    final initiatingSession = _supabase.auth.currentSession;
    final token = initiatingSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException('Sign in required');
    }
    final response = await _supabase.functions.invoke(
      'motion-check-membership',
      headers: {'Authorization': 'Bearer $token'},
      body: {'appId': app.name},
    );
    final result = response.data;
    if (currentUser?.id != userId ||
        !identical(_supabase.auth.currentSession, initiatingSession) ||
        _supabase.auth.currentSession?.accessToken != token ||
        response.status != 200 ||
        result is! Map ||
        result['active'] is! bool ||
        result['anyActive'] is! bool ||
        (result['active'] == true && result['anyActive'] != true)) {
      throw StateError('Membership response was not verified');
    }
    return MotionMembershipStatus(
      active: result['active'] as bool,
      anyActive: result['anyActive'] as bool,
    );
  }

  Future<bool> hasActiveMembership() async => (await membershipStatus()).active;

  User _requireUser() {
    final user = currentUser;
    if (user == null) throw const AuthException('Sign in required');
    return user;
  }
}
