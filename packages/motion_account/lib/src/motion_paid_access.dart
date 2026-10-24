import 'package:flutter/material.dart';

import 'motion_account_client.dart';
import 'motion_account_localizations.dart';
import 'motion_membership_page.dart';
import 'motion_release_policy.dart';

/// Checks a paid lesson or practice session at the moment it starts, before
/// the host creates a camera or audio session. Catalogues, previews and
/// recorded progress remain visible.
///
/// Opens sign-in and the membership page when needed. Since 0.4.0 the gate
/// follows [motionSubscriptionSalesAvailable] (true): a host that relied on
/// the old default to keep a camera path closed must gate that path with
/// [requireMotionCameraAccess] or [motionCameraCoachingAvailable] first.
Future<bool> requireMotionPaidAccess(
  BuildContext context, {
  required MotionAccountClient account,
  required WidgetBuilder accountPageBuilder,
  WidgetBuilder? membershipPageBuilder,
  bool salesAvailable = motionSubscriptionSalesAvailable,
  @Deprecated('Use salesAvailable') bool? paidFeaturesAvailable,
}) async {
  if (!(paidFeaturesAvailable ?? salesAvailable)) {
    _showFutureSession(context);
    return false;
  }
  if (account.currentUser == null) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: accountPageBuilder));
    if (!context.mounted || account.currentUser == null) return false;
  }

  Future<bool?> check() async {
    final userId = account.currentUser?.id;
    if (userId == null) return false;
    try {
      final active = await account.hasActiveMembership();
      if (!context.mounted || account.currentUser?.id != userId) return false;
      return active;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              MotionAccountLocalizations.of(
                context,
              ).text(MotionAccountString.membershipVerificationFailed),
            ),
          ),
        );
      }
      return null;
    }
  }

  final current = await check();
  if (current == true) return true;
  if (current == null || !context.mounted) return false;

  final userId = account.currentUser?.id;
  if (userId == null) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          membershipPageBuilder ??
          (_) => MotionMembershipPage(account: account),
    ),
  );
  if (!context.mounted || account.currentUser?.id != userId) return false;
  return await check() == true;
}

/// Gate for camera coaching, live measurement and scoring sessions.
///
/// While [cameraCoachingAvailable] is false (first release) it shows the
/// "future update" notice and returns false without any account or purchase
/// step. When opened it applies the same paid check as
/// [requireMotionPaidAccess].
Future<bool> requireMotionCameraAccess(
  BuildContext context, {
  required MotionAccountClient account,
  required WidgetBuilder accountPageBuilder,
  WidgetBuilder? membershipPageBuilder,
  bool cameraCoachingAvailable = motionCameraCoachingAvailable,
}) async {
  if (!cameraCoachingAvailable) {
    _showFutureSession(context);
    return false;
  }
  return requireMotionPaidAccess(
    context,
    account: account,
    accountPageBuilder: accountPageBuilder,
    membershipPageBuilder: membershipPageBuilder,
  );
}

void _showFutureSession(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        MotionAccountLocalizations.of(
          context,
        ).text(MotionAccountString.futureSession),
      ),
    ),
  );
}
