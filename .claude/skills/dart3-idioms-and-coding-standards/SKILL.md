---
name: dart3-idioms-and-coding-standards
description: >-
  Which Dart 3 construct each Motion Core declaration earns: sealed class + exhaustive switch with
  no default:/case _:, the three class modifiers (sealed, final, abstract interface class) and
  skip the rest, records as intra-layer tuples only, hand-written immutable value types (final
  fields, const constructor, explicit stable identity, == / hashCode only when needed), total
  non-throwing domain functions, illegal states unrepresentable, firm method/file/nesting limits,
  and no late / ! / dynamic honesty dodges. Dart SDK floor is 3.9. Use when authoring or reviewing
  any Dart type or declaration: class vs enum vs record, adding a switch or if-case, writing
  copyWith or ==/hashCode, deciding identity, keeping a domain function total, or hitting a
  length or nesting limit.
---

# Dart 3 idioms and coding standards (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `dart3-idioms-and-coding-standards` skill (see `../LICENSE-flutter-skills.md`).

Modern Dart 3.x, value-type-first, total functions for domain logic. A language feature earns its place when it converts a runtime silence into a **compile error**; everything else is decoration. This skill governs how each declaration is *typed, named, kept immutable, and kept total*; the error-handling architecture that rides on top of these mechanics lives in `error-handling-typed-results`.

**Dart SDK floor is 3.9.** The pure-Dart packages (`motion_core`, `motion_content`) declare `sdk: ^3.9.0`; the Flutter packages declare `^3.11.0`. Write code that compiles on 3.9 wherever the package declares it, and check the package's `pubspec.yaml` before using a newer language feature. No `--enable-experiment` flag, no macros, no primary constructors.

## Non-negotiable rules

1. **A `switch` on a sealed type or enum carries no `default:` and no `case _:`.** A wildcard makes the switch compile forever, discarding the one compile-time guarantee the type exists for — adding a variant then falls through silently at runtime. Exhaustiveness is the whole product.
2. **Reach for exactly three class modifiers; ignore the rest.** `sealed class` for a closed variant set the compiler must exhaust; `final class` for every concrete leaf; `abstract interface class` for a seam a test fake implements. Default concrete types to `final`. Skip `base` and `extension type`.
3. **Model closed sets of *individually actionable* cases as a `sealed` hierarchy, and payload-free closed sets as an `enum`.** Start with `enum`; convert to `sealed` + `final class` the moment any member needs a field. Never bolt nullable fields onto an enum for data that applies to only some members.
4. **Records never cross a layer boundary.** A record is a nameless, positional shape — fine for an ephemeral multi-value return *inside one layer*. The moment a shape is returned from a repository, stored, or passed to a widget constructor, it is a named class.
5. **Domain values are immutable: `final` fields, a `const` constructor where legal, value equality, and `copyWith` to derive.** Prefer `final` locals and `const` constructors everywhere the analyzer allows.
6. **Identity is an explicit stable field, never equals-on-all-fields.** A value type used in a list or as a map key carries `final String id` (or a typed id). Deriving identity from all fields collapses two distinct entities that happen to share values.
7. **Make illegal states unrepresentable.** Encode a discriminated choice as a sealed variant, not as a bag of nullable fields where only one is ever set. If the type cannot express the bad state, no branch has to guard against it.
8. **Domain functions are total — they never throw.** Every pure function returns a value for every input; uncertainty is an explicit output (a clamped value, a "no result within N steps" outcome, a low-confidence flag). Programmer invariants use `assert` (stripped in release), never `throw`. Recoverable I/O failures return a typed result — see `error-handling-typed-results`.
9. **No honesty dodges: no `late` to dodge nullability, no `!` on a value that matters, no `dynamic` or `Map<String, dynamic>` as an ad-hoc model.** Each hides a runtime failure the type system would otherwise force you to handle. Use `?.`, `??`, and promotion for null, and a typed model for structured data. (A `Map<String, Object?>` at a JSON or channel boundary is fine *if* a typed parser converts it immediately.)
10. **Effective Dart casing, verbatim; constants are `lowerCamelCase`.** `UpperCamelCase` types, extensions, and enums; `lowercase_with_underscores` files, directories, and import prefixes; `lowerCamelCase` variables, parameters, methods, and **constants** (`maxItems`, never `MAX_ITEMS`); acronyms over two letters capitalize as a word (`JsonMap`, `HttpClient`). A file is named for its primary declaration.
11. **Respect these complexity limits as firm defaults:** method ≤ ~30 lines, `build()` ≤ ~80, file ≤ ~300, class public API ≤ ~10 members, positional parameters ≤ 3, **logic nesting ≤ 3**. Widget build trees legitimately nest deeper: **widget build nesting ≤ 5** is the one explicit exception. These are refactor prompts, not laws — a cohesive overrun (a single state machine scattered across five fragments is worse) is justified in the PR.
12. **Hand-write immutable value types; no code generation for them.** Core packages carry no `build_runner` or generator dependency. For a value type write `@immutable` (from `package:meta`, or the Flutter foundation library in Flutter packages), a `const` constructor, `final` fields, a hand-written `copyWith` when derivation is needed, and manual `==` / `Object.hash` only when the type is a map key or set member. Do not add `equatable`, `fpdart`, `dartz`, or any functional-`Either` package (an `Either` erases exhaustiveness), and do not add a generator for boilerplate without a recorded decision.

