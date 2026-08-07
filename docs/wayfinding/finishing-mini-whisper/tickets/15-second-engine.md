---
status: open
type: grilling
blocked-by: [8]
---

# Second engine / fallback hardening (stake 5)

## Question

Reworded from 'Parakeet second engine' after the bakeoff inverted the stack: FluidAudio/Parakeet is primary, whisper.cpp Medium.en is the recorded contingency. Decide what hardening the fallback path needs — a shippable second engine behind ASREngine, a maintained branch, or retirement — driven by FluidAudio's observed reliability in daily use.

## Notes

- **The corpus is gone.** The [Cohere run](26-cohere-transcription-model.md) found that the engine bakeoff's 24 private recordings no longer exist — only `assets/09-engine-bakeoff/fixtures/local-manifest.json`'s reference text survives, which is useless without its audio. Every engine decision this project has made rests on measurements that can no longer be reproduced or extended, so any candidate weighed here starts from nothing.
- Rebuilding it by hand is what happened last time. [History](11-history.md) makes it a byproduct instead: transcripts paired with their audio, accumulated by ordinary use, with hand-corrected entries worth more than clean ones. That was filed as an incidental benefit of history; the corpus loss promotes it to the reason this ticket can be answered at all.
- The corrected-transcript question therefore belongs to history's design, not this one — raise it there before this ticket opens.
- **Re-examine v2 over v3 first, before any second engine.** The [bakeoff](09-engine-bakeoff.md) picked Parakeet v2 on a margin of *one word* across 24 private recordings — 3.21% against v3's 3.29% — plus a seam-duplication artifact in v3's default path. One word is noise, the corpus that produced it no longer exists, and the [Cohere addendum](../assets/26-cohere-transcription-model/README.md) finds public data pointing the other way: Artificial Analysis measures v3 at 4.5% against v2's 6.4% on dictation-like audio. Both artifacts are already pinned and both load in the same FluidAudio runtime, so this is the cheapest accuracy experiment available — and the one that has to run before spending anything on a second engine.
- **Moonshine is a candidate to weigh alongside whisper.cpp.** Whispering — the app the allowlist already sanctions — offers it next to Parakeet and Whisper, which is the cheapest available signal that it is viable for dictation. [Useful Sensors' Moonshine](https://huggingface.co/UsefulSensors/moonshine) is MIT, English-only, and sized for edge devices; it drops Whisper's fixed 30-second padding for variable-length processing, so cost scales with utterance length — the exact shape of this app's workload. Its published WER claims a slight edge on same-size Whisper models. The open question is runtime: weights ship as ONNX/Keras with no FluidAudio or Core ML path, so a Swift integration means onnxruntime or a conversion of our own, and a new inference runtime is an allowlist question before it is an accuracy one. Answer that before spending anything on measurement.
- [Cohere](26-cohere-transcription-model.md) is the standing revisit-later candidate: excluded on today's Core ML conversion at 532 ms p50 and ~12 GB RSS, worth re-measuring if a faster or leaner Apple artifact appears.
