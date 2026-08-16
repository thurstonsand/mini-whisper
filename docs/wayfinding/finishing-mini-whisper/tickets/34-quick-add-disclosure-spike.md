---
status: closed
type: prototype
blocked-by: [33]
---

# Quick-add disclosure spike: collapsed line, progressive reveal

## Question

The shipped quick add ([13](13-dictionary.md), built on [33](33-quick-add-menu-spike.md)) presents both text fields the moment the menu opens. User review rejected that shape: quick add should read as a single collapsed menu line that expands on click, and the misspelling field should appear only when the user declares that intent. Two questions, in order:

1. **The expansion mechanic.** Can a view-based `NSMenuItem` change height while its menu is open and tracking — reliably, without visual tearing, on current macOS? Everything else depends on this.
2. **The disclosure model.** Assuming expansion works, which interaction earns the misspelling field its reveal? Five candidates, all to be mocked in real code so the human can operate each one and choose by feel:
   - **A. Accordion inside the form** — one collapsed line; expands to a word field plus a "misheard as…" disclosure that reveals the second field (nested expansion).
   - **B. Two collapsed rows** — "Add word…" and "Teach a correction…", each expanding to its own correctly-ordered form.
   - **C. Trailing toggle** — word field with a compact affordance beside it that grows the form.
   - **D. Submenu** — the form lives in a submenu, sized at its own open; no in-place resize.
   - **E. Popover** — the menu item closes the menu and opens an `NSPopover` form off the status item.

Field-order note for correction forms: test misheard-first reading order (*what it heard → what it should be*); review flagged the shipped word-first order as feeling backwards.

## What the spike must prove

- A verdict on live height change under menu tracking, with failure modes named if it breaks.
- A runnable artifact presenting all five models side by side — real AppKit, real focus, real typing — operable by the human without reading code.
- For each model: focus behavior, keystroke handling, Escape/Return semantics, and any degradation of sibling menu items.

Precedent: [`spikes/quick-add-menu`](../../../../spikes/quick-add-menu/README.md) — single-file runnable artifact, capture script, README verdict.

## Resolution

**Expansion works; the accordion wins.** The runnable artifact at [`spikes/quick-add-disclosure`](../../../../spikes/quick-add-disclosure/README.md) (macOS 26.5.2) proved live in-place resize and let the human operate all five models; iteration settled on model A. The chosen shape: one collapsed "Add to Dictionary…" row with native menu-item appearance; click (anywhere in the row, one-way) expands to a word field with a "Misheard as…" disclosure row of the same native appearance, itself one-way expanding to the misspelling field; a left-aligned always-enabled Add button beside Return.

Validation feel, decided by operating three mocked variants: Add always renders fully clickable and answers an invalid attempt with the standard `CAKeyframeAnimation` x-translation shake — no disabled state anywhere. Taught-word-only submits as a vocabulary entry even with the disclosure open (silent degradation); misspelling-only shakes. The accordion's structure keeps the taught word on top and reveals the misspelling beneath it — the misheard-first reading order models B/D demonstrated was noted but not chosen; disclosure order won.

Lessons earned, all load-bearing for the production rebuild:

- **Resize must be frame-driven.** Explicit frame mutation or an active Auto Layout height constraint resizes the open, tracking menu exactly (10/10 cycles, no tearing, no tracking loss). Intrinsic-content-size invalidation plus `menu.update()` is silently ignored.
- **The caret is theater.** The menu window accepts the field editor as first responder but never becomes key (`makeKey()` ignored; forcing activation dismisses the menu), so no native caret blinks. Ship a layer-backed one-point blinking overlay as a child of the focused field, positioned from the field editor's selected-range rect in field-local coordinates, refusing degenerate frames. Never attach it at the window content root — under menu tracking, top-level blink invalidations promote to the entire composited menu surface (the whole menu strobes).
- **The field-editor lifecycle law.** Moving focus between menu-hosted fields must synchronize and `endEditing(_:)` the previously-editing cell — whichever view owns it — before selecting the next field; a cell left in editing state deliberately draws neither value nor placeholder.
- **Native parity is measurable.** Selection pill via emphasized `.selection` `NSVisualEffectView`; geometry and colors matched to the native sibling by screenshot pixel-sampling (pill 320×24, RGB (58,93,194); text (222,222,222) unselected, white selected) rather than eyeballing. Full-row hit targets via `hitTest` routing.
- **Placeholders verbatim from the pane's sheet** (`Word or phrase` / `Correct spelling` / `Misspelling`), so quick add and the pane speak identically.
