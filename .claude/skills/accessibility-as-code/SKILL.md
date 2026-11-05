---
name: accessibility-as-code
description: >-
  Accessibility as a correctness property authored into each Motion Core widget (for example
  motion_account pages): Semantics(button/label) or ExcludeSemantics on every node, platform
  accessibility state read from MediaQuery, never MediaQuery.withClampedTextScaling,
  textScaleFactor, FittedBox or TextOverflow.ellipsis to fit a label, non-colour redundant
  channels for every state, contrast against composited backgrounds (4.5:1 body, 3:1 large), 44px
  single-tap targets, OrdinalSortKey traversal, honouring boldText and reduce-motion, and text
  routed through the package's own text mechanism. Use when adding a tap target, an Icon or Image,
  reaching for a clamp or FittedBox to make text fit, encoding state via colour, or reviewing any
  view for screen-reader, switch, or low-vision support.
---

# Accessibility is a coding standard, not a checklist (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `accessibility-as-code` skill (see `../LICENSE-flutter-skills.md`).

Accessibility is authored into the widget as you write it — the same tier as "the button actually works." There is no lint for any of this: `flutter_lints` ships zero accessibility rules. Enforcement is the widget itself, review of your own diff, and widget tests. Applies to every interactive view, every `Icon` / `Image`, every state, and every colour choice in Core's UI packages (today `motion_account`'s account, identity, and membership pages) and in any widget a Core package hands to a consuming app.

Testing mechanics (guideline matchers, overflow matrix, honest conformance limits) live in `widget-golden-and-a11y-testing`; this skill is the authoring discipline.

## Non-negotiable rules

1. **Every interactive node gets `Semantics(button: true, label: ...)`.** A raw `GestureDetector` with no semantics silently locks out every screen-reader and switch user. Correct semantics make TalkBack, VoiceOver, Switch Access, and Switch Control work for free; it is definition-of-done, never a backlog ticket. Prefer built-in controls (`TextButton`, `IconButton`, `ListTile`), which already carry semantics and a minimum target size.
2. **Every `Icon` / `Image` gets a `semanticLabel`, or is wrapped in `ExcludeSemantics`** because it is decorative. There is no third option — an unlabelled `Icon` is invisible to a screen reader.
3. **Read accessibility state from `MediaQuery` at build time, never from app state.** `MediaQuery` is an `InheritedWidget` with correct-by-construction invalidation; copying it into a notifier trades a compiler-guaranteed rebuild for a frame of staleness in the one area where being wrong is total failure.
4. **Never `MediaQuery.withClampedTextScaling`, never `textScaleFactor`.** Both are clamping hacks that silently defeat the text-scale matrix while contrast and tap-target checks still pass green. Enforce with a source grep (see Anti-patterns).
5. **Never `FittedBox`, a computed `fontSize`, or `TextOverflow.ellipsis` to make a label fit.** They turn "doesn't fit at 200%" from a loud test failure into truncated or shrunk text on a device. Build flexible heights and let text wrap.
6. **Never encode state through colour alone.** Pair every stateful signal with at least one non-colour channel — icon, text label, shape or pattern, position. Colour-only state is invisible under `invertColors`, grayscale colour correction, and to every screen-reader user.
7. **Measure contrast against the composited background in both themes** — body text and meaningful icons ≥ 4.5:1 (AA 1.4.3), large text ≥ 3:1 (AA). Large text never has to clear a higher bar than body. Never test against the nominal token colour when a fill, gradient, or translucency sits between text and surface.
8. **Every interactive target is ≥ 44×44 logical pixels and single-tap.** No long-press or precise-gesture-only affordances; hand-off and motor-impaired use demand a large, forgiving target.
9. **Traversal order is authored with `sortKey`, never inherited from layout** — visual position optimised for the thumb actively pessimises linear screen-reader and switch scanning.
10. **Honour `boldText` and reduced motion; keep haptics through reduced motion.** Hardcoding `fontWeight` throws the setting away. Read `MediaQuery.disableAnimationsOf(context)` and collapse motion accordingly; an animation that still conveys meaning with no reduced-motion path is a bug.
11. **All user-visible text, including every semantic label, comes from the package's own text mechanism — never a hard-coded literal.** In `motion_account` that is `MotionAccountLocalizations.of(context).text(MotionAccountString.<key>)` (with `MotionAccountLocalizations.delegates` and `supportedLocales` wired into the app); any new string gets an enum key and a translation for every supported locale. A package without UI of its own takes strings from its caller and ships none.

## Where accessibility state comes from

