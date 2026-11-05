---
name: async-safety
description: >-
  No-silent-failure async discipline for Motion Core's Dart and Flutter code: the arrow-callback
  Future-drop hole that no lint catches (onTap: () => model.save(x)), void-returning event
  handlers, a State.mounted guard after EVERY await before touching BuildContext, capturing
  Navigator/ScaffoldMessenger before the gap, honest unawaited() that always ends in catchError,
  no empty or bare catches, rethrow over throw e, and cancelling every StreamSubscription,
  StreamController, Timer and sink in dispose. Use when writing or reviewing async/await, wiring
  onTap/onPressed or any VoidCallback, touching BuildContext after an await, writing
  initState/dispose/addPostFrameCallback, adding a Timer or Future.delayed, writing a try/catch,
  or seeing use_build_context_synchronously, cancel_subscriptions, close_sinks, or
  unawaited_futures.
---

# Async safety: no failure may be silent (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `async-safety` skill (see `../LICENSE-flutter-skills.md`).

Async bugs are silence. A dropped `Future` swallows its error; a dead `BuildContext` throws into a void; a leaked subscription fires into a disposed widget. Close these structurally, not with discipline. This skill applies whenever you write `async`/`await`, wire a callback, or hold a subscription, timer, or sink — in the Flutter packages (`motion_account`, `motion_camera`, `motion_audio`, …) and in the pure packages' stream and timer code alike.

## Non-negotiable rules

