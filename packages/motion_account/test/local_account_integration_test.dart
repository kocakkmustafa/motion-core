import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final apiUrl = Platform.environment['MOTION_LOCAL_API_URL'];
  final anonKey = Platform.environment['MOTION_LOCAL_ANON_KEY'];
  final mailpitUrl = Platform.environment['MOTION_LOCAL_MAILPIT_URL'];
  final enabled = apiUrl != null && anonKey != null && mailpitUrl != null;

  test(
    'verified email, profile, app-scoped access and common account deletion',
    () async {
      // The host apps use Supabase.initialize, which supplies PKCE storage.
      // This headless local test uses the implicit flow to avoid a plugin.
      final client = SupabaseClient(
        apiUrl!,
        anonKey!,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final account = MotionAccountClient(
        supabase: client,
        app: MotionApp.jablab,
        emailRedirectTo: 'com.yulalab.jablab://auth/callback',
      );
      final email =
          'motion-test-${DateTime.now().microsecondsSinceEpoch}@example.invalid';
      const password = 'LocalOnly!Pass123';
      try {
        final signUp = await account.signUp(email: email, password: password);
        expect(signUp.user, isNotNull);
        expect(signUp.session, isNull);

        final link = await _confirmationLink(mailpitUrl!, email);
        final request = http.Request('GET', Uri.parse(link))
          ..followRedirects = false;
        final response = await http.Client().send(request);
        expect(response.statusCode, 303);

        final signIn = await account.signIn(email: email, password: password);
        expect(signIn.session, isNotNull);
        await account.saveDisplayName('Motion Member');
        final profile = await account.loadProfile();
        expect(profile?['display_name'], 'Motion Member');
        expect(
          await client.rpc(
            'motion_has_active_membership',
            params: {'p_app_id': MotionApp.jablab.name},
          ),
          isFalse,
        );

        final otherApp = MotionAccountClient(
          supabase: client,
          app: MotionApp.gravita,
          emailRedirectTo: 'com.yulalab.gravita://auth/callback',
        );
        expect(otherApp.currentUser?.id, account.currentUser?.id);
        expect(
          await client.rpc(
            'motion_has_active_membership',
            params: {'p_app_id': MotionApp.gravita.name},
          ),
          isFalse,
        );

        await account.deleteCommonAccount();
        expect(account.currentUser, isNull);
      } finally {
        client.dispose();
      }
    },
    skip: enabled ? null : 'Requires local Motion Supabase and Mailpit',
  );
}

Future<String> _confirmationLink(String mailpitUrl, String email) async {
  for (var attempt = 0; attempt < 15; attempt++) {
    final listResponse = await http.get(
      Uri.parse('$mailpitUrl/api/v1/messages'),
    );
    expect(listResponse.statusCode, 200);
    final list = jsonDecode(listResponse.body) as Map<String, dynamic>;
    final messages = list['messages'] as List<dynamic>? ?? [];
    for (final value in messages) {
      final message = value as Map<String, dynamic>;
      final recipients = message['To'] as List<dynamic>? ?? [];
      if (!recipients.any(
        (recipient) => (recipient as Map<String, dynamic>)['Address'] == email,
      )) {
        continue;
      }
      final detailResponse = await http.get(
        Uri.parse('$mailpitUrl/api/v1/message/${message['ID']}'),
      );
      expect(detailResponse.statusCode, 200);
      final detail = jsonDecode(detailResponse.body) as Map<String, dynamic>;
      final plain = detail['Text'] as String;
      final link = RegExp(
        r'https?://\S+/auth/v1/verify\?\S+',
      ).firstMatch(plain);
      if (link != null) return link.group(0)!;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Confirmation email was not delivered locally');
}
