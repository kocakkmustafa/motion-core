import 'package:flutter/material.dart';

import 'motion_account_client.dart';
import 'motion_account_localizations.dart';
import 'motion_membership_page.dart';
import 'motion_release_policy.dart';

/// Checks a paid lesson at the moment it starts, before the host creates a
/// camera or audio session. Catalogues and previews can remain visible.
Future<bool> requireMotionPaidAccess(
  BuildContext context, {
  required MotionAccountClient account,
  required WidgetBuilder accountPageBuilder,
  WidgetBuilder? membershipPageBuilder,
  bool paidFeaturesAvailable = motionPaidFeaturesAvailable,
}) async {
  if (!paidFeaturesAvailable) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          MotionAccountLocalizations.of(context).text(
            MotionAccountString.futureSession,
          ),
        ),
      ),
    );
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
              MotionAccountLocalizations.of(context).text(
                MotionAccountString.membershipVerificationFailed,
              ),
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
