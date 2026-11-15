import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A host wrapper's membership read: the test decides if and when it answers.
class _Account implements MotionAccountClient {
  _Account(this.read);

  final Future<bool> Function() read;
  User? user = _user;
  int checks = 0;

  @override
  User? get currentUser => user;

  @override
  Future<bool> hasActiveMembership() {
    checks++;
    return read();
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

Future<void> _pump(
  WidgetTester tester,
  _Account account,
  void Function(bool?) onResult, {
  Duration? timeout,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onResult(
              await requireMotionPaidAccess(
                context,
                account: account,
                accountPageBuilder: (_) =>
                    const Scaffold(body: Text('ACCOUNT')),
                membershipPageBuilder: (_) =>
                    const Scaffold(body: Text('PURCHASE')),
                membershipTimeout: timeout ?? motionMembershipCheckTimeout,
              ),
            ),
            child: const Text('START'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('START'));
  await tester.pump();
}

void main() {
  testWidgets('a membership read that never answers fails closed', (
    tester,
  ) async {
    final never = Completer<bool>();
    final account = _Account(() => never.future);
    bool? allowed;
    await _pump(tester, account, (v) => allowed = v);

    expect(allowed, isNull, reason: 'still waiting before the deadline');
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(allowed, isFalse);
    expect(account.checks, 1, reason: 'no purchase route, no second read');
    expect(find.text('PURCHASE'), findsNothing);
    expect(find.text('ACCOUNT'), findsNothing);
  });

  testWidgets('a late answer after the deadline cannot grant or throw', (
    tester,
  ) async {
    final late = Completer<bool>();
    final account = _Account(() => late.future);
    bool? allowed;
    await _pump(tester, account, (v) => allowed = v);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(allowed, isFalse);

    late.complete(true);
    await tester.pump();
    expect(allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late error after the deadline is not an unhandled error', (
    tester,
  ) async {
    final late = Completer<bool>();
    final account = _Account(() => late.future);
    bool? allowed;
    await _pump(tester, account, (v) => allowed = v);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    late.completeError(StateError('late network failure'));
    await tester.pump();
    expect(allowed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a prompt answer keeps the old behaviour', (tester) async {
    final account = _Account(() async => true);
    bool? allowed;
    await _pump(tester, account, (v) => allowed = v);
    await tester.pumpAndSettle();

    expect(allowed, isTrue);
    expect(account.checks, 1);
  });

  testWidgets('the timeout is configurable and fails closed with a notice', (
    tester,
  ) async {
    final account = _Account(() => Completer<bool>().future);
    bool? allowed;
    await _pump(
      tester,
      account,
      (v) => allowed = v,
      timeout: const Duration(seconds: 2),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(allowed, isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(allowed, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('PURCHASE'), findsNothing);
    expect(motionMembershipCheckTimeout, const Duration(seconds: 15));
  });

  testWidgets(
    'camera gate passes its custom timeout through and fails closed',
    (tester) async {
      final account = _Account(() => Completer<bool>().future);
      bool? allowed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    allowed = await requireMotionCameraAccess(
                      context,
                      account: account,
                      accountPageBuilder: (_) =>
                          const Scaffold(body: Text('ACCOUNT')),
                      membershipPageBuilder: (_) =>
                          const Scaffold(body: Text('PURCHASE')),
                      cameraCoachingAvailable: true,
                      membershipTimeout: const Duration(seconds: 2),
                    ),
                child: const Text('START'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(allowed, isFalse, reason: 'closed at 2 s, not the 15 s default');
      expect(account.checks, 1);
      expect(find.text('PURCHASE'), findsNothing);
    },
  );
}