Read platform accessibility state from `context`, app state from your model:

```dart
@override
Widget build(BuildContext context) {
  final boldText = MediaQuery.boldTextOf(context);
  final highContrast = MediaQuery.highContrastOf(context);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  // textScaler is deliberately NOT read and NOT clamped. Text scales itself.
  ...
}
```

`MediaQuery.highContrastOf` is **iOS-only and always false on Android** (`AccessibilityFeatures.highContrast` is documented "Only supported on iOS"). Read the flag opportunistically; never gate anything on it, and provide an in-app control as the mechanism that works everywhere. `invertColors` is a system compositing filter — never reimplement it; just never encode meaning in colour alone, or an inverted screen changes what the UI says.

## The tap target, wrong and right

```dart
// WRONG — invisible to a screen reader, a clamping hack, a hidden overflow bug
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.onTap});
  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(   // (1) BANNED clamp
      maxScaleFactor: 1.3,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            const Icon(Icons.star),             // (2) no semanticLabel
            Text(
              item.title,                        // (3) no Semantics button role
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,   // (4) ignores boldText
              ),
              overflow: TextOverflow.ellipsis,   // (5) HIDES the overflow bug
            ),
          ],
        ),
      ),
    );
  }
}
```

```dart
// RIGHT — semantics authored, text free to scale, target ≥ 44px, non-colour state
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.onToggle, required this.copy});
  final Item item;
  final void Function(String id) onToggle; // resolve at tap from the stable id
  final ItemTileCopy copy; // localized strings supplied by the owning text mechanism

  @override
  Widget build(BuildContext context) {
    final bold = MediaQuery.boldTextOf(context);
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      button: true,
      label: item.title, // display label, not a sentence
      // Non-colour state: read out AND flip an icon (below), never colour alone.
      value: item.isSelected ? copy.selected : copy.notSelected,
      sortKey: OrdinalSortKey(item.priority.toDouble()), // priority, not layout
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // whole cell is the target
        onTap: () => onToggle(item.id), // stable id, no stale-closure capture
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: ExcludeSemantics( // face already announced above
            child: Row(
              children: [
                Icon(item.isSelected ? Icons.check_circle : Icons.circle_outlined),
                Text(
                  item.title, // no ellipsis, no FittedBox
                  style: theme.textTheme.bodyLarge!.copyWith(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

The `label` is the **display label**, never a longer vocalisation — nothing in the type system distinguishes the two `String`s, so a scanning user hears the whole sentence on every step unless you keep them separate. Resolve the action from the immutable id **at tap time**; capturing a mutable field into the closure fires the stale value on a fast re-tap.

## Text scale: the instinct is the bug

The reflex when a fixed layout overflows at 200% is to disable text scaling for stability. That reflex is the defect. Auto-shrinking — `FittedBox`, computed `fontSize`, `maxLines` plus `ellipsis` — is the identical bug in disguise: the layout stays tidy and the user's setting stops working, silently, with every guideline still green.

- Honour `MediaQuery.textScalerOf(context)` by **not touching it**. Flutter text widgets already scale.
- `textScaleFactor` is deprecated in favour of `TextScaler` precisely to support Android's nonlinear scaling; its use is almost always a clamp.
- Build **intrinsic, flexible heights**; let text wrap to as many lines as it needs. Hero and display sizes may cap their own growth and **wrap to a second line rather than truncate**.
- Reflow horizontal rows (chip bars, toolbars) at accessibility text sizes instead of clipping.
- Use `FontFeature.tabularFigures()` wherever numbers change or align so they do not reflow or jitter.
- Let overflow **scream in tests**. A red overflow stripe in a widget test is the feedback loop; a truncated word on a device is a failure nobody reports.

## Never state through colour alone

A real state — selected, active, pending, complete, error, disabled — is knowable without colour. Encode it redundantly across independent channels:

- **Icon or glyph** whose *shape* differs per state (legible in grayscale).
- **Text label** — the word for the state, routed through the text mechanism.
- **Shape, pattern, or outline** — a stripe, keyline, or notch.
- **Position** — sort the item that needs attention to the top under a header.

Expose the state to assistive technology through `Semantics` — a `value` or `hint`, or a `liveRegion` for a transient announcement — never through a luminance step alone:

```dart
Semantics(
  liveRegion: true, // announced when it changes, e.g. "Sync complete"
  label: statusLabel(status), // the word, not the colour
  child: StatusBadge(status: status), // icon + label + shape; colour is decoration
)
```

Pair visual feedback with `HapticFeedback.selectionClick()` so confirmation survives reduced motion and low vision. Guard any latched "active" visual with a timeout that force-clears it — a stuck state is both a visual lie and a stale semantic value.

## Contrast against the composited background

Verify contrast against what the pixel actually composites to, in **both** light and dark themes, not against the nominal token:

- Body text and meaningful icons or outlines ≥ **4.5:1** (AA 1.4.3); push to **7:1** (AAA 1.4.6) for body where you can reach it. Large text ≥ **3:1** (AA) or **4.5:1** (AAA).
- Never render a critical number or label on a gradient, translucent glass, or chip fill; put it on an opaque surface.
- Any accent fill that carries text must be pre-paired with a foreground that clears 4.5:1 on *that* fill, re-verified in dark mode (dark values are hand-tuned, never auto-flipped).
- Avoid the red/green trap: a neutral value is neutral ink, "success" is green **plus a check glyph plus the word**, danger-red appears only on destructive actions.
- Verify the whole UI in a grayscale pass and a colour-vision-deficiency simulation.

## Traversal order is a design decision

Layout optimised for thumb reach (highest-priority controls low and central) combined with Flutter's default row-major traversal makes the most important control the last thing a linear scanner reaches. Decouple traversal from position with one argument:

```dart
Semantics(
  sortKey: OrdinalSortKey(item.priority.toDouble()), // authored from priority
  ... )
