---
name: widget-golden-and-a11y-testing
description: >-
  Widget-tier test discipline for Motion Core's Flutter packages (for example motion_account
  pages): one pumpApp harness that pins tester.view.physicalSize x devicePixelRatio and layers
  MediaQuery (textScaler/boldText/accessibleNavigation) above MaterialApp, an overflow net that
  never suppresses (one testWidgets per device x scale x bold tuple), a computed
  getSize/getRect fit gate instead of goldens, pure-Dart WCAG contrast on colour VALUES, and
  honest limits on meetsGuideline. Goldens are optional and not used in Core today. Use when
  writing a test support harness, calling pumpWidget/pumpApp, chasing an "overflowed by N
  pixels" failure, reaching for takeException/FittedBox/withClampedTextScaling, or writing an
  accessibility test with isSemantics/meetsGuideline.
---

# Widget and accessibility testing (Motion Core)

Adapted for Motion Core from the MIT-licensed Flutter-Skills `widget-golden-and-a11y-testing` skill (see `../LICENSE-flutter-skills.md`).

One harness pins the surface; layout and accessibility are asserted by **computed geometry on the real widget tree**, not by blessed pixels. This skill covers the widget tier (packages that use `flutter_test`, e.g. `motion_account`); for pure-logic and notifier tiers see `testing-strategy`.

## Non-negotiable rules

1. **Pin the device on every layout or geometry test.** The default widget test surface is **800x600 logical** — wider than any phone. Unpinned, content is about 2x too wide, everything fits, the suite is green, and the shipped phone is broken. Call `useDevice(...)` first, `pumpApp(...)` second.
2. **`physicalSize` is in PHYSICAL pixels — always multiply by DPR.** `view.physicalSize = Size(320, 640)` at the default DPR 3.0 is a 107x213 logical surface. Set `devicePixelRatio`, then `physicalSize = logical * dpr`, then `addTearDown(view.reset)` — a leaked size poisons every later test in the file.
3. **Layer `MediaQuery` ABOVE `MaterialApp`, built from `.copyWith`.** `MaterialApp` inserts no `MediaQuery` of its own; a bare `MediaQueryData()` zeroes the view-derived size the device just pinned, so the test measures a 0x0 screen and passes.
4. **`pump()`, never `pumpAndSettle()` as an animation wait.** `pumpAndSettle` hangs to a 10-minute timeout on an infinite splash, shimmer, or spinner. Use `pump()` for state changes and `pump(duration)` for timer-driven async.
5. **Never suppress overflow.** A `RenderFlex` overflow already **fails** a widget test (it routes through `FlutterError.reportError` and the binding rethrows at test end). Never call `takeException()` to swallow it, never assign `FlutterError.onError`, never copy an `ignoreOverflowErrors` helper, and never `takeException()` in a global `tearDown`.
6. **One `testWidgets` per (device, scale, bold) tuple — never a loop inside a test.** Overflow is reported **once per RenderObject**, so looping scales inside one test silently under-reports every scale after the first. Loop *around* the `testWidgets` call.
7. **Assert the fit, not just the absence of overflow.** A clipped `Text` reports nothing. `takeException(), isNull` is necessary but not sufficient; add a `getSize`/`getRect` assertion that the label fits its computed cell.
8. **Prefer computed geometry over goldens for layout.** Assert cells in a row share a `top` and cells in a column share a `left` (`moreOrLessEquals`, `epsilon: 0.5`); assert tap targets with a `getSize` loop. These fail with a sentence a human can act on. A blessed screen of clipped, unreadable text passes forever.
9. **Assert contrast on colour VALUES in pure Dart, never on pixels.** `meetsGuideline(textContrastGuideline)` screenshots and histograms the layer, and white text on `#FAFAFA` **passes** (an open Flutter defect). A pure-Dart WCAG test over the theme's colours cannot false-pass. For a state pair distinguished only by chroma, assert the luminance contrast between the two state colours directly.
10. **`await expectLater(...)` for `meetsGuideline`** — it returns an `AsyncMatcher`; a plain `expect()` looks right and asserts nothing. Keep the built-in guidelines as advisory tripwires; geometry and pure-Dart contrast tests are the gate.
11. **Never clamp `TextScaler`.** `withClampedTextScaling`, `textScaleFactor`, and `FittedBox` defeat the matrix while contrast and tap-target checks stay green, and override the user's own OS setting. Fix the layout, not the text.

