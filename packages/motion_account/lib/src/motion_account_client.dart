import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'motion_account_deadline.dart';
import 'motion_age_policy.dart';

export 'motion_account_deadline.dart'
    show MotionAccountOperation, MotionOperationUnknown;

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

/// Parent/guardian approval state of a teen account below its consent age.
enum MotionParentalConsent { none, pending, approved, denied, expired }

/// Age declaration and consent state of the signed-in account.
class MotionAgeStatus {
  const MotionAgeStatus({required this.declaration, required this.consent});

  /// Null for an account created before age declarations (ask once).
  final MotionAgeDeclaration? declaration;
  final MotionParentalConsent consent;

  bool get declared => declaration != null;

  /// Band on the device clock. The server recomputes it for enforcement.
  MotionAgeBand? bandOn(DateTime today) => declaration == null
      ? null
      : MotionAgePolicy.bandFor(declaration!, today: today);

  /// Account features stay closed until a required parent approves.
  bool restrictedOn(DateTime today) {
    final band = bandOn(today);
    return band == MotionAgeBand.blocked ||
        (band == MotionAgeBand.parentalConsentRequired &&
            consent != MotionParentalConsent.approved);
  }
}

/// Typed reasons a parental consent request was refused by the server.
enum MotionConsentRequestError {
  invalidParentEmail,
  parentEmailIsTeen,
  notRequired,
  alreadyApproved,
  tooSoon,
  dailyLimit,
  mailUnavailable,
}

class MotionConsentRequestRefused implements Exception {
  const MotionConsentRequestRefused(this.reason);
  final MotionConsentRequestError reason;

  @override
  String toString() => 'MotionConsentRequestRefused(${reason.name})';
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
///
/// Every network method has one total deadline. Reads throw
/// [TimeoutException]; a mutation without a definite server answer throws
/// [MotionOperationUnknown]. Nothing here retries a mutation automatically.
class MotionAccountClient {
  MotionAccountClient({
    required SupabaseClient supabase,
    required this.app,
    required this.emailRedirectTo,
    Future<bool> Function(String userId)? deletionReceipt,
    this.operationTimeout = const Duration(seconds: 20),
    this.readTimeout = const Duration(seconds: 10),
  }) : _supabase = supabase,
       _deletionReceipt = deletionReceipt;

  final SupabaseClient _supabase;
  SupabaseClient get supabase => _supabase;
  final MotionApp app;
  final String emailRedirectTo;
  // The runtime's anonymous receipt probe. It reads the same server receipt
  // that independent cleanup uses; the page never builds a second client.
  final Future<bool> Function(String userId)? _deletionReceipt;

  /// The receipt probe, so a host wrapper that `extends` this client can pass
  /// `deletionReceipt: original.deletionReceipt` (and the same timeouts) to
  /// `super` and keep lost-reply deletion readback.
  Future<bool> Function(String userId)? get deletionReceipt => _deletionReceipt;

  /// Total budget for one mutation, including SDK preflight and decoding.
  final Duration operationTimeout;

  /// Total budget for one read (profile, membership, deletion receipt).
  final Duration readTimeout;

  User? get currentUser => _supabase.auth.currentUser;
  Stream<AuthState> get authChanges => _supabase.auth.onAuthStateChange;

  /// Runs one mutation under [operationTimeout]. Only a definite server
  /// rejection propagates as-is; a timeout or transport loss is unknown.
  Future<T> _mutation<T>(
    MotionAccountOperation operation,
    Future<T> Function(MotionDeadline deadline) send,
  ) async {
    final deadline = MotionDeadline(operationTimeout);
    try {
      return await deadline.race(Future.sync(() => send(deadline)));
    } catch (error) {
      if (motionServerRejected(error)) rethrow;
      if (error is ArgumentError || error is AuthSessionMissingException) {
        rethrow; // Local precondition: nothing was dispatched.
      }
      throw MotionOperationUnknown(operation);
    } finally {
      deadline.close();
    }
  }

  Future<T> _read<T>(Future<T> Function(MotionDeadline deadline) read) async {
    final deadline = MotionDeadline(readTimeout);
    try {
      return await deadline.race(Future.sync(() => read(deadline)));
    } finally {
      deadline.close();
    }
  }

