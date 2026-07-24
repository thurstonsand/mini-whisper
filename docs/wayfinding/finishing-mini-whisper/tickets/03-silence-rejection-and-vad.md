---
status: closed
claimed: vad-research
type: research
blocked-by: []
---

# Silence rejection and VAD landscape

## Question

Whisper hallucinates on silence ("thank you for watching", phantom punctuation). How do we reject silence and near-silence robustly, within the allowlist (no new third-party deps without checking)?

- Options to evaluate: energy/RMS gating, whisper.cpp's built-in VAD support (it bundles Silero VAD as of 2025 — confirm state and API), Apple's `SNClassifySoundRequest` / voice-processing tap, simple no-speech-probability thresholding on whisper output.
- Two uses to cover: (a) MVP-grade rejection — user holds the key, says nothing, releases: nothing should be pasted; (b) future endpointing for streaming — same primitive, different consumer. Recommend an approach for (a) that doesn't paint (b) into a corner.
- Output: `../assets/03-silence-rejection-and-vad.md` with a recommendation and where it sits in the pipeline (AudioCapture vs. ASREngine).

## Resolution

[Silence rejection and VAD landscape](../assets/03-silence-rejection-and-vad.md) recommends whisper.cpp's standalone Silero VAD as an ASREngine-owned preflight gate, with Whisper's no-speech/log-probability filter as defense in depth. AudioCapture keeps complete canonical PCM and levels; future endpointing reuses Silero's streaming state while a separate pure policy owns utterance boundaries. Before production implementation fixes thresholds, run the asset's labeled-WAV prototype against the actual microphones and environment.
