---
status: closed
type: prototype
claimed: llm-cleanup-grilling
blocked-by: []
---

# Cleanup pill mocks: the shape and verbiage of the waiting state

## Question

The pill during a blocking cleanup: exact chrome, copy, and structure for the working state, the ≥3 s skip affordance ("press ⟨activation⟩ to skip"), and the failure notice ("delivered as heard"). Build a spike with the real pill chrome — the actual panel, materials, and type — rendering multiple variants: different wordings, element orders, and structures, so the decision is made by looking at real pixels rather than prose. Follows the settings-mockup precedent; the chosen variant feeds the [LLM cleanup](18-llm-cleanup.md) design doc.

## Resolution

Built at [`spikes/cleanup-pill-mockup`](../../../spikes/cleanup-pill-mockup/) — eleven variants across three states in the real pill chrome, captured light and dark under `evidence/`. Decided by review: "Transcribing…" (blue dot) holds through the engine leg and flips to **"Polishing…" with a purple dot** when the LLM request starts; the 3 s skip reveal keeps the phase and adds the keycap chip — `Polishing… [⌥ Opt →] to skip` — because a sided modifier needs its full name and the chip speaks Settings' vocabulary; the failure notice is subdued "Cleanup unavailable — pasted as heard", matching the pasted-without-field-context precedent. The `live` mode plays the chosen sequence with real timings. Folded into the [design doc](../../designs/03-llm-cleanup.md).