## Sealed classes: the load-bearing idiom

Model a closed set of individually actionable cases as one sealed hierarchy in one file. `sealed` requires every subtype to live in the same library, so the file **is** the closed set and the compiler enforces it.

```dart
sealed class SyncOutcome {
  const SyncOutcome();
}

final class SyncApplied extends SyncOutcome {
  const SyncApplied(this.appliedCount);
  final int appliedCount;
}

final class SyncSkipped extends SyncOutcome {
  const SyncSkipped(this.reason);
  final String reason;
}
```

Switch with **no** `default:` — adding a variant is then a compile error until every site handles it:

```dart
// RIGHT — exhaustive, no wildcard.
switch (outcome) {
  case SyncApplied(:final appliedCount):
    report('applied $appliedCount');
  case SyncSkipped(:final reason):
    report('skipped: $reason');
}
```

A dropped branch reports as `non_exhaustive_switch_statement` from `dart analyze` **and** fails compilation. Never suppress it.

## Class modifiers: reach for three

| Intent | Declaration |
|---|---|
| A closed set of variants the compiler must exhaust | `sealed class` (implicitly abstract; not constructible or implementable outside its library) |
| A concrete leaf — a variant, a service implementation, a value type | `final class` |
| A seam a test fake must satisfy | `abstract interface class` |

Default every concrete type to `final class`: it blocks both extension and implementation, so no subclass silently inherits half a behaviour and no test accidentally `implements` a concrete class to pick up its fields. `abstract interface class` says "implement me, don't extend me" — exactly the contract a fake wants; a bare `abstract class` permits `extends`, and an inherited default on a service interface is how a fake ends up quietly calling the real implementation. Skip `base` (it polices a library-boundary invariant) and `extension type` (an explicitly unsafe abstraction — the representation stays reachable).

## Records: where they win, where they cost

Use a record for an ephemeral multi-value return **inside a single layer**: `(int row, int col)` as a local coordinate is ideal — structural equality for free, no class, no codegen. Name the fields once a record survives more than a few lines: `({int row, int col})` reads at the use site; `(int, int)` is a swap bug the compiler cannot see.

```dart
// Intra-layer only. Two same-typed positional fields = a latent swap bug.
({int page, int size}) nextPage(({int page, int size}) current) =>
    (page: current.page + 1, size: current.size);
```

Do not `typedef` a record shape into existence to dodge the class decision — a named shape used across files wants a class.

## Enum or sealed

Start with an `enum` when the set is closed and every member is payload-free — a display category, a mode. Enums get the same compiler exhaustiveness in a switch and cost one line each. Convert to `sealed` + `final class` the moment any member needs a field.

```dart
enum OrderStatus { draft, submitted, shipped, cancelled }

// A member needs data -> sealed, not an enum with parallel nullable fields.
sealed class Payment {
  const Payment();
}
final class Cash extends Payment { const Cash(); }
final class Card extends Payment {
  const Card(this.last4);
  final String last4;
}
```

## Switch expressions and if-case

Prefer a switch **expression** when every arm produces a value and no arm has a statement body — exhaustive by construction, cannot fall through:

```dart
final label = switch (status) {
  OrderStatus.draft => 'Draft',
  OrderStatus.submitted => 'Submitted',
  OrderStatus.shipped => 'Shipped',
  OrderStatus.cancelled => 'Cancelled',
};
```

Use a switch **statement** when arms perform effects; do not contort effects into an expression with a `void` sink. Use `if (x case Pattern)` for a single interesting shape where a switch would be one real branch plus a dead one — but **never** `if-case` on a sealed type, which silently reintroduces the non-exhaustive hole a switch would have caught.

