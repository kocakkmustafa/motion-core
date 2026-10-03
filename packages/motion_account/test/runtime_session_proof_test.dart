// Scratch successor source proposal only; compiler and all tests remain UNRUN.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motion_account/motion_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _alice = '00000000-0000-4000-8000-000000000001';
const _bob = '00000000-0000-4000-8000-000000000002';
const _closeBudget = Duration(seconds: 2);

String _session(String id, {String token = 'alice-session'}) => jsonEncode({
  'access_token': token,
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'expires_at': 4102444800,
  'expires_in': 3600,
  'user': {
    'id': id,
    'aud': 'authenticated',
    'created_at': '2026-09-24T00:00:00Z',
    'app_metadata': <String, dynamic>{},
  },
});

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _user(String id) => _json({
  'id': id,
  'aud': 'authenticated',
  'created_at': '2026-09-24T00:00:00Z',
  'app_metadata': <String, dynamic>{},
});

http.Response _denied({String code = 'invalid_token'}) => _json({
  'error_code': code,
  'message': 'synthetic denial',
}, status: 403);

class _FixtureRetired implements Exception {
  const _FixtureRetired();
}

class _ObservedWork {
  _ObservedWork(Future<dynamic> work) {
    settled = work.then<void>((_) {
      done = true;
    }, onError: (Object error, StackTrace stack) {
      failure = error;
      done = true;
    });
  }
  late final Future<void> settled;
  bool done = false;
  Object? failure;
}

class _OwnedActions {
  _OwnedActions(this.zone);
  final Zone zone;
  bool retired = false;
  final work = <_ObservedWork>[];

  Future<T> start<T>(Future<T> Function() action, {bool admittedCleanup = false}) {
    if (retired && !admittedCleanup) throw const _FixtureRetired();
    final future = zone.run(action);
    zone.run(() => work.add(_ObservedWork(future)));
    return future;
  }

  Iterable<Future<void>> get settlements => work.map((w) => w.settled);
  bool get done => work.every((w) => w.done);
}

class _OwnedHold {
  final entered = Completer<void>();
  final _release = Completer<void>();
  final work = <_ObservedWork>[];
  bool get released => _release.isCompleted;

  Future<void> wait() {
    final future = _wait();
    work.add(_ObservedWork(future));
    return future;
  }

  Future<void> _wait() async {
    if (!entered.isCompleted) entered.complete();
    await _release.future;
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  void drain() {
    if (!entered.isCompleted) entered.complete();
    release();
  }

  Iterable<Future<void>> get settlements => work.map((w) => w.settled);
}

class _HeldUser {
  _HeldUser(this.request);
  final http.Request request;
  final response = Completer<http.Response>();

  void succeed(String id) {
    if (!response.isCompleted) response.complete(_user(id));
  }
  void deny() {
    if (!response.isCompleted) response.complete(_denied());
  }
  void missing() {
    if (!response.isCompleted) response.complete(_denied(code: 'user_not_found'));
  }
  void fail() {
    if (!response.isCompleted) {
      response.completeError(const SocketException('synthetic offline'));
    }
  }
}

class _UserRequests {
  _UserRequests(this.userId, {this.initialResponse});
  String userId;
  final http.Response? initialResponse;
  var hold = false;
  var closing = false;
  var userRequests = 0;
  var logoutRequests = 0;
  var refreshRequests = 0;
  var passwordRequests = 0;
  var recoveryRequests = 0;
  final _pending = <_HeldUser>[];
  final allHeld = <_HeldUser>[];
  final work = <_ObservedWork>[];
  Completer<void>? _arrival;

  Future<http.Response> call(http.Request request) {
    final future = _call(request);
    work.add(_ObservedWork(future));
    return future;
  }

  Future<http.Response> _call(http.Request request) async {
    if (request.url.path.endsWith('/user')) {
      userRequests++;
      if (closing) return _user(userId);
      if (!hold) return initialResponse ?? _user(userId);
      final held = _HeldUser(request);
      allHeld.add(held); // Never removed when take() transfers a test handle.
      _pending.add(held);
      _arrival?.complete();
      _arrival = null;
      return held.response.future;
    }
    if (request.url.path.endsWith('/verify')) {
      recoveryRequests++;
      return _json(jsonDecode(_session(userId, token: 'recovery-$recoveryRequests')));
    }
    if (request.url.path.endsWith('/logout')) {
      logoutRequests++;
      return _json({});
    }
    if (request.url.path.endsWith('/token') &&
        request.url.queryParameters['grant_type'] == 'refresh_token') {
      refreshRequests++;
      return _json(jsonDecode(_session(userId, token: 'refreshed-session-$refreshRequests')));
    }
    if (request.url.path.endsWith('/token') &&
        request.url.queryParameters['grant_type'] == 'password') {
      passwordRequests++;
      return _json(jsonDecode(_session(userId, token: 'password-$passwordRequests')));
    }
    throw StateError('Unexpected synthetic request: ${request.url.path}');
  }

  Future<_HeldUser> take() async {
    while (_pending.isEmpty) {
      if (closing) throw const _FixtureRetired();
      final arrival = _arrival ??= Completer<void>();
      await arrival.future;
    }
    return _pending.removeAt(0);
  }

  void drain() {
    closing = true;
    hold = false;
    for (final held in allHeld) {
      held.succeed(userId);
    }
    _pending.clear();
    _arrival?.complete();
    _arrival = null;
  }

  bool get done => allHeld.every((h) => h.response.isCompleted) &&
      work.every((w) => w.done);
  Iterable<Future<void>> get settlements => work.map((w) => w.settled);
}

// This public SDK seam owns its outstanding removal calls and release gate.
class _HeldRemoveStorage extends GotrueAsyncStorage {
  var hold = false;
  var failRemoval = false;
  final gate = _OwnedHold();
  final _items = <String, String>{};
  final work = <_ObservedWork>[];
  Future<void> get entered => gate.entered.future;
  bool get released => gate.released;

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) {
    final future = _remove(key);
    work.add(_ObservedWork(future));
    return future;
  }

  Future<void> _remove(String key) async {
    if (hold) await gate.wait();
    if (failRemoval) throw StateError('synthetic storage removal failure');
    _items.remove(key);
  }

  void release() => gate.release();
  void drain() {
    hold = false;
    gate.drain();
  }
  Iterable<Future<void>> get settlements sync* {
    yield* work.map((w) => w.settled);
    yield* gate.settlements;
  }
}

class _ProofWait {
  _ProofWait(this.runtime, this.condition, {this.failUnavailable = false}) {
    changes = Listenable.merge([runtime.phase, runtime.identityVerification]);
    changes.addListener(check);
    check();
    future = done.future
        .timeout(const Duration(seconds: 3))
        .whenComplete(detach);
  }
  final MotionAccountRuntime runtime;
  final bool Function() condition;
  final bool failUnavailable;
  final done = Completer<void>();
  late final Listenable changes;
  late final Future<void> future;

  void check() {
    if (done.isCompleted) return;
    if (condition()) {
      done.complete();
    } else if (failUnavailable &&
        runtime.phase.value == MotionIdentityPhase.unavailable) {
      done.completeError(StateError('Synthetic bootstrap identity failed'));
    }
  }

  void detach() => changes.removeListener(check);
  void cancel() {
    detach();
    if (!done.isCompleted) done.completeError(const _FixtureRetired());
  }
}

class _OwnedSubscription {
  _OwnedSubscription(this.subscription);
  final StreamSubscription<AuthState> subscription;
  Future<void>? _cancel;
  Future<void> cancel() => _cancel ??= subscription.cancel();
}

