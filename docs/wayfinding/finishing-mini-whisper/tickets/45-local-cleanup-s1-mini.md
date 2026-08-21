---
status: open
type: research
blocked-by: [18]
---

# Local cleanup: superwhisper/s1-mini

## Question

[superwhisper/s1-mini](https://huggingface.co/superwhisper/s1-mini) is a 0.6B Qwen3 fine-tune that does exactly MiniWhisper's cleanup pass — filler removal, self-correction resolution, punctuation, truecasing — as a dedicated local text normalizer, Apache 2.0 plus a naming clause, explicitly pitched for embedding in third-party dictation apps. A local pass would delete the network leg entirely: no endpoint, no key, no privacy story, and latency bounded by the machine instead of a gateway (the proxy's frontier models measure ~3 s median; a 0.6B model on Apple silicon should be an order of magnitude faster).

To establish:

- **Runtime**: what can execute a Qwen3-architecture 0.6B model on macOS within the allowlist posture? whisper.cpp is allowlisted but is not llama.cpp; the security-precedent line says Whispering embeds "local GGUF inference," which may make llama.cpp-class inference defensible — verify what Whispering actually ships. MLX and Core ML conversion are the alternatives; quantizations of s1-mini already exist on the Hub.
- **Interface**: does s1-mini take a bare transcript or a prompt shape? Can it accept our dictionary vocabulary and field context, or is it transcript-in/text-out only (which would make it a *tier*, not a drop-in — the design's prompt inputs wouldn't all apply)?
- **Quality**: run the ticket-43 corpus through it against the gateway baseline once both exist.
- **License**: the naming clause's exact terms; CC-BY-style attribution surface like Parakeet's.
- **Fit**: how a local engine slots into the design — `CleanupClient` is already a seam over `OpenAICompatibleCleanup`; a second implementation behind the same seam is the natural shape. Whether it's the default, a fallback when unconfigured, or a picker choice is a grilling decision, not this ticket's.

Output: findings asset with citations; recommend, don't decide.

## Spike results (2026-08-20)

Runtime and quality spike run at [`spikes/s1-mini-cleanup/`](../../../spikes/s1-mini-cleanup/); findings with the full latency matrix and quality probes in [the asset](../assets/45-local-cleanup-s1-mini.md). Headline: 222 ms median at Q4 GGUF vs 3295 ms for the gateway baseline — 15× — with frontier-equal disfluency handling, working styling axes, but a hard fail on spoken-symbol coded speech and no prompt surface (no dictionary, context, or instructions; empty output is valid). It is a tier, not a drop-in. Remaining: the integration grilling (engine picker shape, empty-output semantics, base-model provenance, runtime choice GGUF-vs-MLX-4-bit) and the ticket-43 corpus comparison once recorded.

**Corpus round 2:** Parakeet + s1-mini scores 12/27 stage-3 exact at 107 ms end-to-end — 63% of gemini's accuracy at 4% of its latency, fully offline. Every failure is structural (no prompt surface: spell-out 0/3, identifier/context 0/3, no dictionary), not quality: it holds all the invariants and ordinary spoken punctuation. The tier framing is confirmed by measurement.

**Round 2 addendum:** Parakeet+s1-mini (12/27 @ 107 ms) beats superwhisper's own recommended offline stack, Cohere Transcribe+s1-mini (9/27 @ 172 ms), on both axes — the engine gap is ASR damage, not cleanup. The offline tier's best pairing is our incumbent engine plus their model.
