---
name: dartdoc-conventions
description: >-
  Effective-Dart documentation for Motion Core's public surface, where each package's public API
  file (lib/<package>.dart and everything it exports) is the contract: a /// doc on every public
  class, method, getter, field and typedef; a one-sentence standalone summary that says WHY plus
  units, ranges, nullability, throws and side effects (never a restatement of the name);
  verb-phrase method docs and "Whether…" boolean getters; [bracket] cross-links; one library doc
  per public API file; in-body // that explains why, not what; and the enforced invariant restated
  at its enforcement point. Use when adding or reviewing a public API in any packages/*/lib,
  a notifier or model, a service interface, a sealed failure, a value type, or when preparing a
  package for dartdoc.
---

# Dartdoc Conventions — the public surface is a contract (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `dartdoc-conventions` skill (see `../LICENSE-flutter-skills.md`).

Public code is read far more than it is written, and five apps consume Core. A symbol with no leading `_` is a **contract** callers depend on, so it carries a `///` doc a reader understands without opening the body. Doc comments use `///` and follow *Effective Dart: Documentation*.

**Scope.** The convention binds every symbol reachable from a package's public API file — `packages/<package>/lib/<package>.dart` and the `src/` files it exports (for example `packages/motion_telemetry/lib/motion_telemetry.dart`). A symbol that must not be part of that contract stays `_`-private or lives in an unexported `src/` file. The analyzer does not enforce this today: the packages include `lints/recommended` or `flutter_lints` with a few extra rules, and `public_member_api_docs` is not enabled. Turning that lint on for a package is a separate decision; until then this skill is the review standard, and the checklist below is what a reviewer checks.

## Non-negotiable rules

1. **Every public declaration in a package's public API gets a `///` doc** — public classes, constructors, methods, getters, top-level functions, typedefs, and fields. Making a symbol public "just in case" is a review reject — make it `_`-private (or leave it out of the exported files) so it needs no doc and no contract.
2. **`///`, never `/** */`.** Dartdoc only recognises `///`. A JavaDoc block is silently ignored and the symbol reads as undocumented.
3. **First line is one standalone sentence ending in a period, in its own paragraph.** Tools show only this sentence in API lists, so it must stand alone; a blank `///` line separates it from the body.
4. **Method and function docs start with a verb phrase** (third person): "Returns…", "Schedules…", "Loads…", "Marks…". A boolean getter or `bool`-returning method starts with "Whether…".
5. **Never restate the name.** `/// The name.` on `String name`, `/// Returns the total.` on `total()` — banned. If a public member has nothing to add beyond its name, make it `_`-private. A member that must stay public still needs a real `///`; add meaning: **units, ranges, nullability, throws, side effects**, and the invariant the symbol enforces.
6. **Cross-link identifiers in `[brackets]`** so dartdoc resolves them: `/// Throws [StateError] if [id] is unknown; see [copyWith].` A broken link is a warning.
7. **In-body `//` explains *why*, never *what*.** The code already says what. Narrating comments (`// loop over items`) rot out of sync and become misinformation. Comment the reason, the gotcha, or the invariant.
8. **Restate an enforced invariant at its enforcement point.** Where one line upholds a guarantee — an ordering, a clamp, a persist-before-publish, a canonical-unit conversion — a terse `//` states it so a diff that weakens it gets an unmissable flag. Same for a magic constant: cite where the number comes from.
9. **Docs change in the same diff as the code.** A wrong doc is worse than none. Every comment your change touches must still be true — put it on the PR checklist.
10. **One library doc per public API file.** The entry point (`<package>.dart`) gets a `///` library doc above the `library;` directive. A leading `///` with no attached declaration must be a real library doc, not an orphan above a blank line or an `export` (`dangling_library_doc_comments`).

## Documenting a value type

```dart
/// A note the user has authored and can later edit or archive.
///
/// Immutable; derive changes with [copyWith]. [updatedAt] is UTC and never
/// precedes [createdAt].
class Note {
  /// Creates a note; [updatedAt] must not precede [createdAt].
  const Note({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable unique identifier, assigned once at creation.
  final String id;

  /// Human-readable heading shown in lists; may be empty, never null.
  final String title;

  /// Creation instant, in **UTC**.
  final DateTime createdAt;

  /// Last-edit instant, in **UTC**; equals [createdAt] until first edited.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  Note copyWith({String? title, DateTime? updatedAt}) => Note(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
```

Every public field carries a `///`, including `title`: a field that "restates the name" is not a licence to drop the doc but a prompt to say something real (or make the field `_`-private). Document units and constraints explicitly where the type does not carry them: minor currency units, an inclusive or exclusive range, a duration unit, what `null` means, "must be `> 0`".

## Documenting behaviour — throws, async, side effects