Future<T> _real<T>(WidgetTester tester, Future<T> Function() operation) async {
  Object? failure;
  StackTrace? failureStack;
  late T value;
  await tester.runAsync(() async {
    try {
      value = await operation();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
  });
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return value;
}

class _Harness {
  _Harness._(
    String userId, {
    this.tester,
    this.storage,
    this.cleanupHold,
    http.Response? initialResponse,
  }) : actions = _OwnedActions(Zone.current),
       requests = _UserRequests(userId, initialResponse: initialResponse);

  final WidgetTester? tester;
  final _HeldRemoveStorage? storage;
  final _OwnedHold? cleanupHold;
  final _OwnedActions actions;
  final _UserRequests requests;
  final clearedIds = <String>[];
  final _waiters = <_ProofWait>[];
  final _subscriptions = <_OwnedSubscription>[];
  final _runtimes = <MotionAccountRuntime>[];
  final _extraHolds = <_OwnedHold>[];
  final _uiCleanups = <VoidCallback>[];
  final cleanupErrors = <Object>[];
  SupabaseClient? _client;
  MockClient? _httpClient;
  MotionAccountRuntime? _runtime;
  Future<void>? _closeFuture;
  Future<void>? _closeDriver;
  bool _resourcesClosed = false;
  var closeRuns = 0;
  var clientDisposeRuns = 0;
  var httpCloseRuns = 0;

  SupabaseClient get client => _client!;
  MotionAccountRuntime get runtime => _runtime!;
  bool get resourcesClosed =>
      _resourcesClosed && _uiCleanups.isEmpty && cleanupErrors.isEmpty;

  static Future<_Harness> boot({
    String userId = _alice,
    Duration timeout = const Duration(seconds: 10),
    WidgetTester? tester,
    _HeldRemoveStorage? storage,
    _OwnedHold? cleanupHold,
    Future<Iterable<String>> Function()? localAccountIds,
    Future<bool> Function(String)? receipt,
    http.Response? initialResponse,
    void Function(_Harness)? onOwned,
    bool signedIn = true,
    bool verifyOnBoot = true,
    bool sessionBeforeRuntime = false,
    bool holdInitialVerification = false,
    void Function(String)? onCleanupAdmission,
  }) async {
    final h = _Harness._(
      userId,
      tester: tester,
      storage: storage,
      cleanupHold: cleanupHold,
      initialResponse: initialResponse,
    );
    // Registered before constructing resources or awaiting bootstrap work.
    addTearDown(h.closeFromTest);
    try {
      h.requests.hold = holdInitialVerification;
      h._httpClient = MockClient(h.requests.call);
      h._client = SupabaseClient(
        'https://motion.example.invalid',
        'public-test-key',
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: storage,
        ),
        httpClient: h._httpClient,
      );
      Future<void> installSession() => h.actions.start(() async {
        await h.client.auth.setInitialSession(
          _session(userId, token: userId == _alice ? 'alice-session' : 'bob-session'),
        );
      });
      if (signedIn && sessionBeforeRuntime) await installSession();
      h._runtime = MotionAccountRuntime.forTesting(
        client: h.client,
        app: MotionApp.ostinato,
        identityVerificationTimeout: timeout,
        localAccountIds: localAccountIds ?? () async => const <String>[],
        wasAccountDeleted: receipt ?? (_) async => false,
        onDeletedAccount: (id) => h.actions.start(() async {
          onCleanupAdmission?.call(id);
          h.clearedIds.add(id);
          await cleanupHold?.wait();
        }, admittedCleanup: true),
      );
      h._runtimes.add(h.runtime);
      onOwned?.call(h);
      await h.scan();
      if (signedIn && !sessionBeforeRuntime) await installSession();
      if (signedIn && verifyOnBoot) {
        await h.until(() => h.runtime.isCurrentSessionVerified, failUnavailable: true);
      }
      await Future<void>.delayed(Duration.zero);
      return h;
    } catch (error, stack) {
      await h._closeWithoutMaskingPrimary();
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> expectFailure(Object actual, Matcher matcher) =>
      actions.start(() => expectLater(actual, matcher));
  Future<void> refresh() => actions.start(runtime.refreshIdentity);
  Future<void> guest() => actions.start(runtime.continueAsGuest);
  Future<void> scan() => actions.start(runtime.reconcileDeletedLocalAccounts);
  Future<void> recover(String session) => actions.start(() async {
    await client.auth.recoverSession(session);
  });
  Future<void> signIn({String userId = _alice}) => actions.start(() async {
    requests.userId = userId;
    await client.auth.signInWithPassword(
      email: 'synthetic@example.invalid',
      password: 'synthetic-not-a-real-password',
    );
  });
  MotionAccountRuntime additionalRuntime() => actions.zone.run(() {
    final next = MotionAccountRuntime.forTesting(
      client: client,
      app: MotionApp.ostinato,
      onDeletedAccount: (id) => actions.start(() async {
        clearedIds.add(id);
        await cleanupHold?.wait();
      }, admittedCleanup: true),
    );
    _runtimes.add(next);
    return next;
  });
  Future<void> refreshFor(MotionAccountRuntime owner) =>
      actions.start(owner.refreshIdentity);
  Future<void> untilFor(MotionAccountRuntime owner, bool Function() condition) =>
      actions.start(() {
        final waiter = _ProofWait(owner, condition);
        _waiters.add(waiter);
        return waiter.future;
      });
  Future<void> refreshCredentials() => actions.start(() async {
    await client.auth.refreshSession();
  });
  Future<void> startRecovery() => actions.start(() async {
    await client.auth.verifyOTP(
      type: OtpType.recovery,
      tokenHash: 'synthetic-recovery-hash',
    );
  });
  Future<void> signOut() => actions.start(
    () => client.auth.signOut(scope: SignOutScope.local),
  );
  Future<AuthState> replay() => actions.start(
    () => client.auth.onAuthStateChange.first,
  );
  Future<_HeldUser> reply() => actions.start(
    () => requests.take().timeout(const Duration(seconds: 3)),
  );
  _OwnedHold ownHold() => actions.zone.run(() {
    final hold = _OwnedHold();
    _extraHolds.add(hold);
    return hold;
  });
  Future<void> entered(_OwnedHold hold) => actions.start(() => hold.entered.future);
  Future<void> storageEntered() => actions.start(() => storage!.entered);

  Future<void> until(bool Function() condition, {bool failUnavailable = false}) =>
      actions.start(() {
        final waiter = _ProofWait(runtime, condition, failUnavailable: failUnavailable);
        _waiters.add(waiter);
        return waiter.future;
      });

  _OwnedSubscription listen(void Function(AuthState) listener) {
    final owned = actions.zone.run(
      () => _OwnedSubscription(client.auth.onAuthStateChange.listen(listener)),
    );
    _subscriptions.add(owned);
    return owned;
  }
  Future<void> cancel(_OwnedSubscription subscription) =>
      actions.start(subscription.cancel);

  // These synchronous handles belong to the widget/fake UI zone, never a real
  // SDK callback. Removal before invocation keeps their cleanup idempotent.
  void ownUiCleanup(VoidCallback cleanup) => _uiCleanups.add(cleanup);

  Future<void> closeFromTest() async {
    Future<void> operation() async {
      if (_closeFuture == null) {
        await close();
      } else {
        // An earlier boot/body close already exposed its primary result.
        await _closeWithoutMaskingPrimary();
      }
    }
    final widgetTester = tester;
    if (widgetTester == null) {
      await operation();
    } else {
      Object? uiFailure;
      StackTrace? uiStack;
      try {
        // Do this even when the binding has a pending primary test exception.
        await widgetTester.pumpWidget(const SizedBox.shrink());
        await widgetTester.pump();
      } catch (error, stack) {
        uiFailure = error;
        uiStack = stack;
        cleanupErrors.add(error);
      }
      final hadUiHandles = _uiCleanups.isNotEmpty;
      while (_uiCleanups.isNotEmpty) {
        final cleanup = _uiCleanups.removeAt(0);
        try {
          cleanup(); // After owned widget unmount, before real-zone SDK drain.
        } catch (error, stack) {
          uiFailure ??= error;
          uiStack ??= stack;
          cleanupErrors.add(error);
        }
      }
      if (hadUiHandles) {
        try {
          await widgetTester.pump(); // Flush semantics-disabled UI work here.
        } catch (error, stack) {
          uiFailure ??= error;
          uiStack ??= stack;
          cleanupErrors.add(error);
        }
      }
      try {
        // Holds and SDK settlement use their creation's real runAsync zone.
        await _real(widgetTester, operation);
      } catch (_) {
        if (uiFailure == null) rethrow;
        // The owned SDK drain was attempted; preserve the first UI close error.
      }
      if (uiFailure != null) Error.throwWithStackTrace(uiFailure, uiStack!);
    }
  }

  Future<void> close() => actions.zone.run(_startClose);

  Future<void> _startClose() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final done = Completer<void>();
    // Latch before disposal: a synchronous proof listener may request close.
    _closeFuture = done.future.whenComplete(() => _closeDriver!);
    _closeDriver = _closeBody().then<void>(
      (_) => done.complete(),
      onError: (Object error, StackTrace stack) => done.completeError(error, stack),
    );
    return _closeFuture!;
  }

  Future<void> _closeBody() async {
    closeRuns++;
    final clock = Stopwatch()..start();
    Future<void> bounded(Future<void> work) {
      final remaining = _closeBudget - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Fixture close budget exhausted', _closeBudget);
      }
      return work.timeout(remaining);
    }

    // Each already-owned runtime gets cleanup even if an earlier one fails.
    for (final runtime in _runtimes) {
      try {
        runtime.dispose();
      } catch (error) {
        cleanupErrors.add(error);
      }
    }
    actions.retired = true;
    requests.drain();
    storage?.drain();
    cleanupHold?.drain();
    for (final hold in _extraHolds) { hold.drain(); }
    for (final waiter in _waiters) {
      waiter.cancel();
    }
    final cancellation = <_ObservedWork>[];
    for (final subscription in _subscriptions) {
      cancellation.add(_ObservedWork(subscription.cancel()));
    }

    try {
      while (true) {
        final ownedCount = actions.work.length + requests.work.length;
        await bounded(Future.wait<void>([
          ...actions.settlements,
          ...requests.settlements,
          ...?storage?.settlements,
          ...?cleanupHold?.settlements,
          ..._extraHolds.expand((hold) => hold.settlements),
          ...cancellation.map((w) => w.settled),
        ]));
        await bounded(Future<void>.delayed(Duration.zero));
        if (actions.done && requests.done &&
            ownedCount == actions.work.length + requests.work.length) break;
      }
      for (final cancelled in cancellation) {
        if (cancelled.failure != null) cleanupErrors.add(cancelled.failure!);
      }
    } catch (error) {
      cleanupErrors.add(error);
    } finally {
      final currentClient = _client;
      if (currentClient != null) {
        clientDisposeRuns++;
        try {
          final disposal = _ObservedWork(currentClient.dispose());
          await bounded(disposal.settled);
          if (disposal.failure != null) cleanupErrors.add(disposal.failure!);
        } catch (error) {
          cleanupErrors.add(error);
        }
      }
      final currentHttp = _httpClient;
      if (currentHttp != null) {
        httpCloseRuns++;
        try {
          currentHttp.close(); // Supabase does not own a supplied HTTP client.
        } catch (error) {
          cleanupErrors.add(error);
        }
      }
      _resourcesClosed = cleanupErrors.isEmpty;
    }
    if (cleanupErrors.isNotEmpty) {
      throw StateError('Fixture cleanup failed: ${cleanupErrors.length} error(s)');
    }
  }

  Future<void> _closeWithoutMaskingPrimary() async {
    try {
      await close();
    } catch (_) {
      // close() records resource failures; the original assertion/boot error wins.
    }
  }

  Future<void> closePreservingPrimary(Object error, StackTrace stack) async {
    await _closeWithoutMaskingPrimary();
    Error.throwWithStackTrace(error, stack);
  }
}

bool _legacyAdmits(MotionAccountRuntime runtime, Session? captured) =>
    captured != null &&
    identical(runtime.account.supabase.auth.currentSession, captured) &&
    runtime.userId.value == captured.user.id &&
    runtime.phase.value == MotionIdentityPhase.verified;


