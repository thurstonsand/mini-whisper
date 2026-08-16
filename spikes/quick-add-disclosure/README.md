# Quick-add disclosure spike

Standalone AppKit status-item app for [ticket 34](../../docs/wayfinding/finishing-mini-whisper/tickets/34-quick-add-disclosure-spike.md). It imports no MiniWhisper code, persists nothing, and does not ship.

The `QD` menu presents all five candidates together. Each form uses real `NSTextField` first-responder behavior. Submitted values print to stdout.

## Run

```sh
swift spikes/quick-add-disclosure/QuickAddDisclosure.swift
```

Click `QD` in the menu bar. Return submits the active form and prints a line such as:

```text
[QuickAddDisclosure] SUBMIT B CORRECTION heard="ghosty" taught="Ghostty"
```

The default comparison uses the reliable live-resize paths. To repeat the intrinsic-content-size probe used for Part 1, run:

```sh
swift spikes/quick-add-disclosure/QuickAddDisclosure.swift --probe-intrinsic
```

In that mode, expanding B first invalidates its intrinsic content size, waits 150 ms to measure the result, then applies the reliable frame fallback if AppKit did not resize the item.

To show the exact-title native item used for pixel-parity captures:

```sh
swift spikes/quick-add-disclosure/QuickAddDisclosure.swift --measure-parity
```

## Capture

```sh
./spikes/quick-add-disclosure/capture
./spikes/quick-add-disclosure/capture /tmp/quick-add-disclosure.png
```

The script builds and launches a temporary copy, opens `QD` through Accessibility, captures the initial menu, then removes the process and temporary files. Terminal/System Events may need Accessibility permission. The status item must be visible rather than hidden by macOS menu-bar overflow; on the test machine, overflow sometimes assigned the temporary process an off-screen menu coordinate, in which case `screencapture` correctly refuses the region.

## Part 1 verdict: works reliably, with a mechanism caveat

Tested on macOS 26.5.2 (25F84). A view-backed `NSMenuItem` **can change height while its menu remains open and tracking**. The menu window resizes immediately, its status-item edge remains anchored, text fields remain focusable, and tracking continues. No clipping, tracking loss, or tearing was observed.

Three mechanisms were exercised:

- **Explicit view-frame mutation works.** The original A probe changed its item view from 38 → 102 → 132 points while open. The containing menu changed from 338 → 402 → 432 points at the same time. Ten automated open/expand/nested-expand/close cycles produced the expected 402/432-point menu heights every time. The chosen single A now sizes 28 → 124 → 154 points. The frame mechanism is unchanged.
- **An Auto Layout height constraint works.** C changed its own active height constraint from 86 → 116 → 86 points and laid out its subtree. The menu followed from 338 → 368 → 338 points. Ten expand/collapse cycles produced those exact heights every time.
- **Intrinsic-content-size invalidation alone does not work.** B changed its intrinsic height from 64 → 96 points, called `invalidateIntrinsicContentSize()`, marked constraints/layout dirty, and called `menu.update()`. After 150 ms, the hosted view and menu remained at 64 and 338 points. Setting the view frame then resized both immediately. Run `--probe-intrinsic` to see this result in the log.

So the caveat is narrow: AppKit does not consult a custom item view's newly invalidated intrinsic size during tracking. Give the item an explicit frame height, or drive that frame through an active height constraint. No close-and-reopen approximation is needed for A–C on this OS.

## Shared keyboard behavior

The click-to-focus behavior follows the predecessor spike: clicking a visible field starts its field editor, while clicking a custom form's background focuses its first visible field. The menu host window accepts a first responder but never becomes key, so AppKit suppresses the field editor's native insertion caret. Calling `makeKey()` during tracking had no effect; activating the accessory app to force key status dismissed the menu. The spike instead converts the field editor's selected-range rectangle into the active field's local coordinates and installs a one-point blinking layer as that field's child. Keeping the layer inside the field matters: the first version attached a drawing view to the menu window's content root, and AppKit promoted each blink invalidation to the entire composited menu surface, producing a whole-window white flash despite the logged 1×14-point frame. Invalid, non-finite, out-of-field, or degenerate rectangles are now logged and skipped rather than attached. Typing and selection continue to use the real field editor. Tab and Shift-Tab cycle through the fields currently disclosed. Return synchronizes the active field editor, prints the submission, and closes the menu.

For A–D, Escape is consumed by `NSMenu` and dismisses the complete menu hierarchy. `menuDidClose` clears every draft, so this is reliable abort-and-discard behavior, but it cannot mean “collapse one level and keep the menu open.” Vertical arrows surrender text editing to native menu navigation. Native D, E, and ordinary sibling items remain arrow-selectable; custom A–C item views are skipped, as expected for view-backed menu items.

## Model observations

### A. Accordion

A is the selected direction and is again a single `Add to Dictionary…` row. Both one-way disclosures retain emphasized `NSVisualEffectView` selection surfaces.

### Measured native parity

Run with `--measure-parity` to place a native `NSMenuItem` with the exact same title immediately below A. Screenshots were sampled from the menu region with ImageMagick on this machine; coordinates below are screenshot pixels.

Before deterministic correction, A's title bounding box was `x=14…127, y=10…22`; the native reference was `x=16…129, y=40…52`. Accounting for the rows' 28-pixel separation, A was two pixels left and two pixels high. A's selection was `x=5…324, y=10…31` (22 pixels high), versus native `x=5…324, y=33…56` (24 pixels). Dominant selected RGB was `(51,84,179)` versus native `(58,93,194)`. Unselected title RGB was `(220,220,220)` versus `(222,222,222)`; selected title RGB was `(224,229,243)` versus native white `(255,255,255)`.

