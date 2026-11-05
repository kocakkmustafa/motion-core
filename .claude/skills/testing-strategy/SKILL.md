---
name: testing-strategy
description: >-
  Test doctrine for Motion Core packages where test shape follows code, not the pyramid:
  business logic lives in Flutter-free packages tested with plain package:test; time enters
  as an injected function (never DateTime.now()); invariants are asserted with seeded fuzz
  loops against an independent oracle plus round-trip and boundary goldens; owned
  collaborators are bare-implements fakes with an honest failure path; ChangeNotifier and
  ValueNotifier objects are tested headlessly through listeners; one acceptance gate plus a
  runtime assert tripwire; coverage floors sit on unrecoverable-bug files, not a global
  percentage. Use when writing tests under packages/*/test, choosing pure vs flutter_test,
  adding a fuzz or round-trip property, writing a fake, testing a notifier, or triaging a
  flaky test.
---

# Testing Strategy (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `testing-strategy` skill (see `../LICENSE-flutter-skills.md`).

Tests are the only correctness instrument you control at build time: shape the suite to the code, not to a decades-old ratio, and make every test assert behaviour that a build either passes or fails. Applies to every test under `packages/*/test/` (and `integration_test/` where a package has one).

Golden, overflow, and accessibility widget mechanics live in `widget-golden-and-a11y-testing`; this skill governs everything below the pixel.

## Which runner a package uses

Motion Core has two kinds of package. Match the test dependency to the package, never the other way around:

| Package kind | Packages | Test dependency | Run with |
|---|---|---|---|
| Pure Dart (no Flutter SDK constraint) | `motion_core`, `motion_content`, `motion_media` | `package:test` (+ `lints`) | `dart test` |
| Flutter | `motion_account`, `motion_audio`, `motion_camera`, `motion_entitlements`, `motion_feedback`, `motion_platform_signals`, `motion_store`, `motion_telemetry` | `flutter_test` (+ `flutter_lints`) | `flutter test` |

A pure package must never import `flutter_test` or anything from the Flutter SDK; the missing SDK constraint in its `pubspec.yaml` *is* the structural boundary. Check `pubspec.yaml` before adding a dependency, and do not add a test or mocking library to a package without a recorded decision.

## Non-negotiable rules

1. **Shape the suite to the code, not the pyramid.** Test at the cheapest tier that can assert the behaviour. Anything expressible as `f(input) -> output` is a unit or property test, never a `pumpWidget`. Driving pure logic through the widget tree is slower, flakier, and hides which layer broke.
2. **Business rules live in the pure packages; inject time as a function.** Domain math imports no Flutter, plugin, or IO symbol. Time enters as a parameter — a `DateTime Function() now` (the shape `motion_account` already uses for its `clock` field) or, for monotonic session timelines, Core's `MotionClock` (`StopwatchMotionClock` in production, a hand-written clock in tests). **Never call `DateTime.now()` or an unseeded `Random()` from domain code.** Do not add a clock package; a function parameter is enough.
3. **Assert invariants, not just examples.** Every conversion has a **round-trip** test (`decode(encode(x)) == x`) and **boundary goldens** at half-way and limit values. Every universal claim is a **seeded fuzz** loop or property test checked against an **independent oracle**, never against the function under test. Print the generated input in `reason:` so a failure is its own minimal repro. Use `==` on integers only; `closeTo(x, 1e-9)` on doubles.
4. **Prefer bare-`implements` fakes over mocks for code you own.** `class FakeX implements X` (no `noSuchMethod`, no `extends`) turns an interface change into a **compile error**, models the risk (state, not call order) as a field, and documents the contract. No mocking library is a Core dependency; write the fake. A fake that cannot fail is a happy-path lie — give it a reachable failure mode.
5. **Test notifiers headlessly through listeners.** Core's observable state is `ChangeNotifier` / `ValueNotifier` (for example in `motion_account`). Construct the object with fakes, `addListener` a counter or collector, drive intent methods, assert on the exposed state and on how many notifications fired, and `dispose()` it in `addTearDown`. Never pump a widget just to test state.
6. **Guard one end-to-end acceptance gate per package.** A single realistic scenario asserted to its exact expected result, plus the **conservation invariant** (parts sum to the whole). Back it with a **runtime `assert` tripwire** inside the primitive itself — free in release, catches the bug the moment it happens.
7. **Hold a floor on unrecoverable-bug files by diff review, not a coverage gate.** Coverage is a published report, not a pass/fail percentage. Keep a 100% floor on the handful of **files** where a gap is silent data loss (store migration and fail-closed paths, the entitlement state machine, parsers with wire-format traps, redaction in `motion_telemetry`), enforced by **reading the diff**. First fix the *coverage-lies-upward* gap: `--coverage` omits files no test imports, so the raw number overstates safety.
8. **Never `pumpAndSettle()` on an indefinite animation** (splash, shimmer, spinner) — it hangs to a 10-minute timeout. Use `pump(Duration)`.
9. **Keep the suite fast, and hand structurally-untestable paths to a named manual pass.** Real microphone and camera behaviour, OEM device diversity, native plugin surfaces without a Flutter engine, and store sandbox purchases are listed in a **manual pre-release pass**, not faked green. A green test that proves nothing is worse than an admitted gap.

## Tier the test to the code

```dart
// packages/motion_core/test/pose/normalize_test.dart — pure Dart, `dart test`.
import 'package:test/test.dart';

