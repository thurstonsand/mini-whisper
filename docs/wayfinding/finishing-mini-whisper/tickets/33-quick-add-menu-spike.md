---
status: closed
type: prototype
blocked-by: []
---

# Quick-add menu spike: can a text field live in the status menu?

## Question

[Dictionary](13-dictionary.md) decided quick add is an inline text field inside the status-item menu — open, click, type, done, no window — built as a view-based `NSMenuItem`. That interaction has known risk: menu tracking runs its own event loop, and text fields hosted in menus have focus and key-handling quirks. Prove or refute it with a runnable spike before the design doc commits to it.

The decided fallback if the UX sours: the menu item opens Settings → Dictionary with the add sheet pre-opened.

## What the spike must prove

- The field can take keyboard focus when the menu opens or the item is clicked.
- Typing works reliably while the menu is tracking; word field plus optional misspelling field.
- Return commits and closes the menu; Escape aborts without killing the whole menu session unexpectedly.
- No degradation of the surrounding menu: arrow-key navigation of ordinary items still works.

Precedent: [`spikes/settings-mockup`](../../../../spikes/settings-mockup/SettingsMockup.swift) — a single-file runnable artifact with a capture script.

## Resolution

**Viable with caveats — the inline field wins.** The runnable artifact at [`spikes/quick-add-menu`](../../../../spikes/quick-add-menu/README.md) (macOS 26.5.2) proved: click-to-focus is reliable and immediate; typing under menu tracking drops nothing; Tab/Shift-Tab traverse the two fields; Return commits from either field and closes the menu; sibling items stay arrow-navigable.

The caveats, and their dispositions:

- **Escape** is consumed by NSMenu tracking before any delegate or monitor sees it — it closes the whole menu and `menuDidClose` discards the draft. Accepted as-is: dismiss-and-discard *is* the abort semantics quick add wanted; keeping the menu open on Escape would demand event-tap machinery for no user benefit.
- **Focus on menu-open** fails synchronously (the hosted view has no window during `menuWillOpen`); a 150 ms delayed attempt works. Production treats click-to-focus as the path and any auto-focus as best-effort garnish.
- **Down-arrow** exits the fields into sibling-item highlighting. Coherent menu behavior; Tab is the documented traversal.

Plain `NSTextField` over SwiftUI hosting: direct first-responder control, and the spike showed responder transitions need explicit field-editor synchronization that AppKit makes visible. Design consumed by [Dictionary](13-dictionary.md)'s design doc.
