import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/local_motion_environment.dart';

void main() {
  final local = LocalMotionEnvironment.from(Platform.environment);

  test(
    'verified email, profile, app-scoped access and common account deletion',
    () async {
      // The host apps use Supabase.initialize, which supplies PKCE storage.
      // This headless local test uses the implicit flow to avoid a plugin.
      final client = SupabaseClient(
        local!.apiUrl,
        local.anonKey,
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
      final mailHttp = http.Client();
      try {
        final signUp = await account.signUp(email: email, password: password);
        expect(signUp.user, isNotNull);
        expect(signUp.session, isNull);

        final link = await _confirmationLink(mailHttp, local.mailpitUrl, email);
        final request = http.Request('GET', Uri.parse(link))
          ..followRedirects = false;
        final response = await mailHttp.send(request);
        await response.stream.drain<void>();
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
        mailHttp.close();
        await client.dispose();
      }
    },
    skip: local != null ? null : 'Requires local Motion Supabase and Mailpit',
  );
  void localTest(
    String name,
    Future<void> Function(_LocalAccountFixture) action,
  ) {
    test(
      name,
      () async {
        final fixture = _LocalAccountFixture(local!);
        try {
          await action(fixture);
        } finally {
          await fixture.close();
        }
      },
      skip: local != null ? null : 'Requires local Motion Supabase and Mailpit',
    );
  }

  localTest('resend emits a new local confirmation before verified sign-in', (
    f,
  ) async {
    await f.signUp();
    final first = await f.mail('signup');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await f.account.resendConfirmation(f.email);
    final resent = await f.mail('signup', excluding: {first.id});
    expect(resent.id, isNot(first.id));
    expect(f.client.auth.currentSession, isNull);
    await f.confirm(resent);
    final signedIn = await f.account.signIn(
      email: f.email,
      password: _password,
    );
    expect(signedIn.session?.user.id, f.userId);
    await f.deleteAndCheckReceipt();
  });

  localTest('confirmation token replay supplies no new session', (f) async {
    await f.signUp();
    final mail = await f.mail('signup');
    await f.confirm(mail);
    final replay = await f.fetchVerification(mail);
    final redirect = Uri.parse(replay.headers['location']!);
    final parameters = {
      ...redirect.queryParameters,
      ...Uri.splitQueryString(redirect.fragment),
    };
    expect(parameters['error'], isNotNull);
    expect(parameters['access_token'], isNull);
    expect(f.client.auth.currentSession, isNull);
    await f.account.signIn(email: f.email, password: _password);
    await f.deleteAndCheckReceipt();
  });

  localTest('wrong password rejected for a confirmed local account', (f) async {
    await f.signUp();
    await f.confirm(await f.mail('signup'));
    await expectLater(
      f.account.signIn(email: f.email, password: 'WrongLocal!Pass123'),
      throwsA(isA<AuthException>()),
    );
    expect(f.client.auth.currentSession, isNull);
    final accepted = await f.account.signIn(
      email: f.email,
      password: _password,
    );
    expect(accepted.session?.user.id, f.userId);
    await f.deleteAndCheckReceipt();
  });

  localTest('local recovery OTP changes password and deletes captured UUID', (
    f,
  ) async {
    await f.signUp();
    await f.confirm(await f.mail('signup'));
    await f.account.signIn(email: f.email, password: _password);
    await f.account.signOut();
    expect(f.client.auth.currentSession, isNull);
    await f.account.sendPasswordReset(f.email);
    final recoveryMail = await f.mail('recovery');
    final tokenHash = recoveryMail.uri.queryParameters['token'];
    expect(tokenHash, isNotEmpty);
    final recoveryEvent = Completer<void>();
    final subscription = f.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery &&
          state.session?.user.id == f.userId &&
          !recoveryEvent.isCompleted) {
        recoveryEvent.complete();
      }
    });
    try {
      final recovered = await f.client.auth.verifyOTP(
        tokenHash: tokenHash!,
        type: OtpType.recovery,
      );
      expect(recovered.session?.user.id, f.userId);
      await recoveryEvent.future.timeout(const Duration(seconds: 5));
      const nextPassword = 'LocalOnly!Replacement456';
      final updated = await f.account.updatePassword(nextPassword);
      expect(updated.user?.id, f.userId);
      await f.account.signOut();
      await expectLater(
        f.account.signIn(email: f.email, password: _password),
        throwsA(isA<AuthException>()),
      );
      expect(f.client.auth.currentSession, isNull);
      final accepted = await f.account.signIn(
        email: f.email,
        password: nextPassword,
      );
      expect(accepted.session?.user.id, f.userId);
      await f.deleteAndCheckReceipt();
    } finally {
      await subscription.cancel();
    }
  });
}