  // Auth mutations expose no per-request abort. The deadline bounds only this
  // caller's wait; a late SDK reply can still publish a Session/event, which
  // the runtime proof and owner fences handle like any other Auth change.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) => _mutation(
    MotionAccountOperation.signUp,
    (_) => _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: emailRedirectTo,
    ),
  );

  /// Sign-up with the neutral age screen result. The server stores it once
  /// and rejects an under-13 declaration; only `YYYY-MM`, country and policy
  /// version are sent, and Auth metadata is stripped after capture. A separate
  /// method keeps existing [signUp] overrides in host wrappers source-compatible.
  Future<AuthResponse> signUpWithAge({
    required String email,
    required String password,
    required MotionAgeDeclaration age,
  }) => _mutation(
    MotionAccountOperation.signUp,
    (_) => _supabase.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: emailRedirectTo,
      data: {'motion_age': age.toJson()},
    ),
  );

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => _mutation(
    MotionAccountOperation.signIn,
    (_) => _supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> sendPasswordReset(String email) => _mutation(
    MotionAccountOperation.passwordReset,
    (_) => _supabase.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: emailRedirectTo,
    ),
  );

  Future<void> resendConfirmation(String email) =>
      _mutation(MotionAccountOperation.resendConfirmation, (_) async {
        await _supabase.auth.resend(
          type: OtpType.signup,
          email: email.trim(),
          emailRedirectTo: emailRedirectTo,
        );
      });

  Future<UserResponse> updatePassword(String password) => _mutation(
    MotionAccountOperation.updatePassword,
    (_) => _supabase.auth.updateUser(UserAttributes(password: password)),
  );

  /// The SDK discards the in-memory Session before contacting the server.
  /// [MotionOperationUnknown] then means this device is signed out locally
  /// while remote revocation is unconfirmed; check [currentUser].
  Future<void> signOut() => _mutation(
    MotionAccountOperation.signOut,
    (_) => _supabase.auth.signOut(),
  );

  /// Deletes the common identity across all five apps. The host app must
  /// remove its own local journal after this method confirms deletion, and explain
  /// that store subscriptions are managed in Apple/Google account settings.
  ///
  /// When the reply is lost or times out, the client reads the anonymous
  /// deletion receipt once. Only a positive receipt for the captured UUID is
  /// treated as confirmation; false, timeout or error throws
  /// [MotionOperationUnknown] and keeps every local file. A 4xx reply is a
  /// definite rejection. Remote deletion is never rolled back by a timeout.
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    final user = _requireUser();
    final initiatingSession = _supabase.auth.currentSession;
    final token = initiatingSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException('Sign in required');
    }
    final deadline = MotionDeadline(operationTimeout);
    FunctionResponse? response;
    Object? dispatchError;
    try {
      response = await deadline.race(
        _supabase.functions.invoke(
          'motion-delete-account',
          // Encoding and dispatch may yield while another auth callback arrives.
          // This authorization belongs to the account that requested deletion.
          headers: {'Authorization': 'Bearer $token'},
          body: {'confirmation': 'DELETE', 'expectedUserId': user.id},
          abortSignal: deadline.signal,
        ),
      );
    } catch (error) {
      dispatchError = error;
    } finally {
      deadline.close();
    }
    if (dispatchError != null) {
      if (motionServerRejected(dispatchError)) {
        throw StateError('Account deletion was rejected by the server');
      }
      if (!await _deletionReceiptConfirms(user.id)) {
        throw const MotionOperationUnknown(
          MotionAccountOperation.deleteAccount,
        );
      }
    } else if (response!.status != 200 ||
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

  Future<bool> _deletionReceiptConfirms(String userId) async {
    final probe = _deletionReceipt;
    if (probe == null) return false;
    try {
      return await _read((_) => probe(userId)) == true;
    } catch (_) {
      return false; // Unavailable is not a negative receipt; it stays unknown.
    }
  }

  /// One bounded read. The abort signal stops PostgREST's own GET retries and
  /// releases the request; the outer race also bounds the Auth token preflight.
  Future<Map<String, dynamic>?> loadProfile() async {
    final user = _requireUser();
    return _read(
      (deadline) => _supabase
          .from('motion_profiles')
          .select('user_id,display_name,created_at,updated_at')
          .eq('user_id', user.id)
          .maybeSingle()
          .abortSignal(deadline.signal),
    );
  }

  /// A lost upsert reply throws [MotionOperationUnknown]. The write is
  /// last-write-wins with a fresh timestamp: a later equal profile read shows
  /// the current state, not an exactly-once acknowledgement of this call.
  Future<void> saveDisplayName(String name) async {
    final user = _requireUser();
    final trimmed = name.trim();
    if (trimmed.length > 80) {
      throw ArgumentError.value(name, 'name', 'Maximum 80 characters');
    }
    await _mutation(
      MotionAccountOperation.saveProfile,
      (deadline) => _supabase
          .from('motion_profiles')
          .upsert({
            'user_id': user.id,
            'display_name': trimmed,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .abortSignal(deadline.signal),
    );
  }

  /// Reads the signed-in account's age declaration and consent state.
  Future<MotionAgeStatus> ageStatus() async {
    final user = _requireUser();
    return _read((deadline) async {
      final declaration = await _supabase
          .from('motion_age_declarations')
          .select('birth_year_month,country,policy_version')
          .eq('user_id', user.id)
          .maybeSingle()
          .abortSignal(deadline.signal);
      final consent = await _supabase
          .from('motion_parental_consents')
          .select('status')
          .eq('user_id', user.id)
          .maybeSingle()
          .abortSignal(deadline.signal);
      return MotionAgeStatus(
        declaration: MotionAgeDeclaration.fromJson(declaration),
        consent: switch (consent?['status']) {
          'pending' => MotionParentalConsent.pending,
          'approved' => MotionParentalConsent.approved,
          'denied' => MotionParentalConsent.denied,
          'expired' => MotionParentalConsent.expired,
          _ => MotionParentalConsent.none,
        },
      );
    });
  }

  /// One-time declaration for an account without one. Returns the server's
  /// band. An under-13 declaration is refused with [PostgrestException]
  /// code `P0013`; a second declaration with `23505`.
  Future<MotionAgeBand> recordAgeDeclaration(
    MotionAgeDeclaration declaration,
  ) async {
    _requireUser();
    final band = await _mutation(
      MotionAccountOperation.declareAge,
      (deadline) => _supabase
          .rpc(
            'motion_record_age_declaration',
            params: {
              'p_birth_year_month': declaration.birthYearMonth,
              'p_country': declaration.countryCode,
              'p_policy_version': declaration.policyVersion,
            },
          )
          .abortSignal(deadline.signal),
    );
    return switch (band) {
      'parental_consent_required' => MotionAgeBand.parentalConsentRequired,
      'teen' => MotionAgeBand.teen,
      'adult' => MotionAgeBand.adult,
      _ => throw StateError('Unexpected age band'),
    };
  }

  /// Mails one approval link to the parent/guardian. A lost reply is
  /// [MotionOperationUnknown] (a mail may still arrive); a refusal is
  /// [MotionConsentRequestRefused]. The address is not stored in clear.
  Future<void> requestParentalConsent({
    required String parentEmail,
    required String locale,
  }) async {
    _requireUser();
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException('Sign in required');
    }
    try {
      await _mutation(
        MotionAccountOperation.parentalConsent,
        (deadline) => _supabase.functions.invoke(
          'motion-parental-consent',
          headers: {'Authorization': 'Bearer $token'},
          body: {
            'action': 'request',
            'parentEmail': parentEmail.trim(),
            'locale': locale,
          },
          abortSignal: deadline.signal,
        ),
      );
    } on FunctionException catch (error) {
      final code = error.details is Map ? error.details['error'] : null;
      final reason = switch (code) {
        'invalid_parent_email' => MotionConsentRequestError.invalidParentEmail,
        'parent_email_is_teen' => MotionConsentRequestError.parentEmailIsTeen,
        'consent_not_required' => MotionConsentRequestError.notRequired,
        'already_approved' => MotionConsentRequestError.alreadyApproved,
        'too_soon' => MotionConsentRequestError.tooSoon,
        'daily_limit' => MotionConsentRequestError.dailyLimit,
        _ => null,
      };
      if (reason != null) throw MotionConsentRequestRefused(reason);
      rethrow;
    } on MotionOperationUnknown {
      rethrow;
    }
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
    // A timeout throws; unknown never grants access. Aborting the request
    // does not stop provider/DB work the Edge Function already started.
    final response = await _read(
      (deadline) => _supabase.functions.invoke(
        'motion-check-membership',
        headers: {'Authorization': 'Bearer $token'},
        body: {'appId': app.name},
        abortSignal: deadline.signal,
      ),
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
