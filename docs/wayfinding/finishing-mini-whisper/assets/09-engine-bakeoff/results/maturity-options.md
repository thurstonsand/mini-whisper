# Mature runtime options

This comparison was the conservative fallback after rejecting transcribe.cpp's maturity posture and before directly testing FluidAudio. `transcribe.cpp` produced the best initial result but is a young 0.x, effectively single-maintainer project. whisper.cpp's Parakeet implementation shipped only in v1.9.0, and its stable v1.9.1 Apple builder does not yet package Parakeet into the XCFramework.

The mature local runtime is whisper.cpp's established Whisper implementation. whisper.cpp began in 2022, has a broad contributor base, is MIT-licensed, publishes tagged releases, carries an Apple XCFramework builder, and already wires cancellation through GGML's backend callbacks. MiniWhisper would consume its C module through a small actor-isolated Swift client.

## Larger Whisper checkpoints through whisper.cpp v1.9.1/Metal

| Checkpoint | Artifact | Cold load | Warm median | 93.5 s fixture | Corpus WER | Peak RSS | Observed failure |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Small.en Q5_1 | 181 MiB | 93 ms | 272 ms | 945 ms | 3.38% | 432 MiB | Accuracy rejected by Thurston |
| **Medium.en Q5_0** | **514 MiB** | **182 ms** | **605 ms** | **2,187 ms** | **3.13%** | **901 MiB** | No catastrophic fixture |
| large-v3-turbo Q5_0 | 547 MiB | 167 ms | 560 ms | 2,240 ms | 3.95% | 853 MiB | Repeated a trailing sentence on the 66.8 s fixture |
| large-v3 Q5_0 | 1,031 MiB | 287 ms | 1,025 ms | 3,864 ms | 12.85% | 2,054 MiB | Repeated one sentence seven times on the 79.4 s fixture |

Aqua's raw transcript remains an independent baseline rather than hand-corrected truth. The full large-v3 aggregate is dominated by one obvious repetition loop; model size did not produce monotonically better dictation behavior.

## Viable directions

### 1. whisper.cpp + Medium.en Q5_0

This is the conservative recommendation. It clears Thurston's minimum model-size requirement, had the best stable Whisper result in the mature runtime, and keeps median release latency near 0.6 seconds. The longest 93.5-second utterance took 2.2 seconds. Its 901 MiB process high-water mark is substantially below Parakeet's 1.65 GiB.

The integration is less elegant than transcribe.cpp's multi-family Swift wrapper but straightforward: build the pinned upstream XCFramework, import its C module, contain the context in a Swift actor, and expose it through `ASREngine`. This path has years of production use and a large upstream community.

### 2. Apple's on-device Speech framework

This offers the strongest vendor stability and uses only an already-allowed Apple framework. It gives up checkpoint control, reproducible model versions, and deterministic behavior across macOS updates. On-device availability and quality must be proven on the deployment target before considering it. It is a separate prototype, not evidence from this bakeoff.

### 3. Seek approval for WhisperKit or FluidAudio

WhisperKit supplies a Swift/Core ML Whisper path, but Small.en was about 800 ms warm and the dependency is not currently allowed. FluidAudio supplies the Parakeet/Core ML path used by Hex. The tested v0.15.5 tag has no external SwiftPM or binary dependency, though current `main` has since made `NemoTextProcessing.xcframework` mandatory. That dependency drift makes an exact release pin important.

### 4. Wait for a mature Parakeet path

Track whisper.cpp's new Parakeet implementation until its Apple packaging, model conversions, and field history settle. This preserves Parakeet as a future migration without making MiniWhisper depend on a new runtime today.

## Recommendation

At this stage, the conservative fallback was **whisper.cpp v1.9.1 + Whisper Medium.en Q5_0 + Metal**. The subsequent [FluidAudio bakeoff](fluid-audio.md) supersedes that recommendation: FluidAudio v0.15.5 with Parakeet v2 proved viable and returns the decision to human quality/dependency judgment.
