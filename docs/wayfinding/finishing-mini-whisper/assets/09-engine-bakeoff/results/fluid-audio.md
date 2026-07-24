# FluidAudio Parakeet bakeoff

FluidAudio v0.15.5 was built as an isolated Swift package and tested against the same 24 personal fixtures (11.7 minutes, 1,214 Aqua-reference words). The Core ML model bundles were loaded from immutable Hugging Face revisions rather than FluidAudio's moving default branch.

## Results

| Runtime | Model | Long-form path | Cached load | Warm median | Warm p95 | 93.5 s fixture | Corpus WER | Peak RSS | Cancel response |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FluidAudio | Parakeet v2 | Default 15 s overlap | 125 ms | 98 ms | 222 ms | 238 ms | 3.21% | 170 MiB | 75 ms |
| FluidAudio | Parakeet v3 | Default 15 s overlap | 89 ms | 107 ms | 226 ms | 246 ms | 3.29% | 188 MiB | 110 ms |
| FluidAudio | Parakeet v3 | No mel context | 93 ms | 110 ms | 244 ms | 244 ms | 3.87% | 188 MiB | 108 ms |
| FluidAudio | Parakeet v3 | Dual-decode arbitration | 92 ms | 216 ms | 643 ms | 755 ms | 3.87% | 155 MiB | 34 ms |
| transcribe.cpp | Parakeet v3 | One-shot Metal | 120 ms | 172 ms | 965 ms | 1087 ms | 2.55% | 1654 MiB | 1020 ms |
| whisper.cpp | Whisper Medium.en | One-shot Metal | 182 ms | 605 ms | 1844 ms | 2187 ms | 3.13% | 901 MiB | not measured |

The FluidAudio RSS values are later-process high-water marks. Core ML and ANE allocations are not directly comparable with native Metal process accounting.

## First-use behavior

The supplied `.mlmodelc` bundles still required one-time Core ML specialization on this Mac. Parakeet v2's first load took **213.0 seconds** and v3's took **194.9 seconds**. Later processes loaded in 89–125 ms. This must happen during model installation/onboarding, never on the first dictation.

The first-use process reached about 560 MiB RSS for either model. Later-process RSS was 170 MiB for v2 and 188 MiB for v3, but that does not include every Core ML/ANE allocation in a comparable way.

## Quality observations

- **Parakeet v2 was the strongest FluidAudio lane.** It had one fewer private-reference word error than v3, no obvious dropped clause or repetition loop, and the lowest latency. Several scored errors were punctuation, casing, or word-boundary formatting rather than recognition.
- v3's default path duplicated short words around long-form seams. The failures were small, but they are the exact stitching class FluidAudio's long-transcription documentation warns about.
- Disabling mel context made v3 worse on this English corpus (3.87% WER). Dual-decode arbitration produced the same transcript while doubling median latency, so neither alternate is justified here.
- FluidAudio v2 was about 6× faster than whisper.cpp Medium.en at the median and completed the 93.5-second fixture in 238 ms because four 15-second windows run concurrently. Its raw Aqua-reference WER was effectively tied with Medium.en (3.21% vs. 3.13%).
- transcribe.cpp v3 remained closest to Aqua (2.55%), but FluidAudio's v2 transcript is qualitatively competitive and avoids the young native runtime.

## Cancellation

A Swift task was cancelled about 10 ms into the 93.5-second fixture. FluidAudio v2 returned `CancellationError` 75 ms later; v3 returned it 110 ms later. No dependency patch was required.

## Integration and maintenance

- The tested v0.15.5 tag is source-only SwiftPM: no external package dependency or binary target. It compiles local `FastClusterWrapper` and `MachTaskSelfWrapper` C/C++ targets alongside the monolithic `FluidAudio` library.
- Current FluidAudio `main` has already added a mandatory `NemoTextProcessing.xcframework`. That rapid dependency change is evidence for pinning the exact qualified tag rather than following a broad version range.
- Production should follow [Hex's pinned FluidAudio Parakeet client](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/ParakeetClient.swift): actor-owned loaded models, explicit cache validation, a fresh decoder state per file, and FluidAudio's complete-file transcription API. MiniWhisper must not replace FluidAudio's chunker or merger.
- The package is not modular: importing Parakeet compiles the repository's TTS, diarization, and other ASR implementations too. Dead stripping limits the shipped binary, but build surface and compiler warnings remain broader than MiniWhisper needs.
- v0.15.5 repeatedly logged `E5RT ... zero shape error` while loading v2 on macOS 26.5.2, then recovered and produced deterministic output. It did not affect results, but should be tracked before declaring the integration quiet.
- Ordinary TDT v2/v3 remains stateless 15-second chunking plus overlap merge, not genuine cache-aware streaming. That is acceptable for hold-release dictation; FluidAudio's separate Parakeet EOU model is the genuine streaming family.

## Artifact pins

- FluidAudio v0.15.5: `19600a485baa4998812e4654b70d2bab8f2c9949`
- Parakeet v2 Core ML: `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39`, 444 MiB required files
- Parakeet v3 Core ML: `FluidInference/parakeet-tdt-0.6b-v3-coreml@aed02740059203c4a87495924f685de3722ae9ce`, 474 MiB required files
- Per-file SHA-256 values: [`fluid-audio-model-hashes.txt`](fluid-audio-model-hashes.txt)

## Prototype verdict

**FluidAudio v0.15.5 + Parakeet TDT 0.6B v2 is viable for MiniWhisper.** It provides the preferred model family through a substantially more established Swift dictation ecosystem, with excellent release latency, working cancellation, low observed process RSS, and competitive personal-corpus quality.

The costs are a three-and-a-half-minute first specialization, 15-second stitching complexity, a broad monolithic package, pre-1.0 update discipline, and one noisy Core ML diagnostic. Thurston tentatively selected this direction while retaining whisper.cpp Medium.en as fallback.

Raw fixture outputs are intentionally retained only under the gitignored `.artifacts/results/` directory.
