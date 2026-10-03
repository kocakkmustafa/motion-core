import 'package:supabase_flutter/supabase_flutter.dart';

import 'entitlement_status.dart';
import 'purchase_adapter.dart';
import 'purchase_state.dart';
import 'server_adapter.dart';
import 'store_product_ref.dart';

/// Calls the Motion Edge Function with the current Supabase Auth session.
/// The service-role key and store credentials never enter the app bundle.
class SupabasePurchaseServerAdapter implements ServerAdapter {
  const SupabasePurchaseServerAdapter(this.supabase);

  final SupabaseClient supabase;

  @override
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence) async {
    final userId = supabase.auth.currentUser?.id;
    final initiatingSession = supabase.auth.currentSession;
    final token = initiatingSession?.accessToken;
    if (userId == null || userId.isEmpty || token == null || token.isEmpty) {
      return null;
    }
    final response = await supabase.functions.invoke(
      'motion-verify-purchase',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'store': switch (evidence.platform) {
          StorePlatform.ios => 'apple',
          StorePlatform.android => 'google',
        },
        'originatingAppId': evidence.originatingAppId,
        'productId': evidence.productId,
        'verificationData': evidence.verificationData,
        if (evidence.transactionId != null)
          'transactionId': evidence.transactionId,
      },
    );
    if (response.status != 200 ||
        supabase.auth.currentUser?.id != userId ||
        !identical(supabase.auth.currentSession, initiatingSession) ||
        supabase.auth.currentSession?.accessToken != token) {
      return null;
    }
    final data = response.data;
    if (data is! Map ||
        data['userId'] != userId ||
        data['productId'] != evidence.productId ||
        (data['appId'] != evidence.originatingAppId &&
            data['appId'] != motionPlusScope) ||
        data['expiresAt'] is! String ||
        data['lastVerifiedAt'] is! String) {
      return null;
    }
    final expiry = DateTime.tryParse(data['expiresAt'] as String);
    final verifiedAt = DateTime.tryParse(data['lastVerifiedAt'] as String);
    if (expiry == null ||
        verifiedAt == null ||
        !expiry.isUtc ||
        !verifiedAt.isUtc) {
      return null;
    }
    final state = switch (data['state']) {
      'active' || 'grace' => PurchaseState.entitled,
      'expired' || 'revoked' => PurchaseState.notEntitled,
      _ => null,
    };
    if (state == null) return null;
    return EntitlementStatus(
      state: state,
      userId: userId,
      appId: data['appId'] as String,
      productId: evidence.productId,
      expiresAt: expiry,
      lastVerifiedAt: verifiedAt,
      source: EntitlementSource.server,
    );
  }
}