1. **A callback must never touch a `Future`.** Every `onTap` / `onPressed` / `onSubmitted` / `VoidCallback` handler returns `void`. `onTap: () => model.save(x)` where `save` is async is caught by NO lint (see below); the fix is shape, not vigilance.
2. **A `mounted` guard goes after EVERY await, immediately before the next `BuildContext` use** — never once at the top, never before the await where it proves nothing. Or capture the object you need before the gap.
3. **Multiple awaits means the guard sits after the LAST one.** A guard only certifies the interval since the most recent suspension point.
4. **`unawaited(x)` is legal only if `x` provably cannot fail silently** — it ends in `.catchError(...)` or is total. A bare `unawaited(f)` routes errors to `PlatformDispatcher.onError`, detached from the UI.
5. **Every `StreamSubscription`, `StreamController`, `Timer`, and sink is released** in `dispose()` (or the owning object's `close()`/`dispose()`), including in `ChangeNotifier` subclasses.
6. **Every timer or stream callback that calls `setState` guards `mounted` first.** A `Timer` holds a strong reference to its closure and fires happily after the widget is gone.
7. **No empty catch, no bare catch, no swallow.** Every `catch` has an `on` clause (except a crash or diagnostic logger's own write), records the stack, and surfaces the failure. Use `rethrow`, never `throw e` — the latter resets the stack trace.
8. **Never `assert` a platform or plugin return value.** Asserts are stripped in release: green in every test, absent on the device.
9. **Nothing unbounded runs before `runApp`.** The consuming app shows a usable first frame, then warms up in `addPostFrameCallback`, unawaited. Core packages expose warm-up as an explicit method; they never start it at import or in a constructor.
10. **Core never installs global error handlers.** `FlutterError.onError` and `PlatformDispatcher.instance.onError` belong to the consuming app, which installs them before `runApp`; a handler must never throw, and `PlatformDispatcher.onError` returns `true` when it handled the error. Do not use `runZonedGuarded` here.

## The hole no lint catches

Verified with `discarded_futures`, `unawaited_futures`, and `unused_result` all at `error`:

| Callback shape | Diagnostics |
|---|---|
| `onTap: () => model.save(note)` | **none — all three miss it** |
| `onTap: () { model.save(note); }` | `discarded_futures` |
| `onTap: () async { model.save(note); }` | `unawaited_futures` |
| `onTap: () => model.saveNote(note)` (void method) | clean — the fix |

The arrow closure *returns* the `Future`, so every rule considers it used; the target type is `VoidCallback`, so Dart's void-compatibility discards it. The `Future` and its error both hit the floor. This is the most idiomatic way to wire a Flutter tap, and it is exactly where silence hides.

The mitigation is **structural**: give the handler method a `void` return and do the `unawaited(... .catchError(...))` inside it. A callback then never holds a `Future`, so the hole is unreachable by construction.

```dart
// A void-returning seam. Do NOT "improve" this to Future<void> — that
// reopens the arrow-callback hole. Keep this comment; without it the next
// reader tidies the void away.
void saveNote(Note note) {
  unawaited(
    _persist(note).catchError((Object e, StackTrace s) {
      _report('save path threw', e, s);
      _showError(SaveFailed.code);
    }),
  );
}

Future<void> _persist(Note note) async {
  final result = await _repo.save(note); // returns a typed result, does not throw
  switch (result) {
    case Ok():
      return;
    case Err(:final failure):
      _showError(failure.code);
  }
}
```

## The async gap and BuildContext

`context` is a live handle into the element tree, not a value. `await` yields to the event loop; while suspended, the route may pop, the dialog may close, the `State` may be disposed. On resume the handle points at a corpse. Promote `use_build_context_synchronously` to `error`.

```dart
// WRONG — the Element may be defunct after the gap.
Future<void> _save() async {
  await _repo.save(note);
  Navigator.of(context).pop();
}

// RIGHT — capture before the gap. The captured object does not need the tree.
Future<void> _save() async {
  final navigator = Navigator.of(context);
  await _repo.save(note);
  navigator.pop();
}

// RIGHT — guard after the gap, immediately before the context use.
Future<void> _save() async {
  await _repo.save(note);
  if (!mounted) return;
  Navigator.of(context).pop();
}
```

Two awaits mean the guard sits after the second — the second await reopens the hole the first guard closed:

```dart
// WRONG
await _repo.save(note);
if (!mounted) return;
await _repo.reindex();
Navigator.of(context).pop(); // unguarded

// RIGHT
await _repo.save(note);
await _repo.reindex();
if (!mounted) return;
Navigator.of(context).pop();
```

### Which guard, where

| Context | Guard | Note |
|---|---|---|
| `State<T>` subclass | `if (!mounted) return;` | `State.mounted` — the field the analyzer recognises |
| `ChangeNotifier` / plain model after an await | Track a `_disposed` flag set in `dispose()` and return early before `notifyListeners()` | `notifyListeners()` on a disposed notifier throws |
| Plain class with no `State` | Take no `BuildContext` at all | Pass a captured `NavigatorState` or a `void Function(String)` callback |
| `StatelessWidget` method | Capture before the gap | There is no `mounted` to check |

A bare helper has no lifecycle to interrogate, so restructure: hand it a captured object or a callback so it never holds a context across a gap. Never write `if (!mounted) return;` *before* the await and call it done — that checks the one moment never in doubt.

## unawaited, initState, and the first frame

`initState` is synchronous and cannot be `async`. Kick the future off through a named method, then guard the landing:

```dart
@override
void initState() {
  super.initState();
  // honest: the load path ends in catchError; _load guards mounted before setState.
  unawaited(_load().catchError((Object e, StackTrace s) {
    _report('load failed', e, s);
    if (mounted) _showError(LoadFailed.code);
  }));
}

Future<void> _load() async {
  final notes = await _repo.loadNotes(); // may throw — the catchError above owns it
  if (!mounted) return; // a disposed widget's setState throws into nothing
  setState(() => _notes = notes);
}
```

Prefer not to hand-hold a subscription: expose state as a `ValueListenable` / `Stream` and let the widget own one `ValueListenableBuilder` / `StreamBuilder`, so teardown is automatic and there is no field to leak.

Never block the first frame on unbounded work. A tiny read is safe to await before `runApp`; a schema migration or a plugin warm-up is not. Show the shell first, then:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  unawaited(_service.warmUp().catchError((Object e, StackTrace s) {
    _report('warm-up failed', e, s); // best-effort; never blocks the frame
  }));
});
```

## Subscriptions, controllers, timers

Every long-lived resource is released. Keep `cancel_subscriptions` and `close_sinks` at `error`.

```dart
class _FeedState extends State<Feed> {
  StreamSubscription<List<Item>>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sub = widget.items.listen(_onItems);
  }

  void _onItems(List<Item> items) {
    if (!mounted) return; // a stream event can outlive dispose()
    setState(() => _items = items);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel()); // nothing to await, but mark the intentional drop
    _debounce?.cancel(); // Timer.cancel() returns void — no Future to mark
    super.dispose();
  }
}
```

`close_sinks` only fires when the rule is enabled under `linter: rules:`; the `analyzer: errors:` block merely re-ranks diagnostics that already exist and cannot switch a lint on. If a never-closed controller produces no diagnostic, check that the rule is actually enabled in the package's `analysis_options.yaml` rather than trusting a green run (the current options include `lints/recommended` or `flutter_lints` plus a few extra rules).

`Timer` and `Future.delayed` share the same rule: cancel the field in `dispose()`, and guard `mounted` in the callback. Re-arming a timer means cancel-then-restart, never "return if already running" — swallowing the event manufactures the silence this skill forbids.

## Catches

```dart
try { await _repo.save(item); } catch (_) {}                    // WRONG — unrecoverable, unknowable
try { await _repo.save(item); } catch (e) { _report('$e'); }    // WRONG — swallows Errors (our bugs)
try { await _repo.save(item); } on StoreException { /* oh well */ } // WRONG — logged nowhere, continues as success

