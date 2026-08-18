---
status: open
type: prototype
blocked-by: [42]
---

# Coded-speech corpus: prove the prompt on real dictations

## Question

**Rescheduled at the design review:** this spike runs *after* the cleanup pass is implemented. Once the real pipeline works end-to-end, recording the corpus and tweaking the prompt against it is much cheaper than staging either in advance. The shipped default prompt is chosen from the prior-art candidates at design time and refined here later.

Which built-in prompt (and which model) actually handles spoken technical language? Build a small recorded corpus of the user dictating coded speech across scenarios — explicit punctuation commands ("comma", "period", "colon"), spoken symbols (the proverbial "dash dash help"), and identifier recovery where the raw transcript says "API controller" but the provided field context contains `apiController` — each entry carrying the raw transcript, the staged context, and the intended output. Replay it through the [benchmark harness](../assets/38-cleanup-model-benchmark/) with the candidate prompts from [prompt prior art](42-cleanup-prompt-prior-art.md), across models, and judge by diff. HITL: the user records the corpus (the app's own history captures raw transcripts; context is staged per entry) and judges the outputs. Output: the chosen built-in prompt and evidence for the recommended-model shortlist feeding [ticket 39](39-recommended-cleanup-providers.md).
