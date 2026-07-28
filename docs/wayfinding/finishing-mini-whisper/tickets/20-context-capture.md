---
status: open
type: grilling
blocked-by: [8]
---

# Context capture: read the focused field before delivering

## Question

Delivery is blind: consecutive dictations butt against each other with no separating space, and the app cannot see edits the user made between dictations. The fix is reading the focused element's actual text via the Accessibility API (`AXUIElement` focused-element value) before delivery — no heuristics; guessing from our own last transcript is explicitly rejected because the user may have lightly edited the field in between. What exactly do we read (full value vs. text around the insertion point), how reliable is AX value access across real targets (native fields, browsers, terminals, Electron), what happens when a target exposes nothing, and does the captured text also feed the LLM cleanup pass ([ticket 18](18-llm-cleanup.md))?

## Notes

- Partially reopens the "screen/selection context awareness" exclusion from [Prune the feature set](tickets/06-prune-the-feature-set.md): focused-field text capture only, not screen-wide awareness or per-app modes.
- Prior art: Wispr Flow reads field context for spacing and tone decisions.
- The paste path already establishes the app's Accessibility-adjacent TCC posture (`kTCCServicePostEvent`); AX value reads require the full `kTCCServiceAccessibility` grant — a new permission ask that onboarding would have to absorb.
