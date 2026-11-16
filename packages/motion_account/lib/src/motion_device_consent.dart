import 'dart:convert';
import 'dart:math';

import 'motion_account_client.dart';

/// Random wait token of one device for the under-13 parental consent flow.
///
/// It is 32 random bytes (base64url, no padding, 43 characters) and is never
/// derived from the child, the device identity, an address or a birth date.
/// Core never stores it: the host keeps it (file or secure store) until the
/// account is created. The server keeps only its SHA-256 digest.
abstract final class MotionDeviceConsentToken {
  static const int byteLength = 32;
  static const int length = 43;

  static String generate({Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => source.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// True for a well-formed token (43 base64url characters).
  static bool isWellFormed(String? token) =>
      token != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token);
}

/// Parent approval state read for one device token. Unverified or unknown
/// answers are [unavailable]: they never grant an account.
class MotionDeviceConsentStatus {
  const MotionDeviceConsentStatus({
    required this.state,
    this.expiresAt,
    this.decidedAt,
    this.verified = true,
  });

  /// Fail-closed answer: unknown, unreachable or malformed.
  const MotionDeviceConsentStatus.unavailable()
    : state = MotionParentalConsent.none,
      expiresAt = null,
      decidedAt = null,
      verified = false;

  final MotionParentalConsent state;
  final DateTime? expiresAt;
  final DateTime? decidedAt;

  /// True only for a well-formed server answer.
  final bool verified;

  /// An account may be created only for a verified approval.
  bool get allowsAccount => verified && state == MotionParentalConsent.approved;
}

/// What can happen to one parental consent record.
enum MotionConsentEvent {
  request,
  approve,
  deny,
  linkExpire,
  retentionPurge,
  withdraw,
}

/// Pure transition table of the parental consent state. A null result means
/// the transition is not allowed (refuse it).
abstract final class MotionParentalConsentMachine {
  static MotionParentalConsent? next(
    MotionParentalConsent from,
    MotionConsentEvent event,
  ) {
    switch (from) {
      case MotionParentalConsent.none:
        return event == MotionConsentEvent.request
            ? MotionParentalConsent.pending
            : null;
      case MotionParentalConsent.pending:
        return switch (event) {
          MotionConsentEvent.request => MotionParentalConsent.pending,
          MotionConsentEvent.approve => MotionParentalConsent.approved,
          MotionConsentEvent.deny => MotionParentalConsent.denied,
          MotionConsentEvent.linkExpire => MotionParentalConsent.expired,
          MotionConsentEvent.retentionPurge => MotionParentalConsent.none,
          MotionConsentEvent.withdraw => null,
        };
      case MotionParentalConsent.approved:
        return switch (event) {
          MotionConsentEvent.retentionPurge => MotionParentalConsent.none,
          MotionConsentEvent.withdraw => MotionParentalConsent.withdrawn,
          _ => null,
        };
      case MotionParentalConsent.denied:
        return event == MotionConsentEvent.retentionPurge
            ? MotionParentalConsent.none
            : null;
      case MotionParentalConsent.expired:
        return switch (event) {
          MotionConsentEvent.request => MotionParentalConsent.pending,
          MotionConsentEvent.retentionPurge => MotionParentalConsent.none,
          _ => null,
        };
      case MotionParentalConsent.withdrawn:
        return event == MotionConsentEvent.retentionPurge
            ? MotionParentalConsent.none
            : null;
    }
  }
}