## The harness — one file, imported by every widget test

Put a `Device` value type and a `pumpApp` extension in the package's `test/support/harness.dart`. Pass the widget under test (and any inherited wrappers it needs) in explicitly so an unprovided dependency fails loudly.

```dart
class Device {
  const Device(this.name, this.logicalSize, this.dpr);
  final String name;
  final Size logicalSize;
  final double dpr;

  // Name presets by measured size, not a marketing model.
  static const compact = Device('compact_320', Size(320, 640), 2.0);
  static const small = Device('small_360', Size(360, 800), 3.0);
  static const medium = Device('medium_412', Size(412, 915), 2.625);
  static const all = <Device>[compact, small, medium];
}

extension TestHarness on WidgetTester {
  void useDevice(Device d) {
    view.devicePixelRatio = d.dpr;
    view.physicalSize = d.logicalSize * d.dpr; // physical px — multiply by DPR
    addTearDown(view.reset); // one call; nothing forgotten
  }

  Future<void> pumpApp(
    Widget home, {
    TextScaler textScaler = TextScaler.noScaling,
    bool boldText = false,
    bool accessibleNavigation = false,
  }) async {
    await pumpWidget(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // copyWith, NOT MediaQueryData()
            textScaler: textScaler,
            boldText: boldText,
            accessibleNavigation: accessibleNavigation,
          ),
          child: MaterialApp(home: home),
        ),
      ),
    );
    await pump(); // one frame; never pumpAndSettle
  }
}
```

If the page reads text from a localization delegate (for example `MotionAccountLocalizations.delegates` in `motion_account`), add those delegates and a supported locale to the `MaterialApp` in the harness.

## The overflow + fit matrix

`Device.all` x `[1.0, 1.3, 1.5, 2.0, 3.0]` x `[false, true]` bold = one `testWidgets` per tuple. `TextScaler.linear` is a deliberate over-approximation (Android 14+ scales large text *less*): conservative, not device-faithful. 1.3 and 1.5 are included because nonlinear device scaling makes the mid-range the non-obvious part. `boldText` only widens glyphs when a real proportional font is loaded; under the default Ahem test font every glyph is a fixed em-square, so load the app's real fonts in `setUpAll` or the bold axis is inert.

```dart
for (final device in Device.all) {
  for (final scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
    for (final bold in const <bool>[false, true]) {
      testWidgets('no overflow @ ${device.name} x$scale${bold ? ' bold' : ''}',
          (tester) async {
        tester.useDevice(device);
        await tester.pumpApp(const PageUnderTest(),
            textScaler: TextScaler.linear(scale), boldText: bold);
        // Explicit for a readable message; the binding also rethrows at test end.
        expect(tester.takeException(), isNull,
            reason: 'content overflowed at ${device.name} x$scale');
      });
    }
  }
}
```

The two overflow classes and the fit assertion:

- **Reported overflow** (`RenderFlex`) fails the test on its own — do not suppress it.
- **Silent clipping** (a `Text` in a constrained box) reports nothing. Assert the label's rect lies inside its cell's rect:

```dart
testWidgets('label fits its cell', (tester) async {
  tester.useDevice(Device.compact);
  await tester.pumpApp(const PageUnderTest(), textScaler: TextScaler.linear(2.0));
  final cell = tester.getRect(find.byKey(const ValueKey('row_0')));
  final label = tester.getRect(find.byKey(const ValueKey('row_0_label')));
  expect(cell.contains(label.topLeft) && cell.contains(label.bottomRight), isTrue,
      reason: 'label $label escaped cell $cell at 2.0x');
});
```

The four wrong fixes for a red matrix, all banned: wrapping in `FittedBox`, `TextOverflow.ellipsis` on a real label, clamping the `TextScaler`, and swallowing the exception. Give the content flexible height and let text wrap.

## The accessibility gate