```

Assert `sortKey` order equals priority order (not layout order) in a test. Know the limit: Flutter publishes no Switch Access support statement and no API simulates scanning, so this is a regression guard on *intent*; real-device passes with TalkBack, VoiceOver, and Switch Access are the only conformance evidence. Touch, switch, and screen reader are three different channels: design for all three or state plainly which one was dropped.

## Anti-patterns

- **`MediaQuery.withClampedTextScaling` / `textScaleFactor`** — the one-line "fix" a future contributor reaches for when an overflow test goes red. Ban with `grep -rn "withClampedTextScaling\|textScaleFactor" packages/*/lib` in review.
- **`FittedBox` / computed `fontSize` / `ellipsis` on a real label** — the same bug in disguise.
- **Unlabelled `Icon` / `Image`** — invisible to a screen reader; label it or `ExcludeSemantics` it.
- **Copying `boldText`, `highContrast`, or `disableAnimations` into a notifier** — one frame stale.
- **Gating anything on `highContrastOf`** — always false on Android; it silently disables your feature on the majority platform.
- **Colour as the only channel for a state** — dies under `invertColors`, grayscale mode, and screen readers.
- **Capturing a mutable field into an `onTap` closure** — fires the stale value on a fast re-tap; resolve from the stable id at tap time.
- **A precise-gesture-only or long-press-only affordance** — excludes motor-impaired and hand-off use; provide a ≥44px single tap.
- **A hard-coded string in a label, hint, or announcement** — bypasses localization and right-to-left handling.
- **`containsSemantics(...)` in tests** — deprecated; use `isSemantics(...)`.

## Definition of done

For any widget with a tap target or state:

1. `Semantics` node with `button: true`, a display-only `label`, and an authored `sortKey` (or a built-in control that already provides them).
2. Every `Icon` / `Image` labelled or explicitly `ExcludeSemantics`.
3. No clamp, no `FittedBox`, no `ellipsis` on a real label; renders at `TextScaler.linear(2.0)` without overflow.
4. `boldText` honoured; no hardcoded `fontWeight` on user-facing text.
5. Every state carries a non-colour channel; transient state uses `liveRegion` or `value`; feedback includes a haptic.
6. Contrast verified against the composited background in both themes (≥4.5:1 body, ≥3:1 large) and in a grayscale pass.
7. Interactive targets ≥ 44×44 and single-tap.
8. All visible and semantic text comes from the package's text mechanism, with every supported locale filled in.
9. A test asserting the semantics with `isSemantics(...)` and traversal against priority order.

## Related skills

- `widget-golden-and-a11y-testing` — the harness, overflow matrix, guideline matchers, and honest conformance limits that verify this authoring.

## References

- Flutter accessibility: https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility
- `Semantics` widget: https://api.flutter.dev/flutter/widgets/Semantics-class.html
- `MediaQueryData` accessibility flags: https://api.flutter.dev/flutter/widgets/MediaQueryData-class.html
- `TextScaler`: https://api.flutter.dev/flutter/painting/TextScaler-class.html
- `OrdinalSortKey`: https://api.flutter.dev/flutter/semantics/OrdinalSortKey-class.html
- WCAG 2.2 contrast (1.4.3 / 1.4.6): https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
