---
name: error-handling-typed-results
description: >-
  Typed-error spine for Motion Core: recoverable failures are sealed result/failure values
  returned instead of thrown (per-boundary sealed types such as ContentLoadResult and
  SecureKeyResult, or a hand-rolled sealed Result<T,F>), each failure carrying a stable code and
  typed params, never a localized string; only bugs throw. Convert at the boundary with a narrow
  on-clause and report the original error and stack BEFORE returning a typed failure; switch
  exhaustively with no default:; reports go through motion_telemetry's public API and never carry
  raw video, audio, or personal data; Isolate.run errors are re-wrapped at the call site. Use when
  writing a result or failure type, a try/catch or sealed-switch default:, a repository, store or
  plugin-adapter boundary, or deciding between throw, assert, Exception and a sealed outcome.
---

# Error Handling — Typed Results (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `error-handling-typed-results` skill (see `../LICENSE-flutter-skills.md`).

Recoverable failures are typed **values** that flow through the layers and are switched on exhaustively; only genuine bugs and unrecoverable states throw. Two tiers, no middle ground. Core's existing code already follows this shape with per-boundary sealed results (`ContentLoadResult` in `motion_content`, `SecureKeyResult` in `motion_store`); new boundaries follow suit.

## Non-negotiable rules

1. **Model recoverable failures as values, not exceptions.** Anything that fails for a runtime reason the caller must handle — store I/O, file or cache I/O, a purchase or entitlement response, an expected not-found, invalid input, a platform signal that is unavailable — returns a sealed outcome. Throwing across a layer for an *expected* failure is a review reject.
2. **One sealed result family per boundary is the default.** Name it for the boundary (`<Thing>Result` / `<Thing>Failure`). A shared generic `Result<T, F extends Failure>` (hand-rolled, zero dependency, in a pure package) is allowed only as a recorded decision; adopt one vocabulary per package and never mix a hand-rolled type with a third-party one.
3. **Every failure subtype carries a stable `code` plus typed params — NEVER a user-facing or localized string.** A baked-in message breaks translation, right-to-left mirroring, and numeral rendering. Localize from the `code` at the presentation edge, through the app's or the package's own text mechanism (for example `MotionAccountLocalizations` in `motion_account`).
4. **`switch` failures exhaustively with NO `default:` / `case _:`.** Sealed exhaustiveness turns "added a new failure" into a *compile error* until every switch covers it; a wildcard silently defeats the only compiler-grade safety net.
5. **Convert at the boundary — report first, then return.** Wrap each dangerous call once, catch narrowly with an `on` clause, and record the original error and stack through the package's reporting path **before** returning the typed failure. A `PlatformException`, `FormatException`, or store exception never leaks past its adapter into a model or widget.
6. **Never swallow.** `catch (_) {}`, a bare `catch (e)` that discards type or stack, and `throw e` (use `rethrow`) are banned. Never catch `Error` subtypes (`StateError`, `AssertionError`): those are bugs; let them crash in debug.
7. **Keep pure logic total — it never throws.** Every pure function returns a value for every input; uncertainty is an explicit output (an `outOfRange` variant, a clamped value, a low-confidence flag). Programmer invariants use `assert` (stripped in release). Async and error handling live *outside* pure code, at the boundary seam.
8. **Anything *thrown* is a bug or an unrecoverable state, routed to the consuming app's global net — never a recoverable failure.** The two handlers (`FlutterError.onError` and `PlatformDispatcher.instance.onError`) are installed by the consuming app before `runApp`; Core only decides what reaches them. Recoverable failures never throw across a layer, so they never reach the net. `runZonedGuarded` is not used.
9. **Re-wrap `Isolate.run` / `compute` errors as a typed result at the call site.** Isolate errors do **not** reach `FlutterError.onError`; catch them where you await or they propagate opaquely.
10. **Errors are reported through `motion_telemetry`'s public API — and nothing sensitive ever enters it.** Use the package's gated path (`TelemetryEmitter` with an `EventAllowlist` and a `ConsentGate`; `Redactor` for attributes; `DiagnosticExporter` for an explicit, user-initiated export; all exported from `package:motion_telemetry/motion_telemetry.dart`). Report **codes, shapes, and counts**, never **raw video frames, raw audio, pose landmarks tied to a person, or any personal data**. A rejected event is a normal outcome (`EmitResult.rejected(reason)`), not an error to retry or work around. If a failure has no allowlisted event, add the event to the allowlist deliberately rather than putting free text in an attribute. Local logging for development stays out of release builds' telemetry path.