Semantics is ON by default in `testWidgets`. Assert the node's role and label directly with `isSemantics` (not the deprecated `containsSemantics`), measure tap targets with an explicit `getSize` loop (the built-in guideline skips every node flush with the view edge), and assert contrast on colour values in pure Dart.

```dart
testWidgets('each item exposes a button labelled by its display name', (tester) async {
  await tester.pumpApp(const PageUnderTest());
  final node = tester.getSemantics(find.byKey(const ValueKey('item_0')));
  expect(node, isSemantics(
    label: 'First item',
    isButton: true,
    hasEnabledState: true,
    isEnabled: true,
    hasTapAction: true,
  ));
});
```

Be honest about limits: Flutter ships a handful of machine-checkable guidelines (one known to false-pass), which cover a small minority of real accessibility. Never claim a suite "tests accessibility". Switch Access and Switch Control cannot be tested automatically at all; real-device passes with TalkBack and VoiceOver are the only conformance evidence.

## Goldens — optional, not used in Core today

Motion Core packages do not use golden tests at present. If one is introduced, keep it narrow: goldens are for glyph shaping, right-to-left mirroring, and numeral rendering that geometry cannot see — never the layout gate.

- Tag every golden `@Tags(['golden'])` and generate blessed files in one pinned environment only.
- Ahem squares are byte-stable across operating systems and prove geometry and mirroring but **not** glyph shaping; a real-font golden proves script joining and numeral glyphs but is host-sensitive, so pin the OS.
- Pump right-to-left goldens under `Directionality(textDirection: TextDirection.rtl, ...)`.
- Block accidental `--update-goldens` in CI; overwriting committed images is a deliberate, reviewed step.

## Anti-patterns

- **Unpinned layout test.** Passes on 800x600, ships a broken 360dp phone.
- **`for` loop over scales inside one `testWidgets`.** Scales 2..n are silently unchecked.
- **`takeException()` in a global `tearDown`.** Clears the pending exception before the binding rethrows and turns the whole overflow net into a no-op.
- **`ignoreOverflowErrors` / `FlutterError.onError = ...` in a layout test.**
- **`FittedBox`, `TextOverflow.ellipsis`, or `withClampedTextScaling` to green a red matrix.**
- **`expect(tester, meetsGuideline(...))` without `await expectLater`.**
- **A tap-target claim resting on `meetsGuideline` alone.** Add the explicit `getSize` loop.
- **A contrast claim resting on `textContrastGuideline`.** Assert the colour ratio in pure Dart.
- **`find.byType(SomeWidget)` for behaviour or geometry.** Couples the test to the class hierarchy; use `find.bySemanticsLabel` for behaviour and `find.byKey` for geometry.
- **A layout golden as the gate.** It blesses whatever shipped, including clipped text.

## Definition of done

- [ ] Every layout or geometry test (and any accessibility test that measures size or position) calls `useDevice(...)` before `pumpApp(...)`.
- [ ] The overflow matrix is one `testWidgets` per (device, scale, bold) tuple; no suppression anywhere in `test/`.
- [ ] A fit assertion (`getSize`/`getRect` inside the computed cell) backs the matrix.
- [ ] Tap targets are measured with an explicit `getSize` loop; `meetsGuideline` is advisory and always awaited via `expectLater`.
- [ ] Semantics asserted with `isSemantics`; the label carries the display name, not internal data.
- [ ] Contrast asserted in pure Dart over theme colour values, looped over every theme.
- [ ] Any golden is tagged, pinned to one environment, and cannot be re-blessed by accident.

## Related skills

- `testing-strategy` — the overall test doctrine this widget tier sits on.
- `accessibility-as-code` — authoring the Semantics, roles, and labels these tests assert.

## References

- Flutter — Widget testing introduction: https://docs.flutter.dev/cookbook/testing/widget/introduction
- Flutter API — `WidgetTester` / `TestFlutterView`: https://api.flutter.dev/flutter/flutter_test/WidgetTester-class.html
- Flutter API — Accessibility guidelines / `meetsGuideline`: https://api.flutter.dev/flutter/flutter_test/AccessibilityGuideline-class.html
- Flutter API — Semantics matchers: https://api.flutter.dev/flutter/flutter_test/matchesSemantics.html
- WCAG 2.2 contrast (1.4.3 / 1.4.6): https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
