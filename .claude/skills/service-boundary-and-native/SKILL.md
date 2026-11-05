---
name: service-boundary-and-native
description: >-
  Wires every side effect and native channel in Motion Core as an injectable interface supplied
  by constructor, with one live implementation chosen by the consuming app, value-typed
  signatures returning typed results, hand-written contract-honouring fakes instead of mocks,
  every MethodChannel confined to its owning package's lib/src/, and versioned cross-language
  contracts edited on both sides in one commit. Use when adding or changing a store, purchase,
  platform-signal, camera, audio or telemetry port, injecting time (a DateTime Function() or
  MotionClock), writing a MethodChannel or platform bridge, replacing a stray DateTime.now() or
  direct SDK call inside a model or widget, or mirroring a shared format in Kotlin/Swift.
---

# Service boundary and native (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `service-boundary-and-native` skill (see `../LICENSE-flutter-skills.md`).

Every platform capability — reading "now", a store purchase, a platform signal, a camera or audio stream, a MethodChannel call — crosses the package's layers as an **injected interface**. The interface names value types only; the concrete SDK lives in exactly one class; **the consuming app wires the live implementation**; tests wire a deterministic fake. **Abstract exactly what cannot run in a test — nothing more.** This keeps domain code pure, SDKs swappable, and every package testable headlessly. Core is a library for five apps, so it never decides which live implementation runs; it offers the seam and, where it is sensible, a default live class the app opts into.

## Non-negotiable rules