## The sealed outcome spine

Native Dart 3 `sealed`, zero dependencies. A boundary's outcome and its failure family:

```dart
// packages/motion_xyz/lib/src/order_result.dart — Flutter-free where the package allows.
sealed class OrderFailure {
  const OrderFailure();
  String get code; // stable, localization-key-like, e.g. 'order.not_found'
}

final class OrderNotFound extends OrderFailure {
  const OrderNotFound(this.id);
  final String id;
  @override
  String get code => 'order.not_found';
}

final class OrderStoreUnavailable extends OrderFailure {
  const OrderStoreUnavailable();
  @override
  String get code => 'order.store_unavailable';
}

sealed class OrderResult {
  const OrderResult();
}

final class OrderFound extends OrderResult {
  const OrderFound(this.order);
  final Order order;
}

final class OrderFailed extends OrderResult {
  const OrderFailed(this.failure);
  final OrderFailure failure;
}
```

Sealed variants are `final class` with a `const` constructor and `final` fields. You switch on the type and never compare instances, so do not write `==` / `hashCode` for them.

If a package adopts a shared generic result by recorded decision, the shape is:

```dart
sealed class Result<T, F extends Failure> { const Result(); }
final class Ok<T, F extends Failure> extends Result<T, F> { const Ok(this.value); final T value; }
final class Err<T, F extends Failure> extends Result<T, F> { const Err(this.failure); final F failure; }
```

## Convert at the boundary

Wrap the dangerous call once. Report the original exception and stack **before** returning a typed, string-free failure. `@useResult` (from `package:meta`, where the package already depends on it) makes discarding the outcome a lint error.

```dart
// The ONLY place the store SDK is imported.
Future<OrderResult> findOrder(String id) async {
  try {
    final row = await _store.byId(id).timeout(const Duration(seconds: 5));
    if (row == null) return OrderFailed(OrderNotFound(id));
    return OrderFound(row.toDomain());
  } on TimeoutException catch (e, st) {
    _report('order.find.timeout', e, st); // report FIRST — never swallow
    return const OrderFailed(OrderStoreUnavailable());
  } on StoreException catch (e, st) {
    _report('order.find.store', e, st);
    return OrderFailed(_mapStoreException(e)); // typed, stable code, no strings
  }
}
```

## Exhaustive switch at the call site

The model (a `ChangeNotifier` or `ValueNotifier` owner) switches every case; localization happens at the presentation edge, from the `code`.

```dart
final class OrderModel extends ChangeNotifier {
  OrderModel(this._repository);
  final OrderRepository _repository;

  OrderViewState state = const OrderLoading();

  Future<void> load(String id) async {
    switch (await _repository.findOrder(id)) {
      case OrderFound(:final order):
        state = OrderReady(order);
      case OrderFailed(:final failure): // sealed => no default:; a new case is a compile error
        state = OrderErrored(failure.code); // the view maps the code to localized text
    }
    notifyListeners();
  }
}
```

For UI that recovers per case rather than showing a generic error, switch the failure in the widget and map each `code` to a localized message — never a `default:`.

## The global net routes only thrown bugs

