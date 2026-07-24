---
status: closed
type: prototype
blocked-by: [4, 6]
claimed: engine-bakeoff
---

# Engine bakeoff: feel the latency before choosing

## Question

Which allowed runtime/model tuple actually gives MiniWhisper the best English dictation quality, release-to-text responsiveness, and future model seam on the target Mac?

Create a cheap, disposable macOS arm64 prototype under `../assets/09-engine-bakeoff/`, isolated from the MiniWhisper app and production packages. It should:

- exercise the pinned `transcribe.cpp` Swift XCFramework with Metal;
- load Parakeet TDT 0.6B v2 `Q5_K_M`, Parakeet TDT 0.6B v3 `Q5_K_M`, Whisper large-v3-turbo `Q5_K_M`, and Whisper `base.en` `Q5_K_M` through the same wrapper;
- prove that changing compatible GGUF models does not require changing app-level transcription code;
- run the same personal English dictation fixtures through every model and report exact hardware/runtime/model revisions, cold load time, warm end-to-end latency, peak resident memory, transcript output/errors, and cancellation behavior;
- keep the model resident and simulate the hold-release path so the user can judge Hex-like perceived responsiveness rather than only throughput;
- demonstrate one genuinely streaming model through `transcribe.cpp` if a supported artifact is readily usable, with committed/tentative live text; otherwise record the exact blocker rather than substituting Whisper-style repeated re-decode;
- include a README with reproduction commands and a compact results table.

This is HITL. Present the working prototype and transcripts to Thurston, let him react to quality and feel, and record the resulting runtime/model direction. The artifact is deliberately rough; production XCFramework build/signing scripts belong under repository `scripts/` only after the MVP spec accepts a runtime.

## Resolution

Tentatively select **FluidAudio v0.15.5 with Parakeet TDT 0.6B v2** for the MVP, loaded once and kept resident behind MiniWhisper's `ASREngine` boundary. Thurston preferred Parakeet's text and responsiveness, rejected Whisper Small's accuracy, and preferred FluidAudio's broader Swift dictation adoption over carrying a young native runtime or dependency patch. **whisper.cpp v1.9.1 with Whisper Medium.en Q5_0 remains the fallback** if FluidAudio's stitching or dependency posture fails under daily use.

The final FluidAudio lane used commit `19600a485baa4998812e4654b70d2bab8f2c9949` and the English-only v2 Core ML artifact at immutable revision `ee09c569f73759e6d44c9bd16766f477b2b36d39`. Across 24 personal fixtures totaling 11.7 minutes, it measured 98 ms warm median, 222 ms warm p95, 238 ms for the 93.5-second fixture, 3.21% edit distance against Aqua's uncorrected baseline, roughly 170 MiB later-process RSS, and 75 ms cancellation response. Its transcript was qualitatively competitive with Whisper Medium.en and showed no obvious dropped clause or repetition loop. Several counted errors were punctuation, casing, or word-boundary formatting differences rather than recognition failures.

Parakeet v3 was slightly worse in FluidAudio and duplicated short words at long-form seams. Disabling mel context raised its edit distance to 3.87%; dual-decode arbitration produced the same text while doubling median latency. V2's default long-form path is therefore the selected configuration.

The stitching concern remains explicit. FluidAudio's ordinary TDT model sees fixed 15-second windows and merges overlapping results. Production must reuse FluidAudio's existing `AsrManager` chunking and merger—following [Hex's pinned FluidAudio Parakeet client](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/ParakeetClient.swift)—rather than inventing an app-level chunker or stitcher. MiniWhisper's regression corpus must retain long speech, quiet pauses, and utterances crossing repeated 15-second boundaries so upstream updates cannot silently introduce dropped, glued, or duplicated words.

Operational constraints:

- First Core ML specialization took 213 seconds; later process loads took about 0.1 seconds. Model download, compilation, and prewarm belong in explicit onboarding, never the first dictation.
- Pin FluidAudio and the Core ML model to exact revisions and hashes. The tested v0.15.5 tag has no external package or binary dependency, while current `main` has already added a mandatory Nemo text-processing XCFramework; every update requires dependency review and the full regression gate.
- The v2 model emitted a recoverable Core ML `E5RT ... zero shape error` diagnostic on load. It did not change deterministic output, but it remains an upstream issue to track.
- Keep the app-owned engine protocol model-agnostic. FluidAudio supports Parakeet, not Whisper; do not ship a second engine merely to preserve theoretical switching.
- The earlier allowlist screen is relaxed for this tentative direction. Final installed-artifact compliance and Parakeet CC-BY-4.0 attribution still need explicit acceptance in the MVP spec.

Silence rejection must hand one accepted utterance to `ASREngine`; it must not perform its own overlap chunking or alter FluidAudio's stitching geometry. Its bakeoff should include quiet spans around 15-second boundaries because those are both VAD-policy and merger regression cases.

Durable evidence:

- [Prototype, reproduction, and integration findings](../assets/09-engine-bakeoff/README.md)
- [FluidAudio report](../assets/09-engine-bakeoff/results/fluid-audio.md)
- [Expanded runtime matrix](../assets/09-engine-bakeoff/results/runtime-matrix.md)
- [Mature Whisper fallback comparison](../assets/09-engine-bakeoff/results/maturity-options.md)