void main() {
  // Round-trip: encoding is lossless across the supported range.
  test('encode/decode round-trips for every sample', () {
    for (final sample in samples) {
      expect(decode(encode(sample)), equals(sample), reason: 'sample=$sample');
    }
  });
}
```

## Inject time as a function; pin it in tests

```dart
// Production: due when the target instant has passed. `now` is injected.
bool isDue(DateTime dueAt, DateTime Function() now) => !now().isBefore(dueAt);

// Test: freeze time by passing a closure — no wall clock, no flake.
test('due exactly at the due instant', () {
  final due = DateTime.utc(2026, 1, 1, 9);
  expect(isDue(due, () => due), isTrue);
  expect(isDue(due, () => due.subtract(const Duration(microseconds: 1))), isFalse);
});
```

For code that schedules work (debounce, retry, timeout), accept the timer/scheduler as a parameter too, so a test calls the scheduled callback by hand instead of waiting. In widget tests, advance time with `tester.pump(const Duration(milliseconds: 300))`; in pure tests, drive a hand-written fake scheduler.

## Seeded fuzz against an independent oracle

```dart
test('allocate: parts always sum to the input (fuzz)', () {
  final rng = Random(0xC0FFEE); // dart:math, seeded — reproducible
  for (var seed = 0; seed < 500; seed++) {
    final n = rng.nextInt(20) + 1;
    final total = rng.nextInt(100000);
    final weights = List.generate(n, (_) => rng.nextInt(500));
    final parts = allocate(total: total, weights: weights);
    expect(parts.fold<int>(0, (a, b) => a + b), equals(total),
        reason: 'seed=$seed total=$total weights=$weights'); // its own repro
  }
});
```

The oracle must be independent of the function under test (a brute-force reference, a conservation law, or a known closed form).

## Hand-written fake with a reachable failure path

```dart
final class FakeEntitlementVerifier implements EntitlementVerifier {
  FakeEntitlementVerifier(this.outcome);
  VerifyOutcome outcome; // flip to a failure outcome to exercise the unhappy path
  int calls = 0;

  @override
  Future<VerifyOutcome> verify(VerifyRequest request) async {
    calls++;
    return outcome;
  }
}
```

State, not call order, is what the fake models. Tests then assert on observable results and on `calls` only where call count is the contract.

## Notifier test through a listener

```dart
test('addItem publishes the new total exactly once', () async {
  final model = CartModel(repository: FakeOrderRepo()); // a ChangeNotifier
  addTearDown(model.dispose);
  var notifications = 0;
  model.addListener(() => notifications++);

  await model.addItem(anItem);

  expect(model.totalMinor, 1299);
  expect(notifications, 1, reason: 'one change, one notification');
});
```

For a `ValueNotifier<T>`, listen and collect `value` into a list, then assert the sequence.

## Anti-patterns

- **Inverting the pyramid** — pushing `f(input) -> output` logic through `pumpWidget`.
- **`DateTime.now()` or ambient `Random()` reachable from domain logic** — "identical inputs, identical output" becomes untestable.
- **`flutter_test` imported into a pure package** — breaks the structural boundary and slows the fastest tier.
- **A fake that lies about its contract** (a dependency that can never fail).
- **`==` on doubles**, or one lucky example standing in for a universal claim.
- **`pumpAndSettle()` on an indefinite animation.**
- **A global or per-directory coverage-percentage gate** — rewards vanity tests; floor the unrecoverable files and publish the rest.
- **A green test over a structurally-untestable path** (real audio, native camera bridge, device diversity).
- **A test with no meaningful `expect`**, shared mutable state across tests, or a vague name like `test('works')`.
- **Leaking a notifier or stream** — forgetting `addTearDown(model.dispose)` leaves listeners alive across tests.

## Definition of done

- [ ] Each test lives at the cheapest tier that can assert it; pure logic runs under `package:test` in a pure package.
- [ ] Domain logic receives time (and any random seed) as parameters; no `DateTime.now()` or ambient `Random()`.
- [ ] Every conversion has a round-trip test and boundary goldens; every universal claim is a seeded fuzz or property test against an independent oracle with the input echoed in `reason:`.
- [ ] Owned collaborators are bare-`implements` fakes whose failure path is reachable.
- [ ] Notifiers are tested through listeners and disposed in teardown; no widget pumped to test state.
- [ ] One acceptance gate asserts a realistic scenario exactly plus the conservation invariant; the primitive carries a runtime `assert` tripwire.
- [ ] Floors sit on the unrecoverable-bug files; the coverage-lies-upward gap is addressed.
- [ ] No `pumpAndSettle()` on an indefinite animation.
- [ ] Every structurally-untestable path is named in the manual pre-release pass.

## Related skills

- `widget-golden-and-a11y-testing` — widget tier, overflow matrix, golden policy, honest accessibility limits.
- `service-boundary-and-native` — the injectable ports the fakes stand in for.
- `error-handling-typed-results` — the sealed `Result` / `Failure` the exhaustive-switch tests assert on.
- `async-safety` — dropped-Future holes the silence-review checklist targets.

## References

- Flutter testing overview — https://docs.flutter.dev/testing/overview
- `package:test` — https://pub.dev/packages/test
