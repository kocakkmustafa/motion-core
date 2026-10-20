import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_account/motion_account.dart';
import 'package:motion_entitlements/motion_entitlements.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('every key has eight nonempty templates with placeholder parity', () {
    final placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9]*)\}');
    Map<String, int> names(String text) {
      final counts = <String, int>{};
      for (final match in placeholder.allMatches(text)) {
        final name = match.group(1)!;
        counts[name] = (counts[name] ?? 0) + 1;
      }
      return counts;
    }

    expect(MotionAccountLocalizations.supportedLocales, hasLength(8));
    for (final key in MotionAccountString.values) {
      final english = MotionAccountLocalizations.templateFor(
        const Locale('en'),
        key,
      );
      for (final locale in MotionAccountLocalizations.supportedLocales) {
        final template = MotionAccountLocalizations.templateFor(locale, key);
        expect(template.trim(), isNotEmpty, reason: '$locale/$key');
        expect(names(template), names(english), reason: '$locale/$key');
        if (key != MotionAccountString.appMembership) {
          expect(MotionAccountLocalizations(locale).text(key), template);
        }
      }
    }
  });

  test('resolver keeps supported variants and English fallback', () {
    expect(
      MotionAccountLocalizations.localeFor(const Locale('es', 'MX')),
      const Locale('es', '419'),
    );
    expect(
      MotionAccountLocalizations.localeFor(const Locale('pt', 'PT')),
      const Locale('pt', 'BR'),
    );
    expect(MotionAccountLocalizations.localeFor(null), const Locale('en'));
    expect(
      MotionAccountLocalizations.localeFor(const Locale('zh')),
      const Locale('en'),
    );
    expect(
      MotionAccountLocalizations.localeResolutionCallback(
        const Locale('ar'),
        const [Locale('tr'), Locale('en')],
      ),
      const Locale('en'),
    );
    for (final locale in MotionAccountLocalizations.supportedLocales) {
      expect(
        MotionAccountLocalizations.localeResolutionCallback(
          locale,
          MotionAccountLocalizations.supportedLocales,
        ),
        locale,
      );
      expect(
        MotionAccountLocalizations(locale).textDirection,
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
    }
  });

  test('typed placeholder values are inserted once', () {
    for (final locale in MotionAccountLocalizations.supportedLocales) {
      final strings = MotionAccountLocalizations(locale);
      expect(
        strings.membershipForApp('Demo{appName}'),
        contains('Demo{appName}'),
      );
      expect(
        () => strings.text(MotionAccountString.appMembership),
        throwsArgumentError,
      );
    }
    expect(
      MotionAccountLocalizations(
        const Locale('xx'),
      ).text(MotionAccountString.accountTitle),
      'Motion account',
    );
  });

  for (final locale in MotionAccountLocalizations.supportedLocales) {
    testWidgets('shared account surfaces use $locale and its direction', (
      tester,
    ) async {
      final strings = MotionAccountLocalizations(locale);
      final guest = _CatalogAccount(signedIn: false);
      final member = _CatalogAccount(signedIn: true);
      final store = _CatalogStore();
      final runtime = MotionAccountRuntime.forTesting(
        client: const _CatalogSupabase(),
        app: MotionApp.ostinato,
        onDeletedAccount: (_) async {},
      );
      runtime.dispose();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await store.dispose();
      });

      await tester.pumpWidget(_app(locale, MotionAccountPage(account: guest)));
      expect(
        find.text(strings.text(MotionAccountString.accountTitle)),
        findsOneWidget,
      );
      expect(find.text(strings.text(MotionAccountString.signIn)), findsWidgets);
      await tester.tap(find.text(strings.text(MotionAccountString.newAccount)));
      await tester.pump();
      expect(
        find.text(strings.text(MotionAccountString.createAccount)),
        findsWidgets,
      );

      await tester.pumpWidget(
        _app(
          locale,
          MotionAccountPage(account: guest, initialPasswordRecovery: true),
        ),
      );
      await tester.tap(
        find.text(strings.text(MotionAccountString.savePassword)),
      );
      await tester.pump();
      expect(
        find.text(strings.text(MotionAccountString.invalidNewPassword)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _app(
          locale,
          MotionAccountPage(account: member, clearLocalData: (_) async {}),
        ),
      );
      await tester.pump();
      final delete = find.text(
        strings.text(MotionAccountString.deleteMotionAccount),
      );
      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(
        find.text(strings.text(MotionAccountString.deleteExplanation)),
        findsOneWidget,
      );
      expect(
        Directionality.of(tester.element(find.byType(AlertDialog))),
        strings.textDirection,
      );
      await tester.tap(find.text(strings.text(MotionAccountString.cancel)));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(
          locale,
          MotionMembershipPage(
            account: member,
            purchaseAdapter: store,
            serverAdapter: _CatalogServer(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(strings.text(MotionAccountString.membershipTitle)),
        findsOneWidget,
      );
      expect(find.text(strings.membershipForApp('Ostinato')), findsOneWidget);
      // Store text is opaque: no currency parsing or translation.
      expect(find.text('STORE_PRICE_9.90'), findsOneWidget);
      final disclosure = find.text(
        strings.text(MotionAccountString.subscriptionDisclosure),
      );
      await tester.scrollUntilVisible(disclosure, 200);
      expect(disclosure, findsOneWidget);

      await tester.pumpWidget(
        _app(
          locale,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => requireMotionPaidAccess(
                  context,
                  account: guest,
                  accountPageBuilder: (_) => const SizedBox.shrink(),
                  paidFeaturesAvailable: false,
                ),
                child: const Text('CLOSED_ACCESS'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('CLOSED_ACCESS'));
      await tester.pump();
      expect(
        find.text(strings.text(MotionAccountString.futureSession)),
        findsOneWidget,
      );

      // A retired runtime gives a deterministic blocked gate without HTTP IO.
      // Its nested MaterialApp must inherit the selected parent locale.
      await tester.pumpWidget(
        _app(
          locale,
          MotionIdentityGate(
            runtime: runtime,
            child: const Text('PRIVATE_CONTENT'),
          ),
        ),
      );
      await tester.pump();
      final blocked = find.text(
        strings.text(MotionAccountString.accountVerificationFailed),
      );
      expect(blocked, findsOneWidget);
      expect(Directionality.of(tester.element(blocked)), strings.textDirection);
      expect(find.text('PRIVATE_CONTENT'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an open validation error follows the selected locale', (
    tester,
  ) async {
    final locale = ValueNotifier<Locale>(const Locale('en'));
    final account = _CatalogAccount(signedIn: false);
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, _) =>
            _app(value, MotionAccountPage(account: account)),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email and password.'), findsOneWidget);
    locale.value = const Locale('ar');
    await tester.pumpAndSettle();
    final arabic = MotionAccountLocalizations(const Locale('ar'));
    final error = find.text(
      arabic.text(MotionAccountString.invalidCredentials),
    );
    expect(error, findsOneWidget);
    expect(find.text('Enter your email and password.'), findsNothing);
    expect(Directionality.of(tester.element(error)), TextDirection.rtl);
  });

  testWidgets('an open profile success follows the selected locale', (
    tester,
  ) async {
    final locale = ValueNotifier<Locale>(const Locale('en'));
    final account = _CatalogAccount(signedIn: true);
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, _) =>
            _app(value, MotionAccountPage(account: account)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    expect(find.text('Profile saved.'), findsOneWidget);
    locale.value = const Locale('ja');
    await tester.pumpAndSettle();
    expect(
      find.text(
        MotionAccountLocalizations(
          const Locale('ja'),
        ).text(MotionAccountString.profileSaved),
      ),
      findsOneWidget,
    );
    expect(find.text('Profile saved.'), findsNothing);
  });

  testWidgets('pending membership copy changes locale but not store price', (
    tester,
  ) async {
    final locale = ValueNotifier<Locale>(const Locale('en'));
    final account = _CatalogAccount(signedIn: true);
    final store = _CatalogStore();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await store.dispose();
      locale.dispose();
    });
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, _) => _app(
          value,
          MotionMembershipPage(
            account: account,
            purchaseAdapter: store,
            serverAdapter: _CatalogServer(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    store.pending();
    await tester.pump();
    expect(find.text('Waiting for the store…'), findsOneWidget);
    locale.value = const Locale('fr');
    await tester.pumpAndSettle();
    expect(
      find.text(
        MotionAccountLocalizations(
          const Locale('fr'),
        ).text(MotionAccountString.waitingStore),
      ),
      findsOneWidget,
    );
    expect(find.text('Waiting for the store…'), findsNothing);
    expect(find.text('STORE_PRICE_9.90'), findsOneWidget);
  });

  testWidgets('retained deletion dialog follows locale after page removal', (
    tester,
  ) async {
    final locale = ValueNotifier<Locale>(const Locale('en'));
    final visible = ValueNotifier<bool>(true);
    final account = _CatalogAccount(signedIn: true);
    var cleanupCalls = 0;
    addTearDown(() {
      locale.dispose();
      visible.dispose();
    });
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, _) => _app(
          value,
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, _) => show
                ? MotionAccountPage(
                    account: account,
                    clearLocalData: (_) async {
                      cleanupCalls++;
                    },
                  )
                : const Scaffold(body: Text('REPLACEMENT_PAGE')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Delete Motion account'));
    await tester.tap(find.text('Delete Motion account'));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump();
    locale.value = const Locale('ar');
    await tester.pumpAndSettle();
    final arabic = MotionAccountLocalizations(const Locale('ar'));
    final explanation = find.text(
      arabic.text(MotionAccountString.deleteExplanation),
    );
    expect(explanation, findsOneWidget);
    expect(Directionality.of(tester.element(explanation)), TextDirection.rtl);
    await tester.tap(
      find.text(arabic.text(MotionAccountString.confirmDeleteAccount)),
    );
    await tester.pumpAndSettle();
    expect(account.deleteCalls, 0);
    expect(cleanupCalls, 0);
    expect(find.text('REPLACEMENT_PAGE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('identity blocker inherits a changed parent appearance', (tester) async {
    final runtime = MotionAccountRuntime.forTesting(
      client: const _CatalogSupabase(),
      app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    )..dispose();
    final brightness = ValueNotifier<Brightness>(Brightness.dark);
    addTearDown(brightness.dispose);
    await tester.pumpWidget(ValueListenableBuilder<Brightness>(
      valueListenable: brightness,
      builder: (_, value, _) => Theme(
        data: ThemeData(brightness: value),
        child: MotionIdentityGate(runtime: runtime, child: const SizedBox.shrink()),
      ),
    ));
    await tester.pumpAndSettle();
    final scaffold = find.byType(Scaffold);
    expect(scaffold, findsOneWidget);
    expect(Theme.of(tester.element(scaffold)).brightness, Brightness.dark);
    brightness.value = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(scaffold)).brightness, Brightness.light);
    expect(runtime.isDisposed, isTrue);
  });

  testWidgets('identity blocker accepts explicit light dark and system themes', (tester) async {
    final runtime = MotionAccountRuntime.forTesting(
      client: const _CatalogSupabase(),
      app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    )..dispose();
    final mode = ValueNotifier<ThemeMode>(ThemeMode.dark);
    addTearDown(mode.dispose);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, value, _) => MotionIdentityGate(
        runtime: runtime,
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: value,
        child: const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    mode.value = ThemeMode.system;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness, Brightness.dark);
    expect(runtime.isDisposed, isTrue);
  });

  testWidgets('identity blocker resolves ordered preferences and explicit host locale', (tester) async {
    final runtime = MotionAccountRuntime.forTesting(
      client: const _CatalogSupabase(), app: MotionApp.ostinato,
      onDeletedAccount: (_) async {},
    )..dispose();
    await tester.pumpWidget(MotionIdentityGate(
      runtime: runtime,
      preferredLocales: const [Locale('xx'), Locale('fr')],
      child: const SizedBox.shrink(),
    ));
    await tester.pumpAndSettle();
    expect(find.text(MotionAccountLocalizations(const Locale('fr')).text(
      MotionAccountString.accountVerificationFailed)), findsOneWidget);
    await tester.pumpWidget(Localizations(
      locale: const Locale('ar'), delegates: MotionAccountLocalizations.delegates,
      child: MotionIdentityGate(runtime: runtime,
        preferredLocales: const [Locale('fr')], locale: const Locale('ja'),
        child: const SizedBox.shrink()),
    ));
    await tester.pumpAndSettle();
    final japanese = find.text(MotionAccountLocalizations(const Locale('ja')).text(
      MotionAccountString.accountVerificationFailed));
    expect(japanese, findsOneWidget);
    expect(Directionality.of(tester.element(japanese)), TextDirection.ltr);
    await tester.pumpWidget(Localizations(
      locale: const Locale('ar'), delegates: MotionAccountLocalizations.delegates,
      child: MotionIdentityGate(runtime: runtime,
        preferredLocales: const [Locale('fr')], child: const SizedBox.shrink()),
    ));
    await tester.pumpAndSettle();
    final arabic = find.text(MotionAccountLocalizations(const Locale('ar')).text(
      MotionAccountString.accountVerificationFailed));
    expect(arabic, findsOneWidget);
    expect(Directionality.of(tester.element(arabic)), TextDirection.rtl);
    expect(runtime.isDisposed, isTrue);
  });

}

Widget _app(Locale locale, Widget home) => MaterialApp(
  locale: locale,
  supportedLocales: MotionAccountLocalizations.supportedLocales,
  localizationsDelegates: MotionAccountLocalizations.delegates,
  localeResolutionCallback: MotionAccountLocalizations.localeResolutionCallback,
  home: home,
);

class _CatalogAccount implements MotionAccountClient {
  _CatalogAccount({required this.signedIn});
  final bool signedIn;
  int deleteCalls = 0;

  @override
  SupabaseClient get supabase => const _CatalogSupabase();
  @override
  MotionApp get app => MotionApp.ostinato;
  @override
  String get emailRedirectTo => 'com.yulalab.ostinato://auth/callback';
  @override
  User? get currentUser => signedIn
      ? const User(
          id: 'catalog-user',
          appMetadata: {},
          userMetadata: null,
          aud: 'authenticated',
          createdAt: '2026-10-20T00:00:00Z',
        )
      : null;
  @override
  Stream<AuthState> get authChanges => const Stream.empty();
  @override
  Future<Map<String, dynamic>?> loadProfile() async => {'display_name': 'Name'};
  @override
  Future<void> saveDisplayName(String name) async {}
  @override
  Future<MotionMembershipStatus> membershipStatus() async =>
      const MotionMembershipStatus(active: false, anyActive: false);
  @override
  Future<void> deleteCommonAccount({
    Future<void> Function(String userId)? afterRemoteDelete,
  }) async {
    deleteCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogSupabase implements SupabaseClient {
  const _CatalogSupabase();
  @override
  GoTrueClient get auth => const _CatalogAuth();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogAuth implements GoTrueClient {
  const _CatalogAuth();
  @override
  Session? get currentSession => null;
  @override
  User? get currentUser => null;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogStore implements PurchaseAdapter {
  final _updates = StreamController<StorePurchaseUpdate>.broadcast(sync: true);
  @override
  Stream<StorePurchaseUpdate> get updates => _updates.stream;
  @override
  Future<List<StoreProductRef>> fetchProducts(List<String> ids) async => const [
    StoreProductRef(
      productId: 'com.yulalab.ostinato.individual.monthly',
      platform: StorePlatform.ios,
      planId: 'monthly',
      localizedPrice: 'STORE_PRICE_9.90',
    ),
  ];
  @override
  Future<void> startPurchase(StoreProductRef offer) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<void> complete(StorePurchaseUpdate update) async {}

  void pending() => _updates.add(
    const StorePurchaseUpdate(
      kind: StorePurchaseKind.pending,
      localHandle: 'catalog-pending',
    ),
  );

  Future<void> dispose() => _updates.close();
}

class _CatalogServer implements ServerAdapter {
  @override
  Future<EntitlementStatus?> verify(StorePurchaseEvidence evidence) async =>
      null;
}
