import 'package:supabase_flutter/supabase_flutter.dart';

/// One Motion+ free trial per Motion account (server ledger).
///
/// Each app's Motion+ is a separate store subscription group / package, so
/// the stores alone would offer the trial again in every app. The purchase
/// adapter asks this gate before showing or buying a Motion+ trial.
abstract interface class MotionTrialGate {
  /// Whether this account may still start its one Motion+ free trial.
  /// Unknown (no session, network error) answers false: no trial is claimed.
  Future<bool> motionPlusTrialAvailable();

  /// App Store only: a server-signed JWS with `allowIntroductoryOffer=false`
  /// for [productId] once the account's trial is used, for StoreKit 2's
  /// introductory-offer-eligibility purchase option. Null when no denial is
  /// needed or it cannot be produced (for example iOS 15 without an app
  /// transaction ID); Apple's own eligibility then applies.
  Future<String?> appleIntroductoryOfferDenial(String productId);
}

/// Reads the account's own ledger row (RLS) and asks the
/// `motion-offer-eligibility` Edge Function for the App Store denial.
class SupabaseMotionTrialGate implements MotionTrialGate {
  const SupabaseMotionTrialGate({
    required this.supabase,
    required this.appId,
    required this.appTransactionId,
  });

  final SupabaseClient supabase;
  final String appId;

  /// The App Store app transaction ID (native; null where unavailable).
  final Future<String?> Function() appTransactionId;

  @override
  Future<bool> motionPlusTrialAvailable() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final row = await supabase
          .from('motion_trial_ledger')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      return row == null && supabase.auth.currentUser?.id == userId;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> appleIntroductoryOfferDenial(String productId) async {
    final token = supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final transactionId = await appTransactionId();
      if (transactionId == null) return null;
      final response = await supabase.functions.invoke(
        'motion-offer-eligibility',
        headers: {'Authorization': 'Bearer $token'},
        body: {
          'appId': appId,
          'productId': productId,
          'appTransactionId': transactionId,
        },
      );
      final data = response.data;
      if (response.status != 200 || data is! Map) return null;
      final jws = data['introductoryOfferEligibilityJws'];
      return data['trialAvailable'] == false && jws is String && jws.isNotEmpty
          ? jws
          : null;
    } on Object {
      return null;
    }
  }
}
