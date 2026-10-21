import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Account mutations whose remote effect can be unknown after a lost reply.
enum MotionAccountOperation {
  signUp,
  signIn,
  passwordReset,
  resendConfirmation,
  updatePassword,
  signOut,
  continueAsGuest,
  saveProfile,
  deleteAccount,
}

/// No definite server answer arrived before the operation's total deadline,
/// or the transport failed after the request may have been sent.
///
/// The remote effect may or may not have happened. This is not a failure
/// receipt: callers must not retry the same mutation automatically, must not
/// erase local data, and must not report success. A late SDK effect (for
/// example a Session published by a delayed sign-in reply) is still observed
/// through the ordinary Auth stream and identity proof.
class MotionOperationUnknown implements Exception {
  const MotionOperationUnknown(this.operation);

  final MotionAccountOperation operation;

  @override
  String toString() => 'MotionOperationUnknown(${operation.name})';
}

/// One budget for a whole operation: a single timer started once.
///
/// Every stage races the same expiry, so per-stage waits can never reset or
/// extend the total. [signal] never completes with an error and can be passed
/// to SDK `abortSignal` parameters. Abort releases the local request only; it
/// never rolls back a server effect.
class MotionDeadline {
  MotionDeadline(Duration total) {
    _timer = Timer(total, _expire);
  }

  late final Timer _timer;
  final _expired = Completer<void>();

  bool get isExpired => _expired.isCompleted;
  Future<void> get signal => _expired.future;

  void _expire() {
    if (!_expired.isCompleted) _expired.complete();
  }

  /// Settles the budget early, e.g. when the owner stops waiting. Pending
  /// [race] calls then fail like an expiry.
  void close() {
    _timer.cancel();
    _expire();
  }

  /// Completes with [work]'s result, or throws [TimeoutException] when the
  /// budget ends first. A later result or error of [work] is observed and
  /// discarded, never left as an unhandled zone error.
  ///
  /// The result completer is synchronous: a prompt [work] resumes its caller
  /// in the same microtask as a direct `await` would, so wrapping an existing
  /// await in a budget does not reorder it against other listeners.
  Future<T> race<T>(Future<T> work) {
    if (isExpired) {
      work.ignore();
      return Future<T>.error(TimeoutException('Motion operation deadline'));
    }
    final result = Completer<T>.sync();
    work.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    _expired.future.then((_) {
      if (!result.isCompleted) {
        result.completeError(TimeoutException('Motion operation deadline'));
      }
    });
    return result.future;
  }

  /// Races [work] against both this budget and a shorter per-stage [limit].
  /// The stage timer is cancelled as soon as the race settles.
  Future<T> raceWithin<T>(Duration limit, Future<T> work) {
    final stage = MotionDeadline(limit);
    final both = Completer<T>.sync();
    race(stage.race(work)).then(
      (value) {
        if (!both.isCompleted) both.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!both.isCompleted) both.completeError(error, stack);
      },
    );
    both.future.then(
      (_) => stage.close(),
      onError: (Object _) => stage.close(),
    );
    return both.future;
  }
}

/// True only when a server definitely answered with a rejection, so the
/// request is known not to have produced its effect. Transport failures,
/// retryable/5xx replies and unknown errors could follow a committed effect.
bool motionServerRejected(Object error) {
  if (error is AuthRetryableFetchException) return false;
  if (error is AuthException) {
    final status = int.tryParse(error.statusCode ?? '');
    return status != null && status >= 400 && status < 500;
  }
  if (error is PostgrestException) {
    // A decoded error body carries a SQLSTATE/PGRST code: the database answered
    // and rolled the statement back. A bare three-digit code is the HTTP status
    // of an undecodable body; a 5xx gateway reply may follow a commit.
    final code = error.code ?? '';
    final http = RegExp(r'^\d{3}$').hasMatch(code) ? int.parse(code) : null;
    return http == null || http < 500;
  }
  if (error is FunctionException) {
    return error.status >= 400 && error.status < 500;
  }
  return false;
}