What reaches `FlutterError.onError` and `PlatformDispatcher.instance.onError` in the consuming app is only genuine bugs and unrecoverable states. Every recoverable failure is a typed value that never throws across a layer. Isolate errors are the one thrown category the net misses — re-wrap them at the call site:

```dart
Future<ReportResult> buildReport(ReportInput input) async {
  try {
    return ReportBuilt(await Isolate.run(() => ReportBuilder().run(input)));
  } on Object catch (e, st) {
    _report('report.compute', e, st);
    return const ReportFailed(ComputeFailed('report'));
  }
}
```

## Mechanism selection

| Situation | Mechanism |
|---|---|
| Expected, recoverable runtime failure (I/O, response, not-found, bad input) | Sealed outcome value |
| Programmer error: a precondition the caller broke | `assert` (debug only) or an `Error` subtype; never caught |
| A failure the caller cannot act on but must not hide (corrupt state) | Throw an `Exception`/`StateError`; the app's global net reports it |
| Value that might be absent in normal operation | Nullable return, documented |
| Uncertainty in a pure computation | An explicit output variant or clamped value; never a throw |

## Anti-patterns

- **`catch (_) {}` / bare `catch (e)`** — discards type *and* stack. Catch narrowly and report `(e, st)`.
- **A user-facing `String` inside a failure or exception** — breaks translation, mirroring, numeral rendering. Codes and typed params only.
- **`default:` / `case _:` on a sealed switch** — a new failure subtype slips through unhandled.
- **`throw e;` in a catch** — resets the stack to the rethrow line. Use `rethrow`.
- **A low-level exception in the UI** — `PlatformException` or `FormatException` reaching a model or widget. Convert it at the adapter.
- **`throw` inside pure logic for uncertainty** — keep it total; return an explicit "cannot within budget" value.
- **Catching `Error` subtypes "to be safe"** — you are hiding a bug.
- **A generic result whose error arm is `Exception` or `Object`** — no type to switch on. Type the failure as a sealed family.
- **`assert` on a platform or plugin return value** — stripped in release, so the real-device failure becomes total silence.
- **Putting raw video, audio, landmarks, or free text into a telemetry attribute** — the telemetry gate exists to make this impossible; do not route around it.
- **Treating notification, permission, or plugin errors as synchronous** — they are asynchronous channel errors; catch at the call site.

## Definition of done

- [ ] Recoverable failures return a sealed outcome; every call site `switch`es all cases with no `default:`.
- [ ] Each boundary owns one sealed failure family; every subtype carries a stable `code` plus typed params and no localized string.
- [ ] Pure logic stays total (returns, never throws); error handling lives at the repository, service, or adapter seam.
- [ ] Boundary catches are narrow (`on` clauses), report `(e, st)` first, then return a typed failure; `rethrow` preserves stacks.
- [ ] Only bugs and unrecoverable states are thrown into the consuming app's global net; no recoverable failure throws across a layer.
- [ ] `Isolate.run` / `compute` errors are re-wrapped as typed results at the call site.
- [ ] Error reporting uses `motion_telemetry`'s public API; no raw video, audio, or personal data reaches it.

## Related skills

- `async-safety` — the arrow-callback Future-drop hole, `unawaited` / `mounted` discipline, and subscription and timer disposal.
- `dart3-idioms-and-coding-standards` — sealed classes, exhaustive `switch` expressions, and total non-throwing functions.
- `service-boundary-and-native` — the injectable seam where SDK and plugin exceptions are caught and converted.
- `testing-strategy` — asserting on failure branches with fakes whose failure path is reachable.

## References

- Dart — Error handling: https://dart.dev/language/error-handling
- Dart — Exhaustiveness checking: https://dart.dev/language/branches#exhaustiveness-checking
- Dart — `sealed` class modifier: https://dart.dev/language/class-modifiers#sealed
- Dart — Concurrency (`Isolate.run`): https://dart.dev/language/concurrency
- Flutter — Handling errors in Flutter: https://docs.flutter.dev/testing/errors
