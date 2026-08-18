# Cleanup pill mock-up

Disposable mock-up for [ticket 41](../../docs/wayfinding/finishing-mini-whisper/tickets/41-cleanup-pill-mocks.md): the pill during a blocking cleanup pass. Not an Xcode target, imports no MiniWhisper code — the pill chrome (capsule, materials, dot, type) is copied from `PillView.swift` so variants are judged on real pixels.

```sh
swiftc -framework AppKit -framework SwiftUI \
  spikes/cleanup-pill-mockup/CleanupPillMockup.swift -o .build/cleanup-pill-mockup
.build/cleanup-pill-mockup        # gallery: all variants at once
.build/cleanup-pill-mockup live   # the chosen sequence with real timings
```

A trailing `light` or `dark` argument forces that appearance. The process prints its `CGWindowID` on launch for `screencapture -l`.

## The decision

Reviewed against `evidence/variants-{dark,light}.png`:

- **Working state**: "Transcribing…" (blue dot) stays for the engine + sidecar leg; the moment the LLM request starts, the pill flips to **"Polishing…" with a purple dot** (W4's wording on W3's color) — the phase change marks the network leg without reading.
- **Skip affordance** (revealed at 3 s of cleanup): **S2's structure with the Polishing label** — `Polishing… [⌥ Opt →] to skip`, the keycap chip speaking the same vocabulary as Settings and onboarding. Bare `⌥` was rejected as ambiguous for a sided modifier.
- **Failure notice**: **F3** — "Cleanup unavailable — pasted as heard", subdued, matching the "Pasted without field context" precedent: delivery succeeded with degradation.

`live` plays the chosen composition end-to-end: transcribing → polishing → skip reveal → failure notice → gone.
