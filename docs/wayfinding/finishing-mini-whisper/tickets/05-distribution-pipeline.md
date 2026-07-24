---
status: closed
claimed: distribution-research
type: research
blocked-by: []
---

# Distribution: signing, notarization, homebrew tap

## Question

What does the release pipeline look like so an installed MiniWhisper complies at work? The user already has the Apple developer account and signing machinery proven in ghosttykit — read `/Users/thurstonsand/Develop/ghosttykit`'s GitHub Actions workflows and reuse the approach.

- Developer ID signing + notarization for a menu bar app with mic + Input Monitoring + Apple Events entitlements; whether the embedded whisper.xcframework changes anything.
- Cask in the existing `thurstonsand/homebrew-tap`: artifact shape (zip/dmg), versioning, release automation from GHA.
- Check hardened-runtime/entitlement interactions with CGEvent taps yourself if [Hotkey mechanism and hold/latch prior art](./02-hotkey-mechanism-prior-art.md) hasn't closed; reconcile at spec time if both looked.
- Output: `../assets/05-distribution-pipeline.md` — the pipeline plan; actual workflow authoring is execution, not this ticket.

## Resolution

Research and recommendations are captured in [Distribution pipeline research](../assets/05-distribution-pipeline.md).