// Synchronous lifecycle/resource/route spies. Their handles are scoped to the
// existing host ticket. They perform no camera, filesystem or provider work.
class _ScopeLedger {
  Object liveTicket = Object();
  int init = 0;
  int builds = 0;
  int updates = 0;
  int dispose = 0;
  int opens = 0;
  int closes = 0;
  int acquisitions = 0;
  int publications = 0;
  final states = <_ScopeSpyState>[];
  final routes = <_RouteSpyState>[];
  final acceptedAtInit = <bool>[];
  final configurations = <String>[];
  _ScopeSpyState get latest => states.last;
  void retireTicket() => liveTicket = Object();
}

class _ScopeSpy extends StatefulWidget {
  const _ScopeSpy({
    super.key,
    required this.runtime,
    required this.ledger,
    required this.ticket,
    required this.configuration,
  });
  final MotionAccountRuntime runtime;
  final _ScopeLedger ledger;
  final Object ticket;
  final String configuration;
  @override
  State<_ScopeSpy> createState() => _ScopeSpyState();
}

class _ScopeSpyState extends State<_ScopeSpy> {
  final navigator = GlobalKey<NavigatorState>();
  final route = GlobalKey<_RouteSpyState>();
  final resource = Object();
  late final Object openedTicket;
  bool closed = false;

  @override
  void initState() {
    super.initState();
    final ledger = widget.ledger;
    openedTicket = widget.ticket;
    ledger.init++;
    ledger.opens++;
    ledger.states.add(this);
    ledger.acceptedAtInit.add(widget.runtime.isCurrentSessionVerified ||
        (!widget.runtime.isDisposed &&
            widget.runtime.account.supabase.auth.currentSession == null &&
            widget.runtime.phase.value == MotionIdentityPhase.signedOut));
  }

  bool _canPublish(MotionAccountRuntime runtime, Session? captured, Object ticket) =>
      mounted && !closed && !runtime.isDisposed &&
      identical(ticket, widget.ledger.liveTicket) &&
      identical(ticket, openedTicket) &&
      identical(runtime, widget.runtime) &&
      captured != null && runtime.isCurrentSessionVerified &&
      identical(captured, runtime.account.supabase.auth.currentSession);

  bool acquire() {
    final runtime = widget.runtime;
    final session = runtime.account.supabase.auth.currentSession;
    if (!_canPublish(runtime, session, widget.ticket)) return false;
    widget.ledger.acquisitions++;
    return true;
  }

  Future<bool> publishAfter(_OwnedHold hold) async {
    final runtime = widget.runtime;
    final session = runtime.account.supabase.auth.currentSession;
    final ticket = widget.ticket;
    if (!_canPublish(runtime, session, ticket)) return false;
    await hold.wait();
    if (!_canPublish(runtime, session, ticket)) return false;
    widget.ledger.publications++;
    return true;
  }

  @override
  void didUpdateWidget(covariant _ScopeSpy oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.ledger.updates++;
    widget.ledger.configurations.add(widget.configuration);
  }

  @override
  Widget build(BuildContext context) {
    widget.ledger.builds++;
    return MaterialApp(
      navigatorKey: navigator,
      initialRoute: '/lesson',
      routes: {
        '/': (_) => const Scaffold(body: Text('ROOT_ROUTE')),
        '/lesson': (_) => _RouteSpy(
          key: route,
          ledger: widget.ledger,
          configuration: widget.configuration,
        ),
      },
    );
  }

  @override
  void dispose() {
    closed = true;
    widget.ledger.dispose++;
    widget.ledger.closes++;
    super.dispose();
  }
}

class _RouteSpy extends StatefulWidget {
  const _RouteSpy({super.key, required this.ledger, required this.configuration});
  final _ScopeLedger ledger;
  final String configuration;
  @override
  State<_RouteSpy> createState() => _RouteSpyState();
}

class _RouteSpyState extends State<_RouteSpy> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    widget.ledger.routes.add(this);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Focus(
      focusNode: focus,
      child: Semantics(
        label: 'PRIVATE_ACCOUNT',
        excludeSemantics: true,
        child: Text('ACCOUNT_PRIVATE ${widget.configuration}'),
      ),
    ),
  );
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }
}

Widget _gate(
  _Harness h,
  _ScopeLedger ledger, {
  MotionAccountRuntime? runtime,
  String configuration = 'initial',
  bool useTicketKey = true,
}) => MotionIdentityGate(
  key: useTicketKey ? ValueKey<Object>(ledger.liveTicket) : null,
  runtime: runtime ?? h.runtime,
  child: _ScopeSpy(
    key: ValueKey<Object>(ledger.liveTicket),
    runtime: runtime ?? h.runtime,
    ledger: ledger,
    ticket: ledger.liveTicket,
    configuration: configuration,
  ),
);

Future<void> _pumpGate(
  WidgetTester tester,
  _Harness h,
  _ScopeLedger ledger, {
  MotionAccountRuntime? runtime,
  String configuration = 'initial',
  bool useTicketKey = true,
}) async {
  await tester.pumpWidget(_gate(h, ledger,
    runtime: runtime, configuration: configuration, useTicketKey: useTicketKey));
  await tester.pump();
  await tester.pump(); // Cold retirement's removal frame precedes new admission.
}

