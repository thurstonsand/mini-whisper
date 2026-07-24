---
status: closed
claimed: engine-research
type: research
blocked-by: []
---

# Engine landscape: whisper.cpp integration, models, streaming, Parakeet

## Question

What does the transcription engine layer need to look like so the MVP is simple but the future (streaming, second engine) doesn't require a rewrite?

- whisper.cpp integration path: building/obtaining `whisper.xcframework` for arm64 macOS, Metal support, how Hex and VoiceInk wire it.
- Model choice for the MVP: which whisper model balances latency and accuracy for dictation-length utterances on Apple Silicon (large-v3-turbo vs. distil vs. base.en); model file discovery (point at existing files first, download UI later).
- Streaming feasibility: what whisper.cpp's streaming actually is (chunked re-decode), what Parakeet/FluidAudio offers (genuinely streaming CTC/TDT), and what that implies for the `TranscriptionEngine` protocol shape now.
- Parakeet/FluidAudio: dependency footprint and whether it could ever fit the work allowlist.
- Output: `../assets/04-engine-landscape.md` with a recommended protocol sketch and MVP model recommendation.

## Resolution

Resolved in [Engine landscape: whisper.cpp, models, streaming, and Parakeet](../assets/04-engine-landscape.md).