1. **Every side effect is an injected interface, never a concrete SDK at the call site.** Models, notifiers, and domain code depend on the *interface*; a plugin or SDK is imported in exactly one live-implementation class. One seam to swap, one place to quarantine platform quirks, zero SDK reach into pure code.
2. **Abstract only what cannot run in `flutter test` / `dart test`.** One interface + one real implementation + one fake is justified. One interface + one implementation + no fake means delete the interface.
3. **Interface signatures reference value types only.** Name a `DateTime`, a domain value object, a sealed outcome — never a plugin type or a `dart:io` symbol, so the interface stays nameable from every layer.
4. **Every method returns a typed result; failure is control flow, not a swallowed exception.** Model a cancel, an empty fetch, or an unavailable target as a sealed outcome (or the package's result type). Dart has no `throws` declaration, so an unhandled failure silently vanishes. See `error-handling-typed-results`.
5. **Dependencies arrive by constructor and are required.** A constructor parameter has no default that opens a live SDK; a forgotten wiring is a compile error, never silent null data or a plugin opening at import time. No service locator, no global singleton, no second container.
6. **The consuming app wires exactly one live implementation per interface.** The app's composition root is the only place a live SDK is constructed; everything below it is wiring-blind. Core packages never reach for a global.
7. **Tests install a hand-written fake that honours the contract.** The fake's failure path must be reachable; a fake that always succeeds is a happy-path lie. Use `implements` (not `extends`) so a new interface method breaks the build.
8. **"Now" has exactly one source, injected.** No `DateTime.now()` or ambient `Random()` reachable from a model, notifier, or domain function. Pass a `DateTime Function() now` (as `motion_account` does with its `clock` field) or, for monotonic session timelines, Core's `MotionClock` (`StopwatchMotionClock` live, a hand-written clock in tests). Do not add a clock package or invent a second clock abstraction.
9. **A mutating service feeds the single write path: persist before publish.** A service that changes durable state is consumed by a method that commits (one transaction) before any state republishes, so a crash mid-flow never leaves "acknowledged but not durable".
10. **Every MethodChannel lives in its owning package's `lib/src/`, one file per channel; nothing else creates one.** A channel born inside a widget, model, or notifier is a defect however well it works. Platform channels are the least testable code in a package and must be findable in one place (today: `motion_camera`, `motion_platform_signals`).
11. **A cross-language shared format is a versioned contract with one owner per side, edited on both sides in the same commit and proven by a round-trip test.** No compiler, analyzer, or unit test catches a renamed key across the Dart/Kotlin/Swift boundary — only a real round-trip does.

## The interface and its typed outcome

```dart
// packages/motion_xyz/lib/src/share_port.dart — value types only, no plugin symbol.
sealed class ShareResult { const ShareResult(); }
final class Shared extends ShareResult { const Shared(); }
final class ShareDismissed extends ShareResult { const ShareDismissed(); }
final class ShareUnavailable extends ShareResult {
  const ShareUnavailable(this.code); // a stable code, never a localized string
  final String code;
}

abstract interface class SharePort {
  Future<ShareResult> share(String text); // a dismiss/unavailable is data, not a throw
}
```

The interface is small, value-typed, and returns a typed outcome. The package exports it from its public API file; the live class (the only importer of the SDK) is either exported separately for the app to opt into or owned by the app.

## Wiring by the consuming app

The app's composition root constructs the one live implementation and hands it to whatever needs it. The app may use `package:provider` or plain constructor passing; Core does not mandate either, and no Core package depends on a DI library.

```dart
// App side — the composition root. Everything below is wiring-blind.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final share = OsSharePort(); // the ONE live implementation
  runApp(App(share: share, now: DateTime.now));
}
```

```dart
// Inside Core or the app: a ChangeNotifier receives the interface by constructor,
// never reaches a global, and exposes intent methods over immutable state.
final class ShareModel extends ChangeNotifier {
  ShareModel(this._share, this._now); // required — no live default
  final SharePort _share;
  final DateTime Function() _now;
  // intent method keeps the single write path and the injected time source
}
```

Tests construct the model with a fake directly — no override machinery needed.

## Fakes over mocks

A hand-written fake that `implements` the interface and models the ways the world breaks. No mocking library, no codegen.

```dart
final class FakeSharePort implements SharePort {
  FakeSharePort(this._next);
  factory FakeSharePort.succeeding() => FakeSharePort(const Shared());
  factory FakeSharePort.unavailable() => FakeSharePort(const ShareUnavailable('no_target'));
  final ShareResult _next;
  int calls = 0;

  @override
  Future<ShareResult> share(String text) async {
    calls++;
    return _next; // resolves instantly — no plugin, no OS sheet; failure path reachable
  }
}

test('sharing an unavailable target surfaces a code, never throws', () async {
  final model = ShareModel(FakeSharePort.unavailable(), () => DateTime.utc(2026, 7, 21));
  addTearDown(model.dispose);
  expect(await model.shareText('hello'), isA<ShareUnavailable>());
});
```

## The native boundary

A MethodChannel is wrapped by one thin **`Gateway`** class in the owning package's `lib/src/` and exposed through the same injectable-interface seam. (A `Gateway` wraps a specific plugin, SDK, or `MethodChannel`; a `Port` or `Service` names a capability interface you define.) Keep the native side able to run without the Dart engine alive where latency demands it.

```dart
// packages/motion_xyz/lib/src/xyz_channel.dart — the ONLY MethodChannel owner here.
class XyzChannel {
  static const _channel = MethodChannel('motion_xyz');
  Future<void> publish(Map<String, Object?> contractJson) =>
      _channel.invokeMethod<void>('publish', contractJson);
}

// Sole Dart owner of the shared format.
// Mirror: android/.../XyzContract.kt and ios/.../XyzContract.swift
// (edit ALL sides in the same commit).
const int kXyzContractVersion = 1;
Map<String, Object?> toContractJson(String title, DateTime updatedAtUtc) => {
      'v': kXyzContractVersion, // a versioned contract we own
      'title': title,
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
    };
```

Every write path that changes a mirrored value republishes as part of the write, never as a follow-up someone remembers — a delete or clear republishes exactly as hard as a save. Prove the mirror with a round-trip test that sends a value through Dart and reads it back from the native side. A `shared_preferences`-style key-value store is a poor home for a cross-language contract: key names and value encodings differ per platform, so own a versioned file or message instead.

## Anti-patterns

- **Calling a plugin or SDK from a model, notifier, or domain function.** The real SDK is imported only inside its live implementation.
- **`DateTime.now()` / `Random()` reachable from a model, notifier, or domain function.**
- **A constructor default that quietly builds the live service** — it hides a missing wiring and can open real I/O at import.
- **Reaching for a mock framework to fake a boundary**, or a fake that always succeeds so the failure path is never exercised.
- **`onTap: () => service.doThing()`** — the arrow closure returns the `Future` into a `VoidCallback`, so the Future and its error are dropped and no lint catches it. Route through a `void`-returning handler that uses `unawaited(...)` with a `catchError` (see `async-safety`).
- **A MethodChannel created outside the owning package's `lib/src/`**, or a contract key renamed on one side of the language boundary without the others in the same commit.
- **Business logic inside the wiring code**, or a service locator alongside constructor injection.
- **User-facing copy inside a service.** The boundary returns a typed failure with a stable code; the presentation layer maps it to localized text.
- **A runtime fork on build flavor inside Core.** Core is flavor-blind; the consuming app chooses implementations at its composition root.

## Definition of done

- [ ] The boundary is an `abstract interface class`; its signatures reference value types only.
- [ ] The interface exists only because it cannot run in a test (real implementation AND fake); none added "for symmetry".
- [ ] Every method returns a typed result; a failure carries a stable code, never a localized string.
- [ ] Dependencies are required constructor parameters; no service locator, no live default.
- [ ] Exactly one live implementation is wired by the consuming app; no Core package imports a concrete SDK outside its live class.
- [ ] A hand-written fake `implements` the interface, honours the contract (failure reachable), and is used in tests — no mock framework.
- [ ] No `DateTime.now()` / `Random()` is reachable from a model, notifier, or domain function; time enters through the injected function or `MotionClock`.
- [ ] A mutating service feeds the single write path (persist before publish).
- [ ] Every MethodChannel lives in its owning package's `lib/src/`, one file per channel.
- [ ] Any cross-language shared format is versioned, owned once per side, edited on all sides in one commit, and covered by a round-trip test.

## Related skills

- `error-handling-typed-results` — the sealed result and failure spine every boundary method returns.
- `async-safety` — the void-handler pattern that closes the arrow-callback Future-drop hole, and the `mounted` / `BuildContext` guards.
- `testing-strategy` — fakes over mocks and the acceptance-gate posture.
- `dart3-idioms-and-coding-standards` — sealed outcomes and `abstract interface class` seams.

## References

- Flutter — Guide to app architecture: https://docs.flutter.dev/app-architecture/guide
- Flutter — Writing custom platform-specific code (MethodChannel): https://docs.flutter.dev/platform-integration/platform-channels
- `package:provider` (app-side option): https://pub.dev/packages/provider