## Immutable value types and identity

A few lines replace a code generator. Hand-write `==` / `hashCode` only when the type is a map key or set member; carry a stable `id` for identity in lists.

```dart
@immutable
final class Task {
  const Task({required this.id, required this.title, required this.done});

  final String id; // identity — NOT derived from title/done
  final String title;
  final bool done;

  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  @override
  bool operator ==(Object other) =>
      other is Task && other.id == id && other.title == title && other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);
}
```

## Total domain functions

A pure function returns for every input. Uncertainty is a value; a programmer invariant is an `assert`.

```dart
/// Total: clamps rather than throwing on an out-of-range page.
int clampPage(int requested, int pageCount) {
  assert(pageCount >= 1, 'pageCount must be positive'); // programmer invariant
  if (requested < 0) return 0;
  if (requested >= pageCount) return pageCount - 1;
  return requested;
}
```

## Anti-patterns

- `default:` or `case _:` on a sealed type or enum — discards exhaustiveness; a new variant falls through at runtime instead of failing to compile.
- `if (x case SomeVariant())` on a sealed type — reintroduces the non-exhaustive hole a `switch` catches.
- An `enum` with a constructor and nullable fields that apply to only some members — every access is a null-check the compiler cannot reason about; use `sealed` + `final class`.
- A record returned from a repository, stored, or passed across a widget constructor — a nameless positional shape as a domain type; make a class.
- A `ChangeNotifier` used as a mutable domain model — domain values are immutable; mutate through a model that exposes immutable state.
- Identity derived from `==`-on-all-fields — two entities sharing values collapse into one; carry a stable `id`.
- `late Foo foo;` or `foo!.value` to dodge a null, `Map<String, dynamic>` as a model — hides a runtime failure; use `?.`, `??`, promotion, and a typed model.
- `throw` from a pure domain function to signal a normal outcome — return the outcome; `assert` is for programmer invariants only.
- `const MAX_ITEMS`, `class JSONModel`, `final s = 3;` — SCREAMING_CAPS, mis-cased acronym, abbreviation; use `maxItems`, `JsonModel`, full words.
- `Widget _buildHeader() => ...` — rebuilds with its parent and cannot be `const`; extract a `const` widget class.
- Adding `equatable`, `fpdart`, `dartz`, a code generator, or an `--enable-experiment` flag — redundant weight or an exhaustiveness-erasing `Either`; hand-write the few lines.

## Definition of done

- [ ] Every `switch` on a sealed type or enum is exhaustive with no `default:` / `case _:`.
- [ ] Concrete types are `final class`; seams are `abstract interface class`; closed sets are `sealed` / `enum`; no `base`, `extension type`, or experiment flags.
- [ ] Closed actionable sets are `sealed` + `final class`; payload-free sets are `enum`; no nullable-field-tagged enums.
- [ ] Records stay intra-layer; every cross-boundary shape is a named class.
- [ ] Domain values are immutable (`final` fields, `const` constructor where legal, `copyWith`); identity is a stable `id`.
- [ ] Illegal states are unrepresentable (sealed or enum unions, not nullable bags).
- [ ] Domain functions are total — they return uncertainty and never throw; invariants use `assert`.
- [ ] No `late` / `!` / `dynamic` / `Map<String, dynamic>` honesty dodge on a value that matters.
- [ ] Effective Dart casing verbatim; constants `lowerCamelCase`; file named for its primary declaration.
- [ ] Code compiles on the package's declared SDK floor (3.9 for the pure-Dart packages).
- [ ] Complexity limits respected, or a cohesive overrun is justified in the PR; `dart analyze` is clean.

## Related skills

- `error-handling-typed-results` — the sealed result and failure spine that rides on these mechanics.
- `service-boundary-and-native` — `abstract interface class` seams and typed outcomes.
- `dartdoc-conventions` — documenting the sealed hierarchies and total-function guarantees this skill creates.

## References

- Effective Dart (Style / Documentation / Usage / Design): https://dart.dev/effective-dart
- Class modifiers: https://dart.dev/language/class-modifiers
- Patterns (destructuring, `if-case`): https://dart.dev/language/patterns
- Branches — exhaustiveness: https://dart.dev/language/branches#exhaustiveness-checking
- Records: https://dart.dev/language/records
- Sound null safety: https://dart.dev/null-safety
