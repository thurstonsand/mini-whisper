---
status: open
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