const _password = 'LocalOnly!Pass123';

class _LocalAccountFixture {
  _LocalAccountFixture(this.local)
    : client = SupabaseClient(
        local.apiUrl,
        local.anonKey,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );

  final LocalMotionEnvironment local;
  final SupabaseClient client;
  final http.Client mailHttp = http.Client();
  final String email =
      'motion-flow-${DateTime.now().microsecondsSinceEpoch}@example.invalid';
  late String userId;
  late final MotionAccountClient account = MotionAccountClient(
    supabase: client,
    app: MotionApp.jablab,
    emailRedirectTo: 'com.yulalab.jablab://auth/callback',
  );

  Future<void> signUp() async {
    final response = await account.signUp(email: email, password: _password);
    expect(response.user, isNotNull);
    expect(response.session, isNull);
    userId = response.user!.id;
  }

  Future<_LocalVerificationMail> mail(
    String type, {
    Set<String> excluding = const {},
  }) => _verificationMail(
    mailHttp,
    local.mailpitUrl,
    email,
    type,
    excluding: excluding,
  );

  Future<http.Response> fetchVerification(_LocalVerificationMail mail) async {
    final request = http.Request('GET', mail.uri)..followRedirects = false;
    final response = await http.Response.fromStream(
      await mailHttp.send(request),
    );
    expect(response.statusCode, 303);
    expect(response.headers['location'], isNotNull);
    return response;
  }

  Future<void> confirm(_LocalVerificationMail mail) async {
    final response = await fetchVerification(mail);
    final redirect = Uri.parse(response.headers['location']!);
    expect(redirect.scheme, 'com.yulalab.jablab');
    expect(redirect.host, 'auth');
    expect(redirect.path, '/callback');
    final parameters = Uri.splitQueryString(redirect.fragment);
    expect(parameters['error'], isNull);
    expect(parameters['access_token'], isNotEmpty);
  }

  Future<void> deleteAndCheckReceipt() async {
    expect(account.currentUser?.id, userId);
    expect(
      await client.rpc(
        'motion_was_account_deleted',
        params: {'p_user_id': userId},
      ),
      isFalse,
    );
    await account.deleteCommonAccount();
    expect(account.currentUser, isNull);
    expect(
      await client.rpc(
        'motion_was_account_deleted',
        params: {'p_user_id': userId},
      ),
      isTrue,
    );
  }

  Future<void> close() async {
    mailHttp.close();
    await client.dispose();
  }
}

class _LocalVerificationMail {
  const _LocalVerificationMail(this.id, this.uri);
  final String id;
  final Uri uri;
}

Future<String> _confirmationLink(
  http.Client client,
  String mailpitUrl,
  String email,
) async => (await _verificationMail(
  client,
  mailpitUrl,
  email,
  'signup',
)).uri.toString();

Future<_LocalVerificationMail> _verificationMail(
  http.Client client,
  String mailpitUrl,
  String email,
  String type, {
  Set<String> excluding = const {},
}) async {
  for (var attempt = 0; attempt < 15; attempt++) {
    final listResponse = await client.get(
      Uri.parse('$mailpitUrl/api/v1/messages'),
    );
    expect(listResponse.statusCode, 200);
    final list = jsonDecode(listResponse.body) as Map<String, dynamic>;
    final messages = list['messages'] as List<dynamic>? ?? [];
    for (final value in messages) {
      final message = value as Map<String, dynamic>;
      final id = message['ID'] as String;
      if (excluding.contains(id)) continue;
      final recipients = message['To'] as List<dynamic>? ?? [];
      if (!recipients.any(
        (recipient) => (recipient as Map<String, dynamic>)['Address'] == email,
      ))
        continue;
      final detailResponse = await client.get(
        Uri.parse('$mailpitUrl/api/v1/message/$id'),
      );
      expect(detailResponse.statusCode, 200);
      final detail = jsonDecode(detailResponse.body) as Map<String, dynamic>;
      final plain = detail['Text'] as String;
      final link = RegExp(
        r'https?://\S+/auth/v1/verify\?\S+',
      ).firstMatch(plain);
      if (link == null) continue;
      final target = Uri.parse(link.group(0)!);
      if (target.scheme != 'http' ||
          (target.host != '127.0.0.1' && target.host != 'localhost') ||
          target.port != 55321 ||
          target.userInfo.isNotEmpty ||
          target.path != '/auth/v1/verify') {
        throw StateError('Verification link escaped the local Auth server');
      }
      if (target.queryParameters['type'] != type) continue;
      return _LocalVerificationMail(id, target);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Requested verification email was not delivered locally');
}
