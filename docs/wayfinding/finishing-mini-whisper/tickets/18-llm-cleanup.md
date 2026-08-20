---
status: closed
type: grilling
claimed: llm-cleanup-grilling
blocked-by: [8]
---

# LLM cleanup pass (stake 8)

## Question

The optional post-transcription cleanup via a configurable OpenAI-compatible endpoint inside the controlled network — deliberately last (it is slow). Design the TranscriptCleanup client, prompt/config surface, latency UX (pill state? deliver-then-revise?), and failure behavior. Aqua-style screenshot-as-context noted as a possible input, needs its own privacy call.

## Notes

- Model selection needs its own research pass: benchmark which models are fastest while retaining enough intelligence for the cleanup task (punctuation, casing, disfluency removal, light rewording against field context) — latency is the UX-defining axis, so small/fast models should be measured against the actual task before defaulting to a large one.
- Field context is already captured at delivery ([ticket 20](20-context-capture.md)): `FocusedTextContext` (bounded before/selected/after around the caret) is shaped for this pass to consume.

## Resolution

Accepted design at [docs/designs/03-llm-cleanup.md](../../designs/03-llm-cleanup.md). The shape: a blocking, best-effort pass — transcribe, clean, deliver once — that can never fail a dictation (raw delivers on any error or timeout, default 10 s, configurable); any activation press resolves a pending cleanup as a skip, with a hold also starting the next recording; context is captured once and feeds both the prompt and the join; history stores an immutable raw beside a cleanup record and displays cleaned; the client is URLSession chat completions with the key in the Keychain — native endpoints, SDKs, and subscription auth researched and rejected.

Five research passes and one spike ground it: [model benchmark + harness](38-cleanup-model-benchmark.md), [AX beyond the field](36-ax-context-beyond-the-field.md) and [screenshot/OCR](37-screenshot-ocr-context.md) (both: ship focused-field-only), [native endpoints](40-native-llm-endpoints.md), [prompt prior art](42-cleanup-prompt-prior-art.md) (built-in prompt: Candidate A + B's symbol enumeration), and the [pill mock spike](41-cleanup-pill-mocks.md) (Polishing… purple dot, keycap skip chip, subdued failure notice). Follow-ups staked: [recommended providers](39-recommended-cleanup-providers.md) and the post-implementation [coded-speech corpus](43-coded-speech-corpus.md).

Built and shipped, all seven phases (`a32c5df`, `9ce4da7`, `2f74ca5`): the TranscriptCleanup package, per-channel Keychain, history log v2 with per-transcription cleanup records, one TranscriptPipeline shared by live dictation and re-transcription, the skip grammar, the Polishing pill, and the Cleanup pane with tri-state Save and bare-host endpoint discovery. Proven end-to-end against a real gateway while daily-driving; further follow-ups staked along the way: [onboarding discovery](44-onboarding-cleanup-discovery.md), [local s1-mini](45-local-cleanup-s1-mini.md), [tone modes](46-cleanup-tone-modes.md).