```dart
/// Schedules a reminder for [task] at [when].
///
/// [when] must be in the future; a past instant is clamped to now. Persists the
/// scheduled row before arming the OS notification, so a crash mid-call cannot
/// leave a notification the store never recorded.
///
/// Throws [PermissionDeniedException] if the OS denied notification permission.
Future<void> scheduleReminder(Task task, DateTime when) async {
  // persist-before-arm: the store is the source of truth, the OS mirrors it
  await _store.saveScheduled(task.id, when);
  await _plugin.schedule(task.id, when);
}
```

State async behaviour, what a method writes or mutates, and every exception it can throw. If a function returns a typed result instead of throwing, say which outcomes it can return. If a function is **total** (returns for every input, never throws), say so — it is a real guarantee callers rely on.

## Library docs and the public API file

```dart
/// Domain-independent telemetry gate: a versioned event allowlist, a consent
/// gate, attribute redaction, and an explicit-action-only diagnostic export.
///
/// Holds no raw sensor, health, or content payload — this purity is what lets
/// the package guarantee such data cannot leave the device through it.
library;

export 'src/consent_gate.dart';
export 'src/event_allowlist.dart';
```

The `///` attaches to the `library;` directive. Never leave a `///` dangling above an `export` or a blank line. (The package descriptions already in each `pubspec.yaml` are a good starting point for the library doc.)

## Restating the invariant at the enforcement point

Where a symbol *enforces* a rule, document the rule as part of its contract and pin it in-body at the one line that upholds it:

```dart
/// Failure modes of a checkout. Switched exhaustively by the caller, so a new
/// case is a compile error at every call site.
sealed class CheckoutFailure {
  /// Const base constructor, so subclasses can be `const`.
  const CheckoutFailure();
}

/// The account balance was below the order total; no charge was made.
final class InsufficientFunds extends CheckoutFailure {
  /// Creates an [InsufficientFunds] failure.
  const InsufficientFunds();
}

/// Observable state of the current order; mutated only through this model.
class OrderModel extends ChangeNotifier {
  /// Creates a model that persists through [repository].
  OrderModel(this.repository);

  /// Storage the model commits to before publishing any state change.
  final OrderRepository repository;

  /// Adds [item] and recomputes the total.
  ///
  /// Persists via [repository] before notifying listeners, so a mid-write crash
  /// cannot surface a line the store never saw.
  Future<void> addItem(Item item) async {
    // persist-before-publish: published state is always a state the store holds
    await repository.append(item);
    _order = _order.withItem(item);
    notifyListeners();
  }
}
```

## Anti-patterns

- **`/** JavaDoc-style */`** — dartdoc ignores it; the symbol reads as undocumented.
- **Restating the name** — `/// Gets the id.` on `String get id`. Delete it or add units, ranges, and invariants.
- **A paragraph before the one-sentence summary** — the first sentence must stand alone in list views.
- **Narrating mechanics in-body** — `// loop over items`, `i++ // increment`. Explain *why*, or delete.
- **A magic constant with no source** — a bare `3` for a cap with no comment saying where the number is defined.
- **Stale docs** describing pre-refactor parameters, or an invariant comment left on code that no longer honours it.
- **Commented-out code** "just in case" — version control remembers. **`// TODO` with no owner** — write `// TODO(name): reason` or nothing.
- **Documenting private trivia** while a public method sits undocumented.
- **A dangling `///`** above a blank line or an `export`.
- **Banner or ASCII-art comment dividers** that bloat files; rely on structure and naming.

## Definition of done

- [ ] Every public declaration reachable from the touched package's public API file has a `///` doc; the first line is a standalone sentence ending in a period.
- [ ] Method and function docs start with a verb; boolean getters start with "Whether".
- [ ] Units, ranges, nullability, throws or typed outcomes, and side effects are documented where they exist.
- [ ] Identifiers are cross-linked with `[brackets]`; no broken references.
- [ ] Enforced invariants are restated at their enforcement points; magic constants cite their source.
- [ ] No restated-name docs, no narrating `//`, no commented-out code, no ownerless TODO, no JavaDoc blocks.
- [ ] Each public API file has a `library;` doc; no dangling doc comments.
- [ ] Every comment the diff touched is still true.
- [ ] `dart analyze` is clean, and `dart doc` generates without warnings for the touched package.

## Related skills

- `dart3-idioms-and-coding-standards` — the sealed-type and total-function guarantees the docs promise.
- `error-handling-typed-results` — the typed outcome contract a method doc must state.

## References

- Effective Dart: Documentation — https://dart.dev/effective-dart/documentation
- `dart doc` tool — https://dart.dev/tools/dart-doc
- Linter rules — https://dart.dev/tools/linter-rules (`public_member_api_docs`, `dangling_library_doc_comments`, `comment_references`, `slash_for_doc_comments`)
- Developing packages and plugins — https://docs.flutter.dev/packages-and-plugins/developing-packages
