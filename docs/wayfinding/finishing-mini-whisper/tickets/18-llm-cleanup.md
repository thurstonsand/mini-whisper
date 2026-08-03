---
status: open
type: grilling
blocked-by: [8]
---

# LLM cleanup pass (stake 8)

## Question

The optional post-transcription cleanup via a configurable OpenAI-compatible endpoint inside the controlled network — deliberately last (it is slow). Design the TranscriptCleanup client, prompt/config surface, latency UX (pill state? deliver-then-revise?), and failure behavior. Aqua-style screenshot-as-context noted as a possible input, needs its own privacy call.

## Notes

- Model selection needs its own research pass: benchmark which models are fastest while retaining enough intelligence for the cleanup task (punctuation, casing, disfluency removal, light rewording against field context) — latency is the UX-defining axis, so small/fast models should be measured against the actual task before defaulting to a large one.
- Field context is already captured at delivery ([ticket 20](20-context-capture.md)): `FocusedTextContext` (bounded before/selected/after around the caret) is shaped for this pass to consume.