// RIGHT — typed, with its trace, surfaced to the user.
try {
  await _repo.save(item);
} on StoreException catch (e, s) {
  _report('save failed', e, s);
  _showError(SaveFailed.code);
}
```

Catch at the few call sites that read or write the boundary, not in a blanket handler. Never catch an `Error` subclass — that means a bug in your own code; let it crash. The **one** licensed silent catch is a logger's own write (it runs inside error handlers; if it throws it recurses until the app dies), and its intent comment is the whole safeguard. Reporting goes through the package's own reporting path; telemetry, where used, goes through `motion_telemetry`'s public API and never carries raw media or personal data (see `error-handling-typed-results`).

## Anti-patterns

- **`onTap: () => asyncMethod()`** — drops the `Future` and its error, uncaught by any lint. Route through a void handler.
- **`if (!mounted) return;` before the await** — proves nothing; the hazard is *after* the suspension point.
- **One guard for two awaits** — the second await reopens the hole.
- **`unawaited(f)` with no `catchError`** on a fallible path — silences the lint, keeps the bug.
- **`notifyListeners()` after `dispose()`** — a model awaiting a future past its own disposal throws.
- **`assert(await plugin.call() == ok)`** — vanishes in release; total silence on the device.
- **`throw e` inside a catch** — resets the stack to the rethrow line; use `rethrow`.
- **An `async` `initState`, or `.then(...)` off it with no `mounted` guard** — `setState` on a disposed widget throws.
- **`pumpAndSettle` for timers in tests** — use `pump(duration)`.
- **`runZonedGuarded`** — a second error path nobody asked for; the consuming app installs the two global handlers.
- **Promoting a void handler method to `Future<void>`** — returns the arrow-callback hole to the codebase.

## Catalogue your silent-failure modes

For any real package, enumerate its silent-failure paths *a priori* as a closed list, tagged by testability — **D** (testable in Dart) · **I** (integration only) · **M** (manual only) · **X** (structurally untestable). This catalogue becomes the spine of the test strategy: reason against it as a closed set, and when you touch a listed mechanism, restore its mitigation. The honest value is that the highest-severity paths — a plugin reporting success while doing nothing, a camera stream silently stalling, a purchase callback that never arrives — often land in **M** or **X**, and naming them prevents papering over a gap with a fake that proves nothing. When you discover an (n+1)th way to go silent, add it to the catalogue.

## Definition of done

- [ ] Every `await` before a `context` use has a `mounted` guard **between** them, or the object was captured before the gap.
- [ ] Multiple awaits means the guard sits after the last one.
- [ ] No callback method that a `VoidCallback` slot invokes returns a `Future`.
- [ ] Every `unawaited(...)` ends in `.catchError` or is provably total.
- [ ] Every `StreamSubscription`, `StreamController`, `Timer`, and sink is released in `dispose()` / `close()`.
- [ ] Every timer or stream callback calling `setState` guards `mounted` first; models guard `notifyListeners()` after disposal.
- [ ] Every `catch` is typed, records its stack, and surfaces the failure (logger's own write excepted); `rethrow`, never `throw e`.
- [ ] No `assert` wraps a platform or plugin return value.
- [ ] Nothing unbounded runs before `runApp` or at construction; no `runZonedGuarded`.

## Related skills

- `error-handling-typed-results` — the sealed result and failure spine that lets `save()` return outcomes instead of throwing.
- `testing-strategy` — injected-time tests that exercise timers and the silent-failure catalogue.
- `service-boundary-and-native` — the injectable seams where plugin exceptions are caught and converted.

## References

- Async programming: https://dart.dev/libraries/async/async-await
- `use_build_context_synchronously`: https://dart.dev/tools/linter-rules/use_build_context_synchronously
- `discarded_futures`: https://dart.dev/tools/linter-rules/discarded_futures
- `State.mounted`: https://api.flutter.dev/flutter/widgets/State/mounted.html
- `PlatformDispatcher.onError`: https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/onError.html
- Handling errors in Flutter: https://docs.flutter.dev/testing/errors