After correction, A's title is `x=16…129, y=12…24`; native remains `x=16…129, y=40…52`. Their row-relative boxes are identical. A's selection is `x=5…324, y=5…28`; native is `x=5…324, y=33…56`: both are exactly 320×24 at the same row-relative origin. Dominant selection RGB is `(58,93,194)` for both; unselected title RGB is `(222,222,222)` for both; selected title RGB is `(255,255,255)` for both.

The nested disclosure now uses the same measured treatment. Its hover surface sampled `x=5…324, y=70…93`—320×24—with dominant `(58,93,194)`. `Misheard as…` sampled `x=17…97, y=77…86`, a vertically centered row-relative `y=7…16`; selected text was `(255,255,255)` and unselected text `(222,222,222)`. The previous selection surface was six pixels above its button, leaving the glyph at row-relative `y=13…22`; centering their frames fixed the baseline.

The clipping diagnosis changed under measurement. `NSMenu` already supplied the five-pixel outer top inset; the borderless attributed `NSButton` was drawing its glyph at the top of its explicitly constrained bounds rather than vertically centering it. The old one-point button placement therefore put the glyph two pixels above the native baseline. Selection and title geometry are now independent: the selection occupies the native 24-point row surface, while the button begins eight points down to reproduce the native glyph box. The selection remains `.selection` material; a calibrated layer color compensates for the different vibrancy backdrop at the top of this specific menu so its sampled output matches the native reference.

### Form and validation

The expanded form uses the Settings add sheet's exact `Word or phrase` placeholder, retains the one-way `Misheard as…` disclosure, and adds a visible, left-aligned Add button. Both disclosure selection surfaces are full-row hit targets: `hitTest(_:)` routes every point inside the 320×24 surface to the accordion, and `mouseDown(with:)` performs the applicable one-way action. Live clicks six pixels from the menu's left edge—outside the text/field column—expanded both the header and nested disclosure. Revealing correction changes the taught field placeholder to `Correct spelling` and adds `Misspelling`. The Add button always renders fully enabled. Invalid Add or Return applies the chosen 350 ms `CAKeyframeAnimation` across x offsets `0, -7, 7, -5, 5, -3, 3, 0`; it never submits.

Validity is determined by the taught field. Misspelling-only is invalid and shakes. A filled taught field with an empty misspelling is valid even after disclosure and submits as `A VOCABULARY`; both filled submit as `A CORRECTION`. The stdout line names the resulting kind.

Before the shared field editor moves, the form copies its string back, calls `endEditing(_:)` on the old field's cell, and invalidates that field, so inactive values and placeholders remain drawn. The original fix searched only the destination form's own fields. That was a real lifecycle hole exposed by the multi-form harness: the menu window owns one field editor, so moving from A into B left A's cell editing if B could not identify it. Focus transfer now obtains the previous `FormField` directly from the field editor's delegate and ends it regardless of owning form. A live A→B test retained `Cross-form retained` visibly in A while B owned the editor. Production has one quick-add form, but the generalized fix also covers coexistence with any other menu field.

Focus, typing, nested expansion, validation shake, Add, Return, Tab, and Shift-Tab remain operational through both height changes. Escape closes and discards the menu. A's structural cost remains word-first correction order.

### B. Two collapsed rows

`Add word…` expands to one field. `Teach a correction…` expands to two fields in the requested order: what it heard, then what it should be. Default mode uses the proven explicit-frame resize and focuses the first applicable field immediately. Tab traverses the two-field correction form; Return submits; Escape dismisses and discards.

This is the clearest declaration of intent, but it spends two rows before the user starts typing. The optional intrinsic probe adds a deliberate 150 ms clipped pause before its frame fallback; that pause demonstrates the failed mechanism and is not part of the default feel comparison.

### C. Trailing toggle

The taught-word field is immediately available. `+ correction` grows the item through an Auto Layout height constraint and focuses the revealed field; the same control shrinks it again. Repeated grow/shrink cycles retained tracking and exact geometry. Return submits either a word or correction, and Escape dismisses and discards.

C deliberately keeps word-first order as another contrast. The compact toggle is fast once understood, but its meaning carries more interface vocabulary than either explicit B row.

### D. Submenu

The native menu row opens a submenu already sized for a two-field correction form. Click either field to focus; the form reads what it heard, then what it should be. Real typing, Tab, Shift-Tab, and Return were exercised successfully. Escape dismisses the submenu and parent menu together.

It avoids resize mechanics entirely and preserves native parent-menu navigation. The tradeoff is pointer travel and the usual submenu hover corridor while trying to reach editable controls.

### E. Popover

Selecting E closes the menu and opens a transient `NSPopover` anchored to the `QD` status button. The first, misheard field focuses automatically. Tab traverses to the taught-word field, Return prints and closes, and Escape clears and closes the popover. Because menu tracking has ended, the popover owns its key handling without competing sibling highlights.

This is the most isolated and predictable editing environment, but it feels like leaving the menu rather than progressively revealing part of it.

## Builder's impression — not the decision

A is the chosen direction, and the human selected the fully enabled Add button with shake-on-invalid feedback. The temporary A1/A2/A3 rows have been removed. The accordion's remaining compromise is word-first correction order.
