import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Account implements MotionAccountClient {
  User? user;
  bool active = false;
  bool unavailable = false;
  int checks = 0;

  @override
  User? get currentUser => user;

  @override
  Future<bool> hasActiveMembership() async {
    checks++;
    if (unavailable) throw StateError('network unavailable');
    return active;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _user = User(
  id: '11111111-1111-4111-8111-111111111111',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  createdAt: '2026-09-24T00:00:00Z',
);

void main() {
  testWidgets('first release keeps paid sessions and purchase route closed', (
    tester,
  ) async {
    final account = _Account()..user = _user;
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => allowed = await requireMotionPaidAccess(
                context,
                account: account,
                accountPageBuilder: (_) =>
                    const Scaffold(body: Text('ACCOUNT')),
                membershipPageBuilder: (_) =>
                    const Scaffold(body: Text('PURCHASE')),
              ),
              child: const Text('START'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('START'));
    await tester.pump();

    expect(allowed, isFalse);
    expect(account.checks, 0);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('PURCHASE'), findsNothing);
    expect(
      find.text('This session will open in a future update.'),
      findsOneWidget,
    );
  });

  testWidgets('active member enters without opening account or purchase', (
    tester,
  ) async {
    final account = _Account()
      ..user = _user
      ..active = true;
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async => allowed = await requireMotionPaidAccess(
                  context,
                  account: account,
                  paidFeaturesAvailable: true,
                  accountPageBuilder: (_) =>
                      const Scaffold(body: Text('ACCOUNT')),
                  membershipPageBuilder: (_) =>
                      const Scaffold(body: Text('PURCHASE')),
                ),
                child: const Text('START'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(account.checks, 1);
    expect(find.text('ACCOUNT'), findsNothing);
    expect(find.text('PURCHASE'), findsNothing);
  });

  testWidgets('sign-in and purchase are rechecked before entry', (
    tester,
  ) async {
    final account = _Account();
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async => allowed = await requireMotionPaidAccess(
                  context,
                  account: account,
                  paidFeaturesAvailable: true,
                  accountPageBuilder: (pageContext) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        account.user = _user;
                        Navigator.of(pageContext).pop();
                      },
                      child: const Text('SIGN IN'),
                    ),
                  ),
                  membershipPageBuilder: (pageContext) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        account.active = true;
                        Navigator.of(pageContext).pop();
                      },
                      child: const Text('COMPLETE PURCHASE'),
                    ),
                  ),
                ),
                child: const Text('START'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN'), findsOneWidget);
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();
    expect(find.text('COMPLETE PURCHASE'), findsOneWidget);
    await tester.tap(find.text('COMPLETE PURCHASE'));
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(account.checks, 2);
  });

  testWidgets('verification outage fails closed with a retry message', (
    tester,
  ) async {
    final account = _Account()
      ..user = _user
      ..unavailable = true;
    bool? allowed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async => allowed = await requireMotionPaidAccess(
                  context,
                  account: account,
                  paidFeaturesAvailable: true,
                  accountPageBuilder: (_) =>
                      const Scaffold(body: Text('ACCOUNT')),
                  membershipPageBuilder: (_) =>
                      const Scaffold(body: Text('PURCHASE')),
                ),
                child: const Text('START'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('START'));
    await tester.pump();

    expect(allowed, isFalse);
    expect(
      find.text(
        'Membership could not be verified. Check your connection and retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('PURCHASE'), findsNothing);
  });
}
