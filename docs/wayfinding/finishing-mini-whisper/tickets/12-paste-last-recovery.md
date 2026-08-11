---
status: closed
type: grilling
blocked-by: [8]
---

# Paste-last-transcript recovery (stake 2)

## Question

A hotkey to re-paste the last transcript plus the menu re-copy item already shipped in MVP. What bind (second chord through the same gesture machine?), what happens when history (stake 1) exists vs. not, and does it respect the delivery-fallback clipboard rules?

## Notes

- **Partly absorbed by history.** The settings inventory expects the history pane to carry a *Copy Last to Clipboard* action rather than a separate paste-last row — inside a window there is no meaningful paste target, so copy is the only honest verb there. What stays here is the hotkey, which is the half that operates without a window and does have a target.
- That splits the ticket along a real seam: the **binding and its delivery behavior** live here; the **list and its copy actions** live in [History](11-history.md).
- The [competitor audit](../assets/25-competitor-feature-audit.md) refines the delivery half: a changed or missing destination must degrade to copy rather than paste into whatever app is now frontmost. The recovery flow needs the delivery result and target snapshot to be observable, not merely the transcript.
- **The same law applies to first delivery, observed in the field (2026-08):** dictating with no text input focused pastes into the void, restores the clipboard over the transcript, and the pill leads with the lesser complaint ("could not collect surrounding text") while the greater one — nothing received the text — goes unsaid. `ContextUnavailable.noFocusedElement`/`nonTextElement` already distinguish the case at capture time, so delivery has the signal: no target should degrade to copy-and-say-so, and pill notices need a precedence where placement failure outranks context failure.

## Resolution

Grilled 2026-08-10; every branch settled.

**One law, both paths.** At delivery time, a context capture of `noFocusedElement` or `nonTextElement` means there is no text receiver: delivery is withheld — the clipboard is left untouched, the history entry records `method: noReceiver` with the reason as detail, and the pill names the recovery in one line for both reasons ("Nowhere to paste — ⌥⌘V to retry", chord rendered glyph-only from settings; unbound: "Nowhere to paste — transcript saved to History") — instead of pasting into the void. Withholding is scoped to `noReceiver` only: the broken-paste fallbacks (missing Accessibility, secure input, event-creation failure) keep copying, because in those states the recovery chord's synthesized ⌘V is equally broken and the clipboard is the only working delivery. Every other `ContextUnavailable` case (`noTextRange`, `gridSemantics`, `zeroWidthSink`, `protectedField`, `axFailure`, `timedOut`) describes a field that accepts ⌘V but resists reading, and keeps pasting blind. The law governs first delivery and the recovery chord identically. Pill notice precedence is fixed so placement failure always outranks context failure. Accepted risk: an app whose focused element misreports its role while a real field holds keyboard focus would wrongly degrade under `nonTextElement`; the recorded retreat is narrowing the law to `noFocusedElement` alone.

**The bind.** A separate side-specific chord through the existing event tap, tap-to-fire — no hold, no latch, no gesture machine. Default: left-Option + left-Command + V. Accepted cost: a globally suppressed ⌥⌘V steals Finder's *Move Item Here* (and any app's ⌥⌘V) until rebound. Right-Option-based chords are foreclosed by activation firing on right-Option-down. New hotkey-pipeline concept: bindings carry an action identity — the activation bindings feed the gesture machine, the paste binding fires its action on chord completion. The rebind row lands in the settings pane (in flight as [Settings pane](31-settings-pane.md)).

**Two verbs.** The menu's *Copy Last Transcript* copies verbatim to the pasteboard, unchanged. The chord *delivers*: full pipeline — fresh context capture, the transcript join rules, clipboard restore, the no-target law. Recovery is just another delivery of an old transcript.

**Source.** In-memory `lastTranscript` when set; otherwise the history head's `currentText` (so first boot after a relaunch still recovers); otherwise nothing, and the pill shows a transient "No transcript to paste yet". History-off users keep the in-memory transcript.

**Prefactor (decided in revision).** Hotkey defaults are defined by action, not key: `HotkeyListener` keeps the purely mechanical `Hotkey` type with no role-named statics, and `AppSettings` owns a per-action bindings structure (`activate: [Hotkey]`, `pasteLastTranscript: [Hotkey]`) with its defaults, replacing the flat `hotkeys` + `pasteLastTranscriptHotkey` fields. No legacy-key migration.

**Boundaries.** No comparison against the entry's recorded `targetApp` — a deliberate keypress is the user's focus statement; only the no-target law degrades. The chord is a no-op while any dictation interaction is live. Success is silent (complete cue only); degrade-to-copy shows the copied notice naming the reason. A recovery paste mutates nothing in history — the entry's `Delivery` record stays the original dictation's outcome, and under the one-law scope a degraded first delivery already lands observably as `method: copied` with a no-focused-field detail.

Execution happened in place (no separate build ticket) under the agreed protocol: a gpt-5.6-sol subagent implements, the coordinator runs the thermo-nuclear review and cycles feedback, the user signs off on the staged result. Interfaces touched: `DeliveryClient`/`DeliveryOutcome` (the `noReceiver` outcome), `MultipleChordMatcher` (per-binding action identity), `AppSettings` (per-action bindings), the pill (withheld + no-transcript notices, placement-over-context precedence). Tested at existing seams: HotkeyListener package tests, AppFeatureTests, PillFeatureTests.