void _expectRetained(_ScopeLedger ledger, _ScopeSpyState state,
    NavigatorState? navigator, _RouteSpyState? route) {
  expect(ledger.init, 1);
  expect(ledger.opens, 1);
  expect(ledger.dispose, 0);
  expect(ledger.closes, 0);
  expect(identical(ledger.latest, state), isTrue);
  expect(identical(ledger.latest.resource, state.resource), isTrue);
  expect(identical(ledger.latest.openedTicket, ledger.liveTicket), isTrue);
  expect(identical(state.navigator.currentState, navigator), isTrue);
  expect(identical(state.route.currentState, route), isTrue);
  expect(navigator?.canPop(), isTrue); // Existing non-home route stack is retained.
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('silent same-token replacement has no inherited current proof', () async {
    final h = await _Harness.boot();
    final original = h.client.auth.currentSession;
    h.requests.hold = true;
    final oldCall = h.refresh();
    final oldReply = await h.reply();
    var events = 0;
    final subscription = h.listen((_) => events++);
    await Future<void>.delayed(Duration.zero);
    events = 0;
    await h.recover(_session(_alice));
    final replacement = h.client.auth.currentSession;
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
    expect(identical(original, replacement), isFalse);
    expect(original?.accessToken, replacement?.accessToken);
    expect(h.runtime.phase.value, MotionIdentityPhase.verified);
    expect(h.runtime.isCurrentSessionVerified, isFalse);

    oldReply.succeed(_alice);
    await oldCall; // A normal void return is not fresh proof for replacement.
    expect(_legacyAdmits(h.runtime, replacement), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    final freshCall = h.refresh();
    final freshReply = await h.reply();
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    freshReply.succeed(_alice);
    await freshCall;
    expect(identical(h.client.auth.currentSession, replacement), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(h.clearedIds, isEmpty);
    await h.cancel(subscription);
  });

  test('captured replacement plus stale void call cannot admit pending G2', () async {
    final h = await _Harness.boot();
    await h.recover(_session(_alice));
    final captured = h.client.auth.currentSession;
    h.requests.hold = true;
    final g1 = h.refresh();
    final r1 = await h.reply();
    final g2 = h.refresh();
    final r2 = await h.reply();
    r1.succeed(_alice);
    await g1;
    expect(_legacyAdmits(h.runtime, captured), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    r2.succeed(_alice);
    await g2;
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(identical(h.client.auth.currentSession, captured), isTrue);
  });

  test('latest same-Session denial stays closed after older success', () async {
    final h = await _Harness.boot();
    h.requests.hold = true;
    final g1 = h.refresh();
    final r1 = await h.reply();
    final g2 = h.refresh();
    final r2 = await h.reply();
    final denied = h.expectFailure(g2, throwsA(isA<AuthException>()));
    r2.deny();
    await denied;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    r1.succeed(_alice);
    await g1;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.runtime.phase.value, MotionIdentityPhase.unavailable);
    expect(h.clearedIds, isEmpty);
  });

  for (final latest in ['success', 'denial']) {
    for (final stale in ['success', 'denial', 'offline']) {
      test('latest $latest proof survives stale $stale completion', () async {
        final h = await _Harness.boot();
        h.requests.hold = true;
        final g1 = h.refresh();
        final r1 = await h.reply();
        final g2 = h.refresh();
        final r2 = await h.reply();
        if (latest == 'success') {
          r2.succeed(_alice);
          await g2;
        } else {
          final failed = h.expectFailure(g2, throwsA(isA<AuthException>()));
          r2.deny();
          await failed;
        }
        if (stale == 'success') {
          r1.succeed(_alice);
          await g1;
        } else if (stale == 'denial') {
          r1.deny();
          await g1; // Superseded AuthException returns void in existing API.
        } else {
          r1.fail();
          await g1; // Superseded SDK errors do not alter the latest proof.
        }
        expect(h.runtime.isCurrentSessionVerified, latest == 'success');
        expect(
          h.runtime.phase.value,
          latest == 'success'
              ? MotionIdentityPhase.verified
              : MotionIdentityPhase.unavailable,
        );
        expect(h.clearedIds, isEmpty);
      });
    }
  }

  test('exact accepted Session keeps positive proof during pending refresh', () async {
    final h = await _Harness.boot();
    final accepted = h.client.auth.currentSession;
    final observations = <bool>[];
    h.runtime.identityVerification.addListener(
      () => observations.add(h.runtime.isCurrentSessionVerified),
    );
    h.requests.hold = true;
    final call = h.refresh();
    final reply = await h.reply();
    expect(h.runtime.phase.value, MotionIdentityPhase.verified);
    expect(h.runtime.userId.value, _alice);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(observations, isEmpty);
    reply.succeed(_alice);
    await call;
    expect(identical(h.client.auth.currentSession, accepted), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(observations, contains(true));
  });

  test('same UUID and token accepted replacement sends proof notification', () async {
    final h = await _Harness.boot();
    final original = h.client.auth.currentSession;
    final observations = <bool>[];
    h.runtime.identityVerification.addListener(
      () => observations.add(h.runtime.isCurrentSessionVerified),
    );
    await h.recover(_session(_alice));
    final replacement = h.client.auth.currentSession;
    expect(original?.user.id, replacement?.user.id);
    expect(original?.accessToken, replacement?.accessToken);
    expect(identical(original, replacement), isFalse);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    h.requests.hold = true;
    final call = h.refresh();
    final reply = await h.reply();
    expect(observations, contains(false));
    reply.succeed(_alice);
    await call;
    expect(h.runtime.userId.value, _alice);
    expect(h.runtime.phase.value, MotionIdentityPhase.verified);
    expect(observations.last, isTrue);
  });

  test('actual A to B to A requires fresh proof and rejects delayed B verification', () async {
    final h = await _Harness.boot();
    final firstA = h.client.auth.currentSession;
    h.requests.hold = true;
    await h.signIn(userId: _bob);
    final delayedB = await h.reply();
    final actualB = h.client.auth.currentSession;
    expect(identical(firstA, actualB), isFalse);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    await h.signIn(userId: _alice);
    final finalAReply = await h.reply();
    final finalA = h.client.auth.currentSession;
    expect(identical(firstA, finalA), isFalse);
    expect(finalA?.user.id, _alice);
    delayedB.succeed(_bob);
    await Future<void>.delayed(Duration.zero);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    finalAReply.succeed(_alice);
    await h.until(() => h.runtime.isCurrentSessionVerified);
    expect(identical(h.client.auth.currentSession, finalA), isTrue);
    expect(h.runtime.userId.value, _alice);
    expect(h.clearedIds, isEmpty);
  });

  test('public cached auth replay with unchanged actual Session keeps proof', () async {
    final h = await _Harness.boot();
    final accepted = h.client.auth.currentSession;
    final replay = await h.replay();
    expect(identical(replay.session, accepted), isTrue);
    expect(identical(h.client.auth.currentSession, accepted), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(h.clearedIds, isEmpty);
  });

  test('public credential refresh replaces proof without erasing UUID storage', () async {
    final h = await _Harness.boot();
    final original = h.client.auth.currentSession;
    h.requests.hold = true;
    await h.refreshCredentials();
    final reply = await h.reply();
    final replacement = h.client.auth.currentSession;
    expect(h.requests.refreshRequests, 1);
    expect(identical(original, replacement), isFalse);
    expect(original?.user.id, replacement?.user.id);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.clearedIds, isEmpty);
    reply.succeed(_alice);
    await h.until(() => h.runtime.isCurrentSessionVerified);
    expect(identical(h.client.auth.currentSession, replacement), isTrue);
    expect(h.clearedIds, isEmpty);
    // The host storage epoch is outside Core; no filesystem behavior is claimed.
  });

  testWidgets('latest real-zone timeout clears proof and ignores late success', (tester) async {
    final h = await _real(
      tester,
      () => _Harness.boot(tester: tester, timeout: const Duration(milliseconds: 100)),
    );
    await _real(tester, () async {
      h.requests.hold = true;
      final failed = h.expectFailure(h.refresh(), throwsA(isA<TimeoutException>()));
      final reply = await h.reply();
      expect(h.runtime.isCurrentSessionVerified, isTrue);
      await failed; // A bounded real-zone deadline; teardown needs no fake pump.
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(h.runtime.phase.value, MotionIdentityPhase.unavailable);
      reply.succeed(_alice);
      await Future<void>.delayed(Duration.zero);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(h.clearedIds, isEmpty);
    });
  });

  test('latest same-Session offline failure clears proof without cleanup', () async {
    final h = await _Harness.boot();
    h.requests.hold = true;
    final failed = h.expectFailure(h.refresh(), throwsA(anything));
    final reply = await h.reply();
    reply.fail();
    await failed;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.runtime.phase.value, MotionIdentityPhase.unavailable);
    expect(h.clearedIds, isEmpty);
  });

  test('guest invalidates before held SDK signout and rejects old verification', () async {
    final storage = _HeldRemoveStorage();
    final h = await _Harness.boot(storage: storage);
    final accepted = h.client.auth.currentSession;
    final observations = <bool>[];
    final actualAtNotification = <Session?>[];
    h.runtime.identityVerification.addListener(() {
      observations.add(h.runtime.isCurrentSessionVerified);
      actualAtNotification.add(h.client.auth.currentSession);
    });
    h.requests.hold = true;
    final old = h.refresh();
    final oldReply = await h.reply();
    storage.hold = true;
    final guest = h.guest();
    await h.storageEntered();
    // The first invalidation pulse preceded the SDK's synchronous local removal.
    expect(observations.first, isFalse);
    expect(identical(actualAtNotification.first, accepted), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    oldReply.succeed(_alice);
    await old;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    storage.release();
    await guest;
    expect(h.client.auth.currentSession, isNull);
    expect(h.runtime.phase.value, MotionIdentityPhase.signedOut);
    expect(h.clearedIds, isEmpty);
  });

  test('dispose invalidates before held success and never republishes proof', () async {
    final h = await _Harness.boot();
    final observations = <bool>[];
    h.runtime.identityVerification.addListener(
      () => observations.add(h.runtime.isCurrentSessionVerified),
    );
    h.requests.hold = true;
    final call = h.refresh();
    final reply = await h.reply();
    h.runtime.dispose();
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(observations.last, isFalse);
    reply.succeed(_alice);
    await call;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
  });

  test('dispose while guest signout is held completes without new proof', () async {
    final storage = _HeldRemoveStorage();
    final h = await _Harness.boot(storage: storage);
    storage.hold = true;
    final guest = h.guest();
    await h.storageEntered();
    h.runtime.dispose();
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    storage.release();
    await guest;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.clearedIds, isEmpty);
  });

  test('latest UUID mismatch invalidates accepted proof without cleanup', () async {
    final h = await _Harness.boot();
    h.requests.hold = true;
    final failed = h.expectFailure(
      h.refresh(),
      throwsA(isA<StateError>()),
    );
    final reply = await h.reply();
    reply.succeed(_bob);
    await failed;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.runtime.phase.value, MotionIdentityPhase.unavailable);
    expect(h.clearedIds, isEmpty);
  });

  test('current UUID receipt invalidates proof before held cleanup', () async {
    var admittedReceipt = false;
    final cleanupHold = _OwnedHold();
    final h = await _Harness.boot(
      localAccountIds: () async => admittedReceipt ? [_alice] : [],
      receipt: (_) async => true,
      cleanupHold: cleanupHold,
    );
    admittedReceipt = true;
    final scan = h.scan();
    await h.entered(cleanupHold);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.runtime.phase.value, MotionIdentityPhase.unavailable);
    expect(h.clearedIds, [_alice]);
    cleanupHold.release();
    await scan;
    await Future<void>.delayed(Duration.zero);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.client.auth.currentSession, isNull);
  });

  test('other UUID receipt cleanup preserves current accepted proof', () async {
    var admittedReceipt = false;
    final cleanupHold = _OwnedHold();
    final h = await _Harness.boot(
      localAccountIds: () async => admittedReceipt ? [_bob] : [],
      receipt: (_) async => true,
      cleanupHold: cleanupHold,
    );
    final accepted = h.client.auth.currentSession;
    admittedReceipt = true;
    final scan = h.scan();
    await h.entered(cleanupHold);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(h.runtime.phase.value, MotionIdentityPhase.verified);
    cleanupHold.release();
    await scan;
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(identical(h.client.auth.currentSession, accepted), isTrue);
    expect(h.clearedIds, [_bob]);
    expect(h.requests.logoutRequests, 0);
  });

  test('user-not-found clears proof before cleanup and protects replacement', () async {
    final cleanupHold = _OwnedHold();
    final h = await _Harness.boot(
      cleanupHold: cleanupHold,
    );
    h.requests.hold = true;
    final call = h.refresh();
    final reply = await h.reply();
    reply.missing();
    await h.entered(cleanupHold);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    await h.recover(_session(_alice));
    final replacement = h.client.auth.currentSession;
    cleanupHold.release();
    await call;
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(identical(h.client.auth.currentSession, replacement), isTrue);
    expect(h.requests.logoutRequests, 0);
    expect(h.clearedIds, [_alice]);
  });

  test('explicit guest and ordinary logout never supply erasure proof', () async {
    final h = await _Harness.boot();
    await h.guest();
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.runtime.phase.value, MotionIdentityPhase.signedOut);
    expect(h.client.auth.currentSession, isNull);
    expect(h.clearedIds, isEmpty);
  });

  test('userId listener retirement drains value notification without later phase write', () async {
    final h = await _Harness.boot(verifyOnBoot: false, holdInitialVerification: true);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      h.runtime.userId.addListener(() { h.runtime.dispose(); });
      final reply = await h.reply();
      reply.succeed(_alice);
      await h.until(() => h.runtime.isDisposed);
      expect(h.runtime.isDisposed, isTrue);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(errors, isEmpty);
      await h.close();
    } finally { FlutterError.onError = previous; }
  });

  test('value listener retirement prevents new verification request', () async {
    final h = await _Harness.boot();
    final before = h.requests.userRequests;
    h.runtime.userId.addListener(h.runtime.dispose);
    h.requests.userId = _bob;
    await h.recover(_session(_bob));
    await h.refresh();
    expect(h.runtime.isDisposed, isTrue);
    expect(h.requests.userRequests, before);
  });

  test('phase listener retirement prevents pre-verification HTTP admission', () async {
    final h = await _Harness.boot(signedIn: false);
    final before = h.requests.userRequests;
    h.runtime.phase.addListener(h.runtime.dispose);
    await h.signIn();
    await h.until(() => h.runtime.isDisposed);
    expect(h.requests.userRequests, before);
  });

  for (final listenerCount in [1, 2]) {
    test('proof listener disposal with $listenerCount listeners drains notification stack', () async {
      final h = await _Harness.boot();
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        var firstCalls = 0;
        var secondCalls = 0;
        h.runtime.identityVerification.addListener(() {
          firstCalls++;
          h.runtime.dispose();
          expect(h.runtime.isCurrentSessionVerified, isFalse);
        });
        if (listenerCount == 2) {
          h.runtime.identityVerification.addListener(() {
            secondCalls++;
            expect(h.runtime.isCurrentSessionVerified, isFalse);
          });
        }
        await h.refresh(); // Current success pulses the public Listenable.
        expect(firstCalls, 2); // Outer success and nested final-false pulse.
        expect(secondCalls, listenerCount == 2 ? 2 : 0); // Retained outer iteration.
        expect(h.runtime.isCurrentSessionVerified, isFalse);
        expect(h.resourcesClosed, isFalse); // Runtime fence is not client closure.
        final admitted = h.requests.userRequests;
        await h.refresh();
        await h.guest();
        expect(h.requests.userRequests, admitted);
        expect(h.requests.logoutRequests, 0);
        await h.close();
        expect(h.resourcesClosed, isTrue);
        expect(h.clientDisposeRuns, 1);
        expect(errors, isEmpty);
      } finally {
        FlutterError.onError = previous;
      }
    });
  }

  test('replacement pulse retirement admits no new request or late proof', () async {
    final h = await _Harness.boot();
    h.requests.hold = true;
    final old = h.refresh();
    final held = await h.reply();
    await h.recover(_session(_alice));
    final admitted = h.requests.userRequests;
    h.runtime.identityVerification.addListener(h.runtime.dispose);
    await h.refresh(); // Observe replacement; listener retires before getUser.
    expect(h.requests.userRequests, admitted);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    held.succeed(_alice);
    await old;
    await h.guest();
    expect(h.requests.logoutRequests, 0);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
  });

  test('guest proof pulse retirement prevents SDK signout admission', () async {
    final h = await _Harness.boot();
    final original = h.client.auth.currentSession;
    final admitted = h.requests.userRequests;
    h.runtime.identityVerification.addListener(h.runtime.dispose);
    await h.guest();
    expect(h.requests.logoutRequests, 0);
    expect(h.requests.userRequests, admitted);
    expect(identical(h.client.auth.currentSession, original), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.clearedIds, isEmpty);
  });

  for (final authority in ['receipt', 'user_not_found']) {
    test('confirmed $authority cleanup survives proof-listener retirement', () async {
      var admittedReceipt = false;
      final cleanupHold = _OwnedHold();
      final h = await _Harness.boot(
        cleanupHold: cleanupHold,
        localAccountIds: () async => admittedReceipt ? [_alice] : [],
        receipt: (_) async => true,
      );
      h.runtime.identityVerification.addListener(h.runtime.dispose);
      late Future<void> cleanup;
      if (authority == 'receipt') {
        admittedReceipt = true;
        cleanup = h.scan();
      } else {
        h.requests.hold = true;
        cleanup = h.refresh();
        final reply = await h.reply();
        reply.missing();
      }
      await h.entered(cleanupHold);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(h.clearedIds, [_alice]); // UUID authority is independent of proof.
      cleanupHold.release();
      await cleanup;
      expect(h.requests.logoutRequests, 0);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
    });
  }

  test('confirmed receipt keeps UUID cleanup after replacement pulse retirement', () async {
    var admittedReceipt = false;
    final cleanupHold = _OwnedHold();
    final h = await _Harness.boot(
      cleanupHold: cleanupHold,
      localAccountIds: () async => admittedReceipt ? [_alice] : [],
      receipt: (_) async => true,
    );
    await h.recover(_session(_alice)); // Eventless exact-UUID replacement.
    final replacement = h.client.auth.currentSession;
    h.runtime.identityVerification.addListener(h.runtime.dispose);
    admittedReceipt = true;
    final cleanup = h.scan();
    await h.entered(cleanupHold);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.clearedIds, [_alice]);
    cleanupHold.release();
    await cleanup;
    expect(identical(h.client.auth.currentSession, replacement), isTrue);
    expect(h.requests.logoutRequests, 0);
  });

  test('late public signedOut pulse retirement stops recovery bookkeeping', () async {
    final storage = _HeldRemoveStorage();
    final h = await _Harness.boot(storage: storage);
    storage.hold = true;
    final logout = h.signOut();
    await h.storageEntered();
    await h.startRecovery(); // Supported public recovery event creates S2.
    await h.until(() => h.runtime.isCurrentSessionVerified);
    expect(h.runtime.isPasswordRecovery, isTrue);
    final replacement = h.client.auth.currentSession;
    final admitted = h.requests.userRequests;
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      h.runtime.identityVerification.addListener(h.runtime.dispose);
      storage.release(); // SDK publishes signedOut with actual S2 unchanged.
      await logout;
      await Future<void>.delayed(Duration.zero);
      expect(h.runtime.phase.value, MotionIdentityPhase.signedOut);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(identical(h.client.auth.currentSession, replacement), isTrue);
      expect(h.runtime.isPasswordRecovery, isTrue); // No post-retirement write.
      final alreadyAdmittedLogout = h.requests.logoutRequests;
      await h.refresh();
      await h.guest();
      expect(h.requests.userRequests, admitted);
      expect(h.requests.logoutRequests, alreadyAdmittedLogout);
      expect(h.clearedIds, isEmpty);
      await h.close();
      expect(h.resourcesClosed, isTrue);
      expect(errors, isEmpty);
    } finally {
      FlutterError.onError = previous;
    }
  });

  test('early assertion drains taken reply storage callback and subscription once', () async {
    var admittedReceipt = false;
    final storage = _HeldRemoveStorage();
    final cleanupHold = _OwnedHold();
    final h = await _Harness.boot(
      storage: storage,
      cleanupHold: cleanupHold,
      localAccountIds: () async => admittedReceipt ? [_alice] : [],
      receipt: (_) async => true,
    );
    h.listen((_) {});
    h.requests.hold = true;
    h.refresh(); // Owned even when an assertion prevents its explicit await.
    final taken = await h.reply();
    storage.hold = true;
    h.guest();
    await h.storageEntered();
    admittedReceipt = true;
    h.scan();
    await h.entered(cleanupHold);
    Object? primary;
    StackTrace? primaryStack;
    try {
      expect(false, isTrue, reason: 'intentional owned-fixture failure');
    } catch (error, stack) {
      primary = error;
      primaryStack = stack;
    }
    expect(primary, isA<TestFailure>());
    await expectLater(
      h.closePreservingPrimary(primary!, primaryStack!),
      throwsA(same(primary)),
    );
    expect(taken.response.isCompleted, isTrue);
    expect(h.requests.allHeld.every((r) => r.response.isCompleted), isTrue);
    expect(storage.released, isTrue);
    expect(cleanupHold.released, isTrue);
    expect(h.actions.done, isTrue);
    expect(h.requests.done, isTrue);
    expect(h.cleanupErrors, isEmpty);
    expect(h.resourcesClosed, isTrue);
    await h.close();
    expect(h.closeRuns, 1);
    expect(h.clientDisposeRuns, 1);
    expect(h.httpCloseRuns, 1);
  });

  test('bootstrap error closes acquired resources and preserves original error', () async {
    final primary = StateError('synthetic bootstrap failure');
    late _Harness acquired;
    await expectLater(
      _Harness.boot(onOwned: (owned) {
        acquired = owned;
        throw primary;
      }),
      throwsA(same(primary)),
    );
    expect(acquired.resourcesClosed, isTrue);
    expect(acquired.closeRuns, 1);
    expect(acquired.clientDisposeRuns, 1);
    expect(acquired.httpCloseRuns, 1);
    expect(acquired.cleanupErrors, isEmpty);
  });

  test('bootstrap Auth mismatch closes resources before rethrow', () async {
    late _Harness acquired;
    await expectLater(
      _Harness.boot(
        initialResponse: _user(_bob),
        onOwned: (owned) => acquired = owned,
      ),
      throwsA(isA<StateError>()),
    );
    expect(acquired.resourcesClosed, isTrue);
    expect(acquired.actions.done, isTrue);
    expect(acquired.clientDisposeRuns, 1);
    expect(acquired.httpCloseRuns, 1);
    expect(acquired.cleanupErrors, isEmpty);
  });

  testWidgets('early widget assertion joins real-zone work without fake clock pumping', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    Object? primary;
    StackTrace? primaryStack;
    try {
      await _real(tester, () async {
        h.requests.hold = true;
        h.refresh();
        await h.reply();
        expect(false, isTrue, reason: 'intentional widget fixture failure');
      });
    } catch (error, stack) {
      primary = error;
      primaryStack = stack;
    }
    expect(primary, isA<TestFailure>());
    await _real(tester, () async {
      await expectLater(
        h.closePreservingPrimary(primary!, primaryStack!),
        throwsA(same(primary)),
      );
    });
    expect(h.resourcesClosed, isTrue);
    expect(h.actions.done, isTrue);
    expect(h.requests.done, isTrue);
    expect(h.cleanupErrors, isEmpty);
    expect(h.clientDisposeRuns, 1);
  });

  // Uses the pinned SDK's own error broadcaster; all HTTP remains synthetic.
  Future<void> authStreamError(_Harness h) async {
    // ignore: invalid_use_of_internal_member
    h.client.auth.notifyException(StateError('synthetic auth stream failure'));
    await Future<void>.delayed(Duration.zero);
  }

  testWidgets('explicit successful guest recovers auth stream blocker', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    await tester.pumpWidget(MotionIdentityGate(
      runtime: h.runtime,
      child: const MaterialApp(home: Text('GUEST_HISTORY')),
    ));
    await _real(tester, () => authStreamError(h));
    await tester.pump();
    expect(find.text('GUEST_HISTORY'), findsNothing);
    await _real(tester, () => tester.tap(find.text('Continue as guest')));
    await _real(tester, () => h.until(() =>
        h.client.auth.currentSession == null &&
        h.runtime.phase.value == MotionIdentityPhase.signedOut));
    await tester.pump();
    await tester.pump();
    expect(find.text('GUEST_HISTORY'), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing);
    expect(h.clearedIds, isEmpty);
  });

  testWidgets('ordinary null signedOut does not recover auth stream blocker', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    await tester.pumpWidget(MotionIdentityGate(
      runtime: h.runtime,
      child: const MaterialApp(home: Text('GUEST_HISTORY')),
    ));
    await _real(tester, () => authStreamError(h));
    await tester.pump();
    await _real(tester, h.signOut);
    await tester.pump();
    await tester.pump();
    expect(h.client.auth.currentSession, isNull);
    expect(find.text('GUEST_HISTORY'), findsNothing);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(h.clearedIds, isEmpty);
  });

  testWidgets('failed guest signout keeps blocker even with null actual Session', (tester) async {
    final h = await _real(tester, () => _Harness.boot(
      tester: tester, storage: _HeldRemoveStorage(),
    ));
    await tester.pumpWidget(MotionIdentityGate(
      runtime: h.runtime,
      child: const MaterialApp(home: Text('GUEST_HISTORY')),
    ));
    await _real(tester, () => authStreamError(h));
    await tester.pump();
    h.storage!.failRemoval = true;
    await _real(tester, () => tester.tap(find.text('Continue as guest')));
    await _real(tester, () async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump();
    // The SDK clears in-memory Session before awaited storage removal fails.
    expect(h.client.auth.currentSession, isNull);
    expect(find.text('GUEST_HISTORY'), findsNothing);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(h.clearedIds, isEmpty);
    h.storage!.failRemoval = false;
  });

  for (final supersession in ['error', 'owner', 'dispose', 'gate']) {
    testWidgets('held guest cannot recover after newer $supersession', (tester) async {
      final h = await _real(tester, () => _Harness.boot(
        tester: tester, storage: _HeldRemoveStorage(),
      ));
      await tester.pumpWidget(MotionIdentityGate(
        runtime: h.runtime,
        child: const MaterialApp(home: Text('GUEST_HISTORY')),
      ));
      await _real(tester, () => authStreamError(h));
      await tester.pump();
      h.storage!.hold = true;
      await _real(tester, () => tester.tap(find.text('Continue as guest')));
      await _real(tester, h.storageEntered);
      if (supersession == 'error') {
        await _real(tester, () => authStreamError(h));
      } else if (supersession == 'owner') {
        h.requests.hold = true;
        await _real(tester, () => h.recover(_session(_bob)));
      } else if (supersession == 'dispose') {
        h.runtime.dispose();
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await _real(tester, () async {
        h.storage!.release();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('GUEST_HISTORY'), findsNothing);
      if (supersession == 'owner') {
        expect(h.client.auth.currentSession?.user.id, _bob);
        expect(h.runtime.isCurrentSessionVerified, isFalse);
      }
      expect(h.clearedIds, isEmpty);
    });
  }

  testWidgets('gate requires cold ticket reset after eventless same UUID acceptance', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    await tester.pumpWidget(MotionIdentityGate(
      runtime: h.runtime,
      child: const MaterialApp(home: Text('ACCOUNT_HISTORY')),
    ));
    expect(find.text('ACCOUNT_HISTORY'), findsOneWidget);
    await _real(tester, () => h.recover(_session(_alice)));
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    // Eventless mutation has no automatic UI-notification promise.
    h.requests.hold = true;
    late Future<void> call;
    final reply = await _real(tester, () async {
      call = h.refresh();
      return h.reply();
    });
    await tester.pump();
    expect(h.runtime.phase.value, MotionIdentityPhase.verified);
    expect(find.text('ACCOUNT_HISTORY'), findsNothing);
    await _real(tester, () async {
      reply.succeed(_alice);
      await call;
    });
    await tester.pump();
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(find.text('ACCOUNT_HISTORY'), findsNothing);
    // Exact proof is not an owner/E ticket. Explicit cold key reset starts a new
    // scope for this eventless replacement instead of revealing retained State.
    await tester.pumpWidget(MotionIdentityGate(
      key: const ValueKey('replacement-ticket'),
      runtime: h.runtime,
      child: const MaterialApp(home: Text('ACCOUNT_HISTORY')),
    ));
    await tester.pump();
    expect(find.text('ACCOUNT_HISTORY'), findsOneWidget);
    expect(h.clearedIds, isEmpty);
  });

  testWidgets('gate denies guest when late public signedOut retains actual Session', (tester) async {
    final h = await _real(tester, () => _Harness.boot(
      tester: tester,
      storage: _HeldRemoveStorage(), // Hold Completers are born in this real zone.
    ));
    final storage = h.storage!;
    h.requests.hold = true;
    storage.hold = true;
    final reply = await _real(tester, () async {
      final logout = h.signOut();
      await h.storageEntered();
      await h.recover(_session(_alice));
      final held = await h.reply();
      storage.release();
      await logout;
      await Future<void>.delayed(Duration.zero);
      return held;
    });
    expect(h.runtime.phase.value, MotionIdentityPhase.signedOut);
    expect(h.client.auth.currentSession, isNotNull);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    await tester.pumpWidget(MotionIdentityGate(
      runtime: h.runtime,
      child: const MaterialApp(home: Text('GUEST_HISTORY')),
    ));
    expect(find.text('GUEST_HISTORY'), findsNothing);
    await _real(tester, () async {
      reply.succeed(_alice);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.text('GUEST_HISTORY'), findsNothing);
    h.requests.hold = false;
    await _real(tester, h.refresh);
    await tester.pump();
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(find.text('GUEST_HISTORY'), findsOneWidget);
    expect(h.clearedIds, isEmpty);
  });


  testWidgets('public tokenRefreshed preserves admitted State route and resource ticket while proof is held', (tester) async {
    var semanticsOwned = false;
    var semanticsCloseRuns = 0;
    // Registered before the harness: its teardown runs after owned UI cleanup.
    addTearDown(() {
      if (semanticsOwned) expect(semanticsCloseRuns, 1);
    });
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    final semantics = tester.ensureSemantics(); // Public enabled tree handle.
    h.ownUiCleanup(() {
      semanticsCloseRuns++;
      semantics.dispose();
    });
    semanticsOwned = true;
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    final navigator = state.navigator.currentState;
    final route = state.route.currentState;
    final s1 = h.client.auth.currentSession;
    expect(find.semantics.byLabel('PRIVATE_ACCOUNT'), findsOneWidget);
    expect(state.acquire(), isTrue);
    final events = <AuthState>[];
    final ownedAuth = h.listen(events.add);
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      await h.refreshCredentials(); // Real public SDK refreshSession -> tokenRefreshed.
      return h.reply();
    });
    final s2 = h.client.auth.currentSession;
    expect(identical(s1, s2), isFalse);
    expect(s2?.user.id, s1?.user.id);
    expect(events.any((e) => e.event == AuthChangeEvent.tokenRefreshed &&
        identical(e.session, s2)), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    await tester.pump();
    await tester.pump();
    _expectRetained(ledger, state, navigator, route);
    expect(find.text('ACCOUNT_PRIVATE initial'), findsNothing);
    expect(find.text('ACCOUNT_PRIVATE initial', skipOffstage: false), findsOneWidget);
    expect(find.semantics.byLabel('PRIVATE_ACCOUNT'), findsNothing);
    expect(route?.focus.canRequestFocus, isFalse);
    expect(state.acquire(), isFalse); // Mounted resource is not new admission.
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
      await h.cancel(ownedAuth);
    });
    await tester.pump();
    _expectRetained(ledger, state, navigator, route);
    expect(find.text('ACCOUNT_PRIVATE initial'), findsOneWidget);
    expect(find.semantics.byLabel('PRIVATE_ACCOUNT'), findsOneWidget);
    expect(state.acquire(), isTrue);
    expect(h.clearedIds, isEmpty);
    await h.closeFromTest(); // Before Flutter's end-of-body semantics verification.
  });

  testWidgets('same actual Session refreshIdentity preserves visible admitted scope as a separate control', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    final navigator = state.navigator.currentState;
    final route = state.route.currentState;
    final accepted = h.client.auth.currentSession;
    late Future<void> call;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      call = h.refresh();
      return h.reply();
    });
    await tester.pump();
    expect(identical(h.client.auth.currentSession, accepted), isTrue);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    expect(find.text('ACCOUNT_PRIVATE initial'), findsOneWidget);
    _expectRetained(ledger, state, navigator, route);
    await _real(tester, () async {
      reply.succeed(_alice);
      await call;
    });
    await tester.pump();
    _expectRetained(ledger, state, navigator, route);
  });

  testWidgets('first gate mount never builds private child until matching current proof', (tester) async {
    final h = await _real(tester, () => _Harness.boot(
      tester: tester, verifyOnBoot: false, sessionBeforeRuntime: true,
      holdInitialVerification: true,
    ));
    final reply = await _real(tester, h.reply);
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger);
    expect(ledger.init, 0);
    expect(ledger.builds, 0);
    expect(ledger.opens, 0);
    expect(find.text('ACCOUNT_PRIVATE initial', skipOffstage: false), findsNothing);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 1);
    expect(ledger.opens, 1);
    expect(ledger.acceptedAtInit, [true]);
  });

  for (final failure in ['denial', 'mismatch', 'offline', 'timeout']) {
    testWidgets('first gate mount remains unbuilt after latest $failure', (tester) async {
      final h = await _real(tester, () => _Harness.boot(
        tester: tester, verifyOnBoot: false, sessionBeforeRuntime: true,
        holdInitialVerification: true,
        timeout: failure == 'timeout'
            ? const Duration(milliseconds: 100) : const Duration(seconds: 10),
      ));
      final reply = await _real(tester, h.reply);
      final ledger = _ScopeLedger();
      await _pumpGate(tester, h, ledger);
      expect(ledger.init, 0);
      expect(ledger.builds, 0);
      expect(ledger.opens, 0);
      await _real(tester, () async {
        if (failure == 'denial') reply.deny();
        if (failure == 'mismatch') reply.succeed(_bob);
        if (failure == 'offline') reply.fail();
        await h.until(() => h.runtime.phase.value == MotionIdentityPhase.unavailable);
      });
      await tester.pump();
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(ledger.init, 0);
      expect(ledger.builds, 0);
      expect(ledger.opens, 0);
      expect(h.clearedIds, isEmpty);
      if (failure == 'timeout') {
        await _real(tester, () async {
          reply.succeed(_alice);
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        expect(ledger.init, 0);
      }
    });
  }

  testWidgets('runtime reference reset never inherits same UUID Session or mounted admission', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final oldState = ledger.latest;
    final session = h.client.auth.currentSession;
    late MotionAccountRuntime replacement;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      replacement = h.additionalRuntime();
      return h.reply();
    });
    expect(identical(h.client.auth.currentSession, session), isTrue);
    expect(replacement.isCurrentSessionVerified, isFalse);
    await _pumpGate(tester, h, ledger, runtime: replacement, useTicketKey: false);
    expect(ledger.init, 1);
    expect(ledger.dispose, 1);
    expect(oldState.closed, isTrue);
    expect(find.text('ACCOUNT_PRIVATE initial', skipOffstage: false), findsNothing);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.untilFor(replacement, () => replacement.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 2);
    expect(ledger.opens, 2);
    expect(ledger.closes, 1);
    expect(identical(ledger.latest, oldState), isFalse);
    final successorState = ledger.latest;
    await _real(tester, () async {
      final failed = h.expectFailure(h.refresh(), throwsA(anything));
      final oldRuntimeReply = await h.reply();
      oldRuntimeReply.deny();
      await failed;
    });
    await tester.pump();
    expect(replacement.isCurrentSessionVerified, isTrue);
    expect(identical(ledger.latest, successorState), isTrue);
    expect(ledger.closes, 1); // Detached R1 notification cannot retire R2.
  });

  testWidgets('fresh distinct signedIn retires same UUID default scope before new proof', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final oldState = ledger.latest;
    final s1 = h.client.auth.currentSession;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      await h.signIn(); // Real public password sign-in emits signedIn for S2.
      return h.reply();
    });
    expect(identical(s1, h.client.auth.currentSession), isFalse);
    expect(h.client.auth.currentUser?.id, _alice);
    await tester.pump();
    await tester.pump();
    expect(oldState.closed, isTrue);
    expect(ledger.closes, 1);
    expect(ledger.init, 1);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 2);
    expect(ledger.closes, 1);
    expect(identical(ledger.latest, oldState), isFalse);
  });

  testWidgets('initial public identical Session replay keeps default admitted scope stable', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    final actual = h.client.auth.currentSession;
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final state = ledger.latest;
    final navigator = state.navigator.currentState;
    final route = state.route.currentState;
    final replay = await _real(tester, h.replay);
    expect(identical(replay.session, actual), isTrue);
    await tester.pump();
    _expectRetained(ledger, state, navigator, route);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
  });

  for (final producer in ['signedIn', 'tokenRefreshed']) {
    testWidgets('different UUID $producer retires old scope before successor proof', (tester) async {
      final h = await _real(tester, () => _Harness.boot(tester: tester));
      final ledger = _ScopeLedger();
      await _pumpGate(tester, h, ledger, useTicketKey: false);
      final oldState = ledger.latest;
      final reply = await _real(tester, () async {
        h.requests.hold = true;
        if (producer == 'signedIn') {
          await h.signIn(userId: _bob);
        } else {
          // A synthetic provider reply changes actual owner despite event label.
          h.requests.userId = _bob;
          await h.refreshCredentials();
        }
        return h.reply();
      });
      expect(h.client.auth.currentUser?.id, _bob);
      await tester.pump();
      await tester.pump();
      expect(oldState.closed, isTrue);
      expect(ledger.init, 1);
      expect(ledger.closes, 1);
      await _real(tester, () async {
        reply.succeed(_bob);
        await h.until(() => h.runtime.isCurrentSessionVerified);
      });
      await tester.pump();
      expect(ledger.init, 2);
      expect(ledger.latest.widget.runtime.userId.value, _bob);
      expect(ledger.closes, 1);
      expect(h.clearedIds, isEmpty);
    });
  }

  testWidgets('guest and account transitions retire each old scope once with actual Session checks', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final accountState = ledger.latest;
    await _real(tester, h.guest);
    await tester.pump();
    await tester.pump();
    expect(h.client.auth.currentSession, isNull);
    expect(h.runtime.phase.value, MotionIdentityPhase.signedOut);
    expect(accountState.closed, isTrue);
    expect(ledger.init, 2);
    expect(ledger.closes, 1);
    final guestState = ledger.latest;
    expect(guestState.acquire(), isFalse);
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      await h.signIn();
      return h.reply();
    });
    await tester.pump();
    await tester.pump();
    expect(guestState.closed, isTrue);
    expect(ledger.init, 2);
    expect(ledger.closes, 2);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 3);
    expect(ledger.acceptedAtInit, [true, true, true]);
    expect(h.clearedIds, isEmpty);
  });

  testWidgets('public recovery Session retires old scope and waits for matching proof', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final oldState = ledger.latest;
    final prior = h.client.auth.currentSession;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      await h.startRecovery(); // Public verifyOTP emits passwordRecovery.
      return h.reply();
    });
    expect(h.runtime.isPasswordRecovery, isTrue);
    expect(identical(prior, h.client.auth.currentSession), isFalse);
    await tester.pump();
    await tester.pump();
    expect(oldState.closed, isTrue);
    expect(ledger.init, 1);
    expect(ledger.closes, 1);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 2);
    expect(h.runtime.isPasswordRecovery, isTrue);
    expect(ledger.closes, 1);
    expect(h.clearedIds, isEmpty);
  });

  for (final failure in ['denial', 'offline', 'timeout']) {
    testWidgets('latest $failure hides admitted State without erasure and matching retry reveals it', (tester) async {
      final h = await _real(tester, () => _Harness.boot(
        tester: tester, timeout: failure == 'timeout'
            ? const Duration(milliseconds: 100) : const Duration(seconds: 10),
      ));
      final ledger = _ScopeLedger();
      await _pumpGate(tester, h, ledger);
      final state = ledger.latest;
      final navigator = state.navigator.currentState;
      final route = state.route.currentState;
      await _real(tester, () async {
        h.requests.hold = true;
        final failed = h.expectFailure(h.refresh(), throwsA(anything));
        final reply = await h.reply();
        if (failure == 'denial') reply.deny();
        if (failure == 'offline') reply.fail();
        await failed;
        if (failure == 'timeout') reply.succeed(_alice);
      });
      await tester.pump();
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      _expectRetained(ledger, state, navigator, route);
      expect(state.acquire(), isFalse);
      expect(find.text('ACCOUNT_PRIVATE initial'), findsNothing);
      expect(h.clearedIds, isEmpty);
      await _real(tester, () async {
        h.requests.hold = false;
        await h.refresh();
      });
      await tester.pump();
      _expectRetained(ledger, state, navigator, route);
      expect(find.text('ACCOUNT_PRIVATE initial'), findsOneWidget);
      expect(h.clearedIds, isEmpty);
    });
  }

  for (final evidence in ['receipt', 'user_not_found']) {
    testWidgets('confirmed $evidence UUID cleanup still completes after host ticket and runtime retirement', (tester) async {
      final ledger = _ScopeLedger();
      var receipt = false;
      late _OwnedHold cleanup;
      late _Harness h;
      h = await _real(tester, () => _Harness.boot(
        tester: tester,
        cleanupHold: cleanup = _OwnedHold(),
        localAccountIds: () async => [_alice],
        receipt: (_) async => receipt,
        onCleanupAdmission: (id) {
          if (id == _alice) {
            ledger.retireTicket(); // Synthetic host erase admission fence.
            h.runtime.dispose();
          }
        },
      ));
      await _pumpGate(tester, h, ledger);
      final state = ledger.latest;
      late Future<void> operation;
      await _real(tester, () async {
        if (evidence == 'receipt') {
          receipt = true;
          operation = h.scan();
        } else {
          h.requests.hold = true;
          operation = h.refresh();
          (await h.reply()).missing();
        }
        await h.entered(cleanup);
      });
      expect(h.runtime.isDisposed, isTrue);
      expect(h.runtime.isCurrentSessionVerified, isFalse);
      expect(state.acquire(), isFalse);
      await _pumpGate(tester, h, ledger);
      expect(state.closed, isTrue);
      expect(ledger.closes, 1);
      expect(ledger.init, 1);
      await _real(tester, () async {
        cleanup.release();
        await operation;
      });
      await tester.pump();
      expect(h.clearedIds, [_alice]);
      expect(ledger.init, 1);
      expect(ledger.closes, 1);
      expect(h.requests.logoutRequests, 0); // Retired runtime admits no signout.
    });
  }

  testWidgets('other UUID receipt preserves current proof State and ticket', (tester) async {
    var receipt = false;
    final h = await _real(tester, () => _Harness.boot(
      tester: tester, localAccountIds: () async => [_bob],
      receipt: (_) async => receipt,
    ));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    final navigator = state.navigator.currentState;
    final route = state.route.currentState;
    await _real(tester, () async {
      receipt = true;
      await h.scan();
    });
    await tester.pump();
    expect(h.clearedIds, [_bob]);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    _expectRetained(ledger, state, navigator, route);
  });

  testWidgets('fast same UUID signedIn proof cannot erase pending distinct Auth retirement', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    final state = ledger.latest;
    final s1 = h.client.auth.currentSession;
    await _real(tester, () async {
      await h.signIn();
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    expect(identical(s1, h.client.auth.currentSession), isFalse);
    expect(h.runtime.isCurrentSessionVerified, isTrue);
    // Actual fast proof succeeded before the test pumps public fake-zone Auth.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(state.closed, isTrue);
    expect(ledger.init, 2);
    expect(ledger.closes, 1);
    expect(identical(ledger.latest, state), isFalse);
  });

  testWidgets('unverified child configuration waits and host ticket key independently retires scope', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, configuration: 'admitted');
    final state = ledger.latest;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      await h.refreshCredentials();
      return h.reply();
    });
    final updates = ledger.updates;
    await _pumpGate(tester, h, ledger, configuration: 'unverified-new-config');
    expect(state.widget.configuration, 'admitted');
    expect(ledger.updates, updates);
    expect(ledger.configurations, isNot(contains('unverified-new-config')));
    ledger.retireTicket();
    await _pumpGate(tester, h, ledger, configuration: 'successor-config');
    expect(state.closed, isTrue);
    expect(ledger.closes, 1);
    expect(ledger.init, 1); // New ticket cannot first-mount while proof is absent.
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 2);
    expect(ledger.latest.widget.configuration, 'successor-config');
    expect(identical(ledger.latest.openedTicket, ledger.liveTicket), isTrue);
  });

  testWidgets('retained resource rejects old Session publication and admits new proven Session action', (tester) async {
    final ledger = _ScopeLedger();
    late _OwnedHold oldHold;
    late _OwnedHold newHold;
    final h = await _real(tester, () async {
      final owner = await _Harness.boot(tester: tester);
      oldHold = owner.ownHold();
      newHold = owner.ownHold();
      return owner;
    });
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    late Future<bool> oldPublication;
    final reply = await _real(tester, () async {
      oldPublication = h.actions.start(() => state.publishAfter(oldHold));
      await h.entered(oldHold);
      h.requests.hold = true;
      await h.refreshCredentials();
      return h.reply();
    });
    await tester.pump();
    expect(state.acquire(), isFalse);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.until(() => h.runtime.isCurrentSessionVerified);
      oldHold.release();
      expect(await oldPublication, isFalse);
    });
    await tester.pump();
    expect(ledger.init, 1);
    expect(ledger.closes, 0);
    expect(ledger.publications, 0);
    await _real(tester, () async {
      final current = h.actions.start(() => state.publishAfter(newHold));
      await h.entered(newHold);
      newHold.release();
      expect(await current, isTrue);
    });
    expect(ledger.publications, 1);
  });

  for (final order in ['older-first', 'newer-first']) {
    for (final stale in ['success', 'denial']) {
      testWidgets('overlapping credential refresh $order stale $stale keeps one scope and latest proof', (tester) async {
        final h = await _real(tester, () => _Harness.boot(tester: tester));
        final ledger = _ScopeLedger();
        await _pumpGate(tester, h, ledger);
        final state = ledger.latest;
        final navigator = state.navigator.currentState;
        final route = state.route.currentState;
        late _HeldUser s2Reply;
        late _HeldUser s3Reply;
        late Session? s2;
        await _real(tester, () async {
          h.requests.hold = true;
          await h.refreshCredentials();
          s2 = h.client.auth.currentSession;
          s2Reply = await h.reply();
          await h.refreshCredentials();
          s3Reply = await h.reply();
        });
        final s3 = h.client.auth.currentSession;
        expect(identical(s2, s3), isFalse);
        expect(s3?.user.id, _alice);
        await tester.pump();
        await tester.pump();
        _expectRetained(ledger, state, navigator, route);
        Future<void> finishOlder() => h.actions.start(() async {
          if (stale == 'success') s2Reply.succeed(_alice);
          if (stale == 'denial') s2Reply.deny();
          await Future<void>.delayed(Duration.zero);
        });
        await _real(tester, () async {
          if (order == 'older-first') {
            await finishOlder();
            expect(h.runtime.isCurrentSessionVerified, isFalse);
          }
          s3Reply.succeed(_alice);
          await h.until(() => h.runtime.isCurrentSessionVerified);
          if (order == 'newer-first') await finishOlder();
          expect(h.runtime.isCurrentSessionVerified, isTrue);
        });
        await tester.pump();
        _expectRetained(ledger, state, navigator, route);
        expect(identical(h.client.auth.currentSession, s3), isTrue);
        expect(find.text('ACCOUNT_PRIVATE initial'), findsOneWidget);
      });
    }
  }

  testWidgets('runtime final disposed pulse retires retained scope once and late success stays closed', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    final disposalObservations = <bool>[];
    h.runtime.identityVerification.addListener(() {
      if (h.runtime.isDisposed) disposalObservations.add(h.runtime.isCurrentSessionVerified);
    });
    late Future<void> call;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      call = h.refresh();
      return h.reply();
    });
    final requestCount = h.requests.userRequests;
    await _real(tester, () async { h.runtime.dispose(); });
    expect(disposalObservations, [false]);
    await tester.pump();
    await tester.pump();
    expect(state.closed, isTrue);
    expect(ledger.closes, 1);
    expect(ledger.init, 1);
    expect(state.acquire(), isFalse);
    await _real(tester, () async {
      reply.succeed(_alice);
      await call;
      await h.refresh();
      await h.guest();
    });
    await tester.pump();
    expect(h.runtime.isDisposed, isTrue);
    expect(h.runtime.isCurrentSessionVerified, isFalse);
    expect(h.requests.userRequests, requestCount);
    expect(h.requests.logoutRequests, 0);
    expect(ledger.init, 1);
    expect(ledger.closes, 1);
    expect(h.clearedIds, isEmpty);
  });

  for (final owner in ['account', 'guest']) {
    testWidgets('disposed first mount $owner never builds child or subscribes disposed notifiers', (tester) async {
      final h = await _real(tester, () => _Harness.boot(
        tester: tester, signedIn: owner == 'account',
      ));
      await _real(tester, () async { h.runtime.dispose(); });
      final ledger = _ScopeLedger();
      await _pumpGate(tester, h, ledger);
      expect(tester.takeException(), isNull);
      expect(h.runtime.isDisposed, isTrue);
      expect(ledger.init, 0);
      expect(ledger.builds, 0);
      expect(ledger.opens, 0);
      expect(find.text('ACCOUNT_PRIVATE initial', skipOffstage: false), findsNothing);
    });
  }

  testWidgets('new runtime after disposed first mount requires fresh exact Session proof', (tester) async {
    final h = await _real(tester, () => _Harness.boot(tester: tester));
    await _real(tester, () async { h.runtime.dispose(); });
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger, useTicketKey: false);
    expect(ledger.init, 0);
    final actual = h.client.auth.currentSession;
    late MotionAccountRuntime fresh;
    final reply = await _real(tester, () async {
      h.requests.hold = true;
      fresh = h.additionalRuntime();
      return h.reply();
    });
    await _pumpGate(tester, h, ledger, runtime: fresh, useTicketKey: false);
    expect(identical(actual, h.client.auth.currentSession), isTrue);
    expect(fresh.isCurrentSessionVerified, isFalse);
    expect(ledger.init, 0);
    await _real(tester, () async {
      reply.succeed(_alice);
      await h.untilFor(fresh, () => fresh.isCurrentSessionVerified);
    });
    await tester.pump();
    expect(ledger.init, 1);
    expect(ledger.acceptedAtInit, [true]);
    expect(h.runtime.isDisposed, isTrue);
  });

  testWidgets('early widget failure unmounts resource once before real-zone reply storage and receipt drain', (tester) async {
    var receipt = false;
    late _OwnedHold cleanup;
    final h = await _real(tester, () => _Harness.boot(
      tester: tester, storage: _HeldRemoveStorage(),
      cleanupHold: cleanup = _OwnedHold(),
      localAccountIds: () async => [_alice], receipt: (_) async => receipt,
    ));
    final ledger = _ScopeLedger();
    await _pumpGate(tester, h, ledger);
    final state = ledger.latest;
    Object? primary;
    StackTrace? primaryStack;
    try {
      await _real(tester, () async {
        h.requests.hold = true;
        h.refresh(); // Observed/owned even though assertion precedes its release.
        await h.reply(); // Taken reply remains in allHeld.
        h.storage!.hold = true;
        h.signOut();
        await h.storageEntered();
        receipt = true;
        h.scan();
        await h.entered(cleanup);
        expect(false, isTrue, reason: 'intentional owned Gate fixture failure');
      });
    } catch (error, stack) {
      primary = error;
      primaryStack = stack;
    }
    expect(primary, isA<TestFailure>());
    // The test binding does not promise to unmount after a pending exception.
    // No real callback waits on a fake-zone hold or private Auth cancellation.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(state.closed, isTrue);
    expect(ledger.closes, 1);
    await _real(tester, () async {
      await expectLater(h.closePreservingPrimary(primary!, primaryStack!),
          throwsA(same(primary)));
      await h.close(); // Idempotent join, never an orphan disposal.
    });
    expect(h.resourcesClosed, isTrue);
    expect(h.actions.done, isTrue);
    expect(h.requests.done, isTrue);
    expect(h.storage!.released, isTrue);
    expect(cleanup.released, isTrue);
    expect(h.closeRuns, 1);
    expect(h.clientDisposeRuns, 1);
    expect(h.httpCloseRuns, 1);
    expect(ledger.init, 1);
    expect(ledger.closes, 1);
    expect(h.cleanupErrors, isEmpty);
  });

}
