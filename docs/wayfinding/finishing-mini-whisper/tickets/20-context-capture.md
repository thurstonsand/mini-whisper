---
status: closed
type: grilling
blocked-by: [8]
---

# Context capture: read the focused field before delivering

## Resolution

Prototyped, then implemented. The probe evidence and design (target matrix, payload, taxonomy, prior-art comparison) live in [the research asset](../assets/20-context-capture.md). Implementation: `Packages/FieldContext` (payload, validated range planner, join rules) plus an app-side reader — per-app focus resolution (never system-wide), 20 ms per-element timeouts under a 60 ms capture deadline, bounded 256-unit windows with surrogate-safe cuts, all-or-nothing conformance; any unavailable case pastes blind and shows a transient pill notice. No new permission ask: the Paste Access grant covers AX reads. One design reversal recorded during implementation: the mechanical terminal earn-back was withdrawn — the probe's own Terminal.app/nvim row (`{193, 0}` over pure grid) proved a nonzero in-bounds caret cannot distinguish document from grid semantics, so terminals stay `gridSemantics` until a per-terminal, per-version validated contract exists (Ghostty's upstream AX work is the likely first). The captured context feeds spacing/capitalization now and is shaped for the LLM cleanup pass ([ticket 18](18-llm-cleanup.md)) later.

## Question

Delivery is blind: consecutive dictations butt against each other with no separating space, and the app cannot see edits the user made between dictations. The fix is reading the focused element's actual text via the Accessibility API (`AXUIElement` focused-element value) before delivery — no heuristics; guessing from our own last transcript is explicitly rejected because the user may have lightly edited the field in between. What exactly do we read (full value vs. text around the insertion point), how reliable is AX value access across real targets (native fields, browsers, terminals, Electron), what happens when a target exposes nothing, and does the captured text also feed the LLM cleanup pass ([ticket 18](18-llm-cleanup.md))?

## Notes

- Partially reopens the "screen/selection context awareness" exclusion from [Prune the feature set](tickets/06-prune-the-feature-set.md): focused-field text capture only, not screen-wide awareness or per-app modes.
- Prior art: Wispr Flow reads field context for spacing and tone decisions.
- The paste path already establishes the app's Accessibility-adjacent TCC posture (`kTCCServicePostEvent`); AX value reads require the full `kTCCServiceAccessibility` grant — a new permission ask that onboarding would have to absorb.
