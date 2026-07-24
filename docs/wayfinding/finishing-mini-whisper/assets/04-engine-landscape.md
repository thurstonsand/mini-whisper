# Engine landscape: whisper.cpp, models, streaming, and Parakeet

Research snapshot: 2026-07-18. Facts below are pinned to immutable upstream revisions where possible. Recommendations are explicitly labeled and are not product decisions.

## Conclusion

New project facts change the leading recommendation: dictation is English-only, and Whispering plus everything in its installed stack is allowlisted. Whispering's native path is not whisper.cpp; at the inspected revision it uses `transcribe-cpp` 0.1.2 over `transcribe.cpp`, Metal, and GGUF models, including Parakeet TDT v3. Current [`transcribe.cpp` v0.1.3](https://github.com/handy-computer/transcribe.cpp/releases/tag/v0.1.3) now publishes a Swift XCFramework and supports both Whisper and Parakeet behind one model-loading API.

**Recommendation for the decision benchmark:** evaluate `transcribe.cpp`/Metal first because it provides the cleanest model seam. Use English Parakeet TDT 0.6B v2 `Q5_K_M` as the leading quality/latency candidate, Whisper large-v3-turbo `Q5_K_M` as the Whisper quality control, and Whisper `base.en` `Q5_K_M` as the small-footprint control. Upstream's full LibriSpeech test-clean results report 1.70%, 2.03%, and 4.16% WER respectively, but a personal dictation corpus—not LibriSpeech—must choose the product default. If `transcribe.cpp` fails that benchmark or integration smoke test, the original whisper.cpp/Metal `large-v3-turbo-q5_0` path remains the conservative fallback.

“Metal,” “GGUF,” and “Core ML” are not competing model formats. Metal is an execution backend, GGUF/GGML are weight containers, and Core ML is a separate Apple runtime plus model representation. On Apple Silicon the practical default is Metal with quantized weights. The container only decides which runtime can load the model; it does not itself make inference fast.

The first model import should copy into managed Application Support storage. The app owns the path; a later cache-management surface can enumerate and delete managed models. Security-scoped bookmarks remain a later “reference in place” option.

The engine API should remain one cancellable `async throws` batch operation, with model selection outside that operation. This separates two axes: another compatible model can be loaded by the same concrete runtime, while a genuinely different runtime conforms to the same protocol. Incremental events stay an additive capability for a streaming model rather than infecting the batch MVP.

## Assumptions and unknowns

Verified project facts:

- MiniWhisper targets macOS 14+ on arm64 and is currently sandboxed.
- Dictation is English-only. A multilingual model is still acceptable when its measured quality/latency balance is better.
- Whispering and its installed dependencies are allowlisted. Its inspected native stack establishes direct precedent for `transcribe.cpp`/GGUF/Metal inference; it does not establish precedent for FluidAudio, which is verified unavailable.
- Developer ID signing and notarization credentials already exist in the adjacent GhosttyKit release pipeline.
- `Packages/ASREngine` is an empty SwiftPM shell, while the repository-level `Frameworks/` directory is empty.
- The current model-size enum is provisional and cannot represent a runtime, model family, file, or quantization.

The remaining material unknown is the target Apple Silicon chip, GPU core count, memory size, and thermal envelope. The comparison below assumes short personal-dictation utterances, usually 5–60 seconds, local 16 kHz mono audio, transcription rather than translation, and an Apple Silicon Mac with at least 16 GB unless a row says otherwise.

## 1. Reproducible native XCFramework path

### Leading candidate: transcribe.cpp

Whispering at [`cb12bccfdeba`, inspected 2026-07-18](https://github.com/EpicenterHQ/epicenter/tree/cb12bccfdeba2ba6bad65bd905d78ea92130e99d) resolves the Rust `transcribe-cpp` and `transcribe-cpp-sys` crates at 0.1.2, enabling their Metal feature on macOS ([manifest](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/Cargo.toml), [lockfile](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/Cargo.lock)). That is direct allowlist precedent for the underlying `transcribe.cpp`/GGUF/Metal path, not FluidAudio.

Current [`transcribe.cpp` v0.1.3 (`a94e021ef658`), published 2026-07-12](https://github.com/handy-computer/transcribe.cpp/releases/tag/v0.1.3), ships a 13 MB `TranscribeCpp.xcframework.zip` release asset with SHA-256 `b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd`. Its official Swift package wraps a C module and exposes batch, cancellation, backend selection, and streaming APIs ([Swift package](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift/Package.swift), [Swift binding](https://github.com/handy-computer/transcribe.cpp/tree/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift)). The upstream builder emits a dynamic macOS universal framework with Metal embedded in the arm64 slice and a CPU-only x86_64 slice:

```sh
mkdir -p .build Packages/ASREngine/Frameworks
git clone https://github.com/handy-computer/transcribe.cpp.git .build/transcribe.cpp
git -C .build/transcribe.cpp checkout --detach a94e021ef658dc7c788837341a13f6acea3baf3c
test "$(git -C .build/transcribe.cpp rev-parse HEAD)" = a94e021ef658dc7c788837341a13f6acea3baf3c
(
  cd .build/transcribe.cpp
  TRANSCRIBE_XCFRAMEWORK_SLICES=macos ./scripts/ci/build_xcframework.sh
)
ditto .build/transcribe.cpp/bindings/swift/build-apple/TranscribeCpp.xcframework \
  Packages/ASREngine/Frameworks/TranscribeCpp.xcframework
```

Pinning the release asset is also reproducible when its published digest is verified. Building from source is preferable for auditing exactly which native code enters the installed app; using the release archive is preferable for shorter CI. The local benchmark should decide runtime behavior before the packaging choice matters.

### Conservative fallback: whisper.cpp

The current stable whisper.cpp release is [`v1.9.1` (`f049fff95a08`), published 2026-06-19](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.1). The current source snapshot inspected here is [`080bbbe85230`, committed 2026-07-11](https://github.com/ggml-org/whisper.cpp/commit/080bbbe85230f624f0b52127f1ae1218247989f9). Both versions of [`build-xcframework.sh`](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/build-xcframework.sh) require CMake 3.28+, Xcode, `libtool`, and `dsymutil`, then produce `build-apple/whisper.xcframework`.

The supplied script is not a macOS-only builder. It builds iOS, visionOS, tvOS, and macOS slices. Its macOS framework is universal `arm64;x86_64`, with a macOS 13.3 deployment floor, so it contains the arm64 slice MiniWhisper needs. Xcode selects the macOS library from the XCFramework; the copied macOS framework remains universal unless a later packaging step thins it. There is no need to patch the build merely to run on arm64.

The audited release build can be reproduced as follows:

```sh
mkdir -p .build Packages/ASREngine/Frameworks
git clone https://github.com/ggml-org/whisper.cpp.git .build/whisper.cpp
git -C .build/whisper.cpp checkout --detach f049fff95a089aa9969deb009cdd4892b3e74916
test "$(git -C .build/whisper.cpp rev-parse HEAD)" = f049fff95a089aa9969deb009cdd4892b3e74916
(
  cd .build/whisper.cpp
  ./build-xcframework.sh
)
ditto .build/whisper.cpp/build-apple/whisper.xcframework \
  Packages/ASREngine/Frameworks/whisper.xcframework
find Packages/ASREngine/Frameworks/whisper.xcframework -type f \
  | LC_ALL=C sort \
  | while IFS= read -r file; do shasum -a 256 "$file"; done \
  > Packages/ASREngine/Frameworks/whisper.xcframework.sha256
```

Pin the full source hash in the eventual build script and record the produced artifact checksum plus Xcode and CMake versions. VoiceInk's current Makefile is useful prior art but not reproducible: it clones the old `ggerganov/whisper.cpp` URL or runs `git pull`, then builds whatever branch head happens to exist ([VoiceInk `69ed170c1d7f`, 2026-07-16](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f/Makefile)).

The package-owned destination above is intentional. Apple's local SwiftPM binary-target form expects the XCFramework inside the package repository. A repository-level `Frameworks/` artifact cannot be referenced by escaping the `Packages/ASREngine` package root. The eventual package should therefore keep the selected binary under `Packages/ASREngine/Frameworks/` and declare it as a binary target; `ASREngine` then imports either `CTranscribe` or `whisper` without app-target magic.

Do **not** create `assets/04-engine-landscape/` for executable build machinery. This file is an auditable research record, and its shell blocks are recipes. When implementation chooses the runtime, add one maintained script under the repository's `scripts/` directory, pin its upstream revision and expected checksums in direct declarations, and have local builds and CI call that same script. Generated XCFrameworks belong under the owning package and should stay out of Git unless their size/review policy is decided explicitly. Build infrastructure hidden under documentation would survive until the first person reasonably deletes “old research.”

Both upstream XCFrameworks are dynamic. The selected framework must be embedded and signed before the outer app. Standard Xcode archive/export signing can do this through “Embed & Sign”; a custom release script must sign inside-out and then verify the whole bundle. The adjacent GhosttyKit pipeline is sufficient precedent: `.github/workflows/release.yml` imports the Developer ID certificate with `apple-actions/import-codesign-certs`, while `scripts/build-release-archive.sh` signs nested executables before the containing app and submits the archive with `notarytool`. MiniWhisper can reuse those secrets and workflow shape; no special non-Xcode signing system is required.

Verify the archive rather than trusting the project editor:

```sh
find MiniWhisper.app/Contents/Frameworks -maxdepth 2 -type d -name '*.framework' -print
otool -L MiniWhisper.app/Contents/MacOS/MiniWhisper
codesign --verify --deep --strict MiniWhisper.app
```

If the XCFramework is instead added directly to the Xcode project, use “Embed & Sign.” That path is simpler in the UI but leaves the `ASREngine` package unable to compile independently, so the package-owned binary target remains preferable.

### Model container, quantization, and backend are separate choices

| Layer | Examples | What it changes |
| --- | --- | --- |
| Model architecture/checkpoint | Whisper `base.en`, Whisper Turbo, Parakeet TDT v2 | Accuracy, language coverage, decoder behavior, and fundamental compute cost. This dominates the quality/latency tradeoff. |
| Weight container | whisper.cpp's custom GGML `.bin`; transcribe.cpp's `.gguf` | Which runtime can load the weights and what metadata lives beside them. A container is not an accelerator. |
| Quantization | F16, Q8, Q6, Q5, Q4 | Disk/RAM and often throughput, with a model- and runtime-specific accuracy tradeoff. |
| Execution backend | CPU, Metal GPU, Core ML/ANE | Where computation runs. This dominates hardware utilization. |

For Apple Silicon, **Metal is the default backend recommendation**. Both audited builders embed their Metal shader library; no separate `.metallib` should be copied. `transcribe.cpp` selects Metal automatically on arm64 Apple builds and exposes explicit backend selection. whisper.cpp sets `GGML_METAL=ON` and `GGML_METAL_EMBED_LIBRARY=ON`; at runtime keep `use_gpu` enabled, set `flash_attn = true`, and confirm the startup log identifies the Apple GPU.

**Core ML is not a faster “format” of the same file.** In the whisper.cpp path, Core ML support is compiled into the framework, but ANE execution requires a separate `ggml-<model>-encoder.mlmodelc` directory beside the GGML model. It accelerates only the Whisper encoder, incurs a first-run compile, and leaves decoding in whisper.cpp ([Core ML documentation](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/README.md#core-ml-support)). The official store provides encoder archives for unquantized model names; VoiceInk likewise fetches them only for non-q5/non-q8 models ([VoiceInk model manager](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f/VoiceInk/Transcription/Whisper/WhisperModelManager.swift)). It is a legitimate later benchmark lane, not the simplest first artifact.

The clearest initial combination is therefore **quantized GGUF + Metal through transcribe.cpp**, because one runtime can load multiple Whisper and Parakeet families. If the project retains whisper.cpp, use **quantized GGML `.bin` + Metal**. Do not compare “GGUF vs. Metal”; compare complete tuples such as `(runtime, checkpoint, quantization, backend)` on the target Mac.

### The official Swift example is batch prior art

The official SwiftUI example wraps one C context in a Swift `actor` because the same whisper context must not be used concurrently, caps worker threads, enables flash attention on device, records a complete WAV, reads all samples, calls `whisper_full`, and then concatenates segments ([`LibWhisper.swift`](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/examples/whisper.swiftui/whisper.cpp.swift/LibWhisper.swift), [`WhisperState.swift`](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/examples/whisper.swiftui/whisper.swiftui.demo/Models/WhisperState.swift)). That is the relevant MVP shape. It is not a streaming wrapper.

VoiceInk follows the same direct shape: an actor owns the C context, enables Metal flash attention, calls `whisper_full` over a whole decoded WAV, and copies imported `.bin` files into its managed model directory ([wrapper](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f/VoiceInk/Transcription/Whisper/LibWhisper.swift), [service](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f/VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift)). Its `Atomics` and `Zip` dependencies are not acceptable MiniWhisper dependencies; the useful part is the direct C API shape.

Hex is no longer whisper.cpp prior art. At [`ca9642799024`, 2026-07-09](https://github.com/kitlangton/Hex/commit/ca9642799024), Hex routes Whisper models through WhisperKit 0.15.0 and Parakeet v2/v3 through FluidAudio 0.15.5, both pinned in `Package.resolved` ([routing and managed model folders](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/TranscriptionClient.swift), [Parakeet client](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/ParakeetClient.swift)). It is useful evidence for actor-owned loaded models and explicit cache validation, not evidence for a direct whisper.cpp integration.

## 2. Runtime and model recommendation

### Verified cross-model data from one runtime

`transcribe.cpp` v0.1.3 is unusually useful evidence because it publishes GGUFs, full LibriSpeech test-clean WER, and end-to-end mel+encode+decode timings for both Whisper and Parakeet through the same runtime. That removes several apples-to-oranges comparisons from the initial screen.

| Candidate | Language | Q5 size | Reported WER | Directional M4 Max Metal latency | Role in local benchmark |
| --- | --- | ---: | ---: | ---: | --- |
| Parakeet TDT 0.6B v2 `Q5_K_M` | English | 547 MB | 1.70% | Q4: 67 ms for 11 s audio | **Leading candidate.** Best reported English accuracy and fastest high-quality batch path in this set. |
| Parakeet TDT 0.6B v3 `Q5_K_M` | 25 European languages | 565 MB | 1.92% | Q4: 76 ms for 11 s audio | Multilingual control. Use it if personal dictation quality beats v2 despite v2's benchmark advantage. |
| Whisper large-v3-turbo `Q5_K_M` | Multilingual | 591 MB | 2.03% | Q4: 289 ms for 11 s audio | Whisper quality/control path; more mature model behavior and prompt support. |
| Whisper `base.en` `Q5_K_M` | English | 61 MB | 4.16% | Q4: 50 ms for 11 s audio | Tiny-footprint control. It is fastest here, but gives up substantial benchmark accuracy. |

The M4 Max numbers are means after warmup on macOS 26.4.1 and are not target-machine predictions. The project reports Parakeet v2 Q8/Q4 at 68/67 ms, v3 at 74/76 ms, Turbo at 286/289 ms, and `base.en` at 50/50 ms for the 11-second JFK sample. Q5 latency was not published, so the table deliberately shows the measured Q4 neighbor rather than fabricating interpolation. Sources: [Parakeet v2](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/parakeet-tdt-0.6b-v2.md), [Parakeet v3](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/parakeet-tdt-0.6b-v3.md), [Turbo](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/whisper-large-v3-turbo.md), and [`base.en`](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/docs/models/whisper-base.en.md).

The old whisper.cpp facts remain relevant to the fallback: its custom GGML `large-v3-turbo-q5_0` is 547 MiB, `base.en-q5_1` is 59.7 MB, and integer quantization reduces storage/RAM. whisper.cpp's `whisper-bench` is only an encoder microbenchmark, though, so it cannot fairly select an end-to-end dictation model. Distil-Large-v3 remains outside the first bakeoff: its own card is promising, but whisper.cpp still warns that its distilled chunk strategy can be suboptimal, and transcribe.cpp's unified published matrix does not include it.

### Local benchmark is required

Run the four Q5 candidates above on the actual work Mac before choosing the default. Use the same runtime and Metal backend first so the model comparison is controlled. Only after selecting a model should the benchmark compare adjacent Q4/Q8 quantizations or the whisper.cpp fallback.

The fixture set should contain 20–30 real utterances recorded with the intended microphone and environment: short commands, 5/15/60-second dictation, code and product names, punctuation-heavy prose, corrections/fillers, quiet speech, and background noise. Record exact hardware, OS, runtime commit, model SHA, quantization, cold model-load time, warm release-to-final-text latency, peak resident memory, transcript edit distance, punctuation/casing failures, hallucinations, and cancellation latency. Keep silence rejection scored separately so a VAD improvement cannot disguise ASR quality.

**Recommendation, not decision:** begin the bakeoff with Parakeet v2 `Q5_K_M`. Its being English-only is now an advantage, not a limitation. Keep v3 because multilingual training may still generalize better to Thurston's voice or vocabulary; the personal corpus gets the last word. Use Turbo when Whisper-specific prompting or robustness wins enough accuracy to justify slower decode. Use `base.en` only if its personal error rate is acceptable—the storage win is real, but so is the benchmark gap.

## 3. Import existing models into managed storage first

The first model-management feature should select an existing `.gguf` or `.bin`, copy it into the app's Application Support model directory, validate it with the selected runtime, persist the managed model identity, and load it. It should not derive a download URL from `WhisperModelSize` or leave the app dependent on the source file's future location.

Recommended import transaction:

1. `NSOpenPanel` grants temporary access to the user-selected file.
2. Copy to a uniquely named staging file under `Application Support/MiniWhisper/Models/`.
3. Compute SHA-256 and ask the runtime to load/inspect the model; the model metadata, not its extension or filename, determines family and capabilities.
4. Atomically rename the validated staging file into managed storage and persist a small descriptor containing stable ID, runtime kind, managed filename, hash, and display metadata.
5. If any step fails, remove the staging file and leave the previous selected model untouched.

This duplicates the source once, but MiniWhisper then owns path stability, deletion, and backup/cache policy. VoiceInk's local import likewise copies into its model directory. A later “clear model cache” action should first unload the selected context, remove every managed model and partial import, clear the selected descriptor, and return the app to a deliberate “model required” state. Do not silently fall back to an arbitrary model.

Referencing an external model in place remains a valid future feature. Because MiniWhisper is sandboxed, persistence would require an app-scoped security-scoped bookmark, stale-bookmark handling, and balanced `startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()` calls for the loaded context's lifetime ([Apple documentation](<https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()>)). None of that complexity is needed for the managed-copy MVP.

## 4. Sliding re-decode is not stateful streaming

### whisper.cpp's stream example

The upstream [`examples/stream` README](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/examples/stream/README.md) calls the implementation “naive.” In the default example it samples every 500 ms and repeatedly calls `whisper_full` over up to the last 5 seconds. The C++ source carries a small overlap to mitigate word boundaries and can pass prior output tokens as a prompt when context retention is enabled ([`stream.cpp`](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/examples/stream/stream.cpp)). Its VAD mode waits for activity and then transcribes the retained window.

That is repeated chunk/sliding-window decoding. It may preserve text tokens as a prompt, but it recomputes audio features and encoder work for overlapping audio and revises earlier text. It does not maintain a cache-aware acoustic encoder state that consumes only new frames. `whisper_state` and callbacks in the C API are inference storage and observation mechanisms; their existence does not turn this loop into a streaming model.

For MiniWhisper's hold-release MVP, there is no reason to pay this complexity. Capture one utterance, reject silence, then run one batch transcription on release.

### Hex-like responsiveness does not require live partials

The inspected Hex path is batch: after recording ends it pads very short audio, creates a fresh Parakeet decoder state, and calls FluidAudio's file transcription API. Its near-real-time feel comes from a loaded model and very fast TDT inference, not from words appearing while the microphone is still open ([Hex client](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/ParakeetClient.swift)). Whispering uses the same perceived-latency trick with a different runtime: recording start prewarms its selected GGUF model while capture continues, then release runs one complete batch ([recording prewarm](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/operations/recording.ts), [resident cache](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/src/transcription/model_cache.rs)).

That is the MVP responsiveness target: keep or prewarm the selected model in memory, overlap cold load with recording when necessary, and measure release-to-final-text. Parakeet v2/v3 batch throughput is fast enough upstream to make this credible, but the target Mac must prove it.

Live text is a separate capability. Offline Whisper and offline Parakeet TDT do not become stateful streaming models merely because their batch inference is faster than real time. `transcribe.cpp` does, however, expose a common streaming API and currently supports genuine streaming families including Moonshine Streaming, Nemotron Speech Streaming, and Multitalker Parakeet Streaming ([v0.1.3 model matrix](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/README.md)). That makes it a useful future seam: MVP batch callers remain unchanged, while a streaming-capable model can later provide committed/tentative updates through the additive incremental protocol. Model quality, punctuation, latency, and license still need their own design pass.

### FluidAudio has both kinds; the names matter

At [`FluidAudio` `300165b240c4`, committed 2026-07-16](https://github.com/FluidInference/FluidAudio/commit/300165b240c45375add402265f62410b6df33cf1), ordinary Parakeet TDT v2/v3 is a **sliding-window batch pipeline**. `SlidingWindowAsrManager` processes roughly 15-second overlapping chunks and stitches them. Hex's integration uses that batch path, creating a fresh `TdtDecoderState` for each file. It is near-real-time throughput, not genuinely stateful streaming.

FluidAudio separately exposes **true cache-aware streaming** through [`StreamingAsrManager`](https://github.com/FluidInference/FluidAudio/blob/300165b240c4/Sources/FluidAudio/ASR/Parakeet/Streaming/StreamingAsrManager.swift). `StreamingEouAsrManager` and streaming Nemotron managers append incoming buffers, process complete chunks while retaining model state, emit partials, flush residual audio on `finish()`, reset session state without unloading models, and expose optional token/EOU timestamps. The Parakeet EOU model has 160, 320, and 1280 ms variants. NVIDIA describes the source model as a 120M-parameter English cache-aware FastConformer-RNNT with an `<EOU>` token, 80–160 ms advertised latency, and no punctuation or capitalization ([NVIDIA model card](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1)). FluidAudio's own M2 LibriSpeech benchmark reports 4.88% average WER and 19.25× real-time for the 320 ms variant versus 8.23% and 5.78× for 160 ms ([benchmark snapshot](https://github.com/FluidInference/FluidAudio/blob/300165b240c4/Documentation/Benchmarks.md#streaming-asr-parakeet-eou)). Those are upstream project results, not MiniWhisper measurements.

### whisper.cpp now has a third Parakeet path

whisper.cpp merged native NVIDIA Parakeet TDT v3 support in [PR #3735 on 2026-06-16](https://github.com/ggml-org/whisper.cpp/pull/3735), shipped it in v1.9.0/1.9.1 source, and current master now includes `libparakeet.a` and `parakeet.h` in the Apple XCFramework. The current CLI loads a converted Parakeet TDT 0.6B v3 file and transcribes complete files ([current CLI README](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/examples/parakeet-cli/README.md)). Its C API has contexts, states, `parakeet_full`, and a short-clip `parakeet_chunk`, but no documented live, cache-aware partial-event flow like FluidAudio's EOU manager. Treat it as a new batch TDT engine, not proof of stateful streaming.

One packaging wrinkle is auditable: the v1.9.1 release's `build-xcframework.sh` does not yet combine `libparakeet.a`; current master does. The stable release is sufficient for the Whisper MVP. Native Parakeet should be benchmarked from a later pinned release rather than pulling master merely to obtain a second engine.

## 5. FluidAudio/Parakeet footprint, dependencies, licensing, and allowlist

### Whispering changes the viable native path

Whispering's allowlisted desktop binary embeds `transcribe.cpp` through `transcribe-cpp` 0.1.2, `hf-hub`, audio decoding/resampling crates, and Metal on macOS. Its catalog includes Whisper Tiny Q8, Whisper Small Q4_K_M, and Parakeet TDT v3 Q4_K_M GGUFs; it keeps one loaded model resident, prewarms on recording start, and runs batch inference after release ([catalog](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/src/transcription/catalog.rs), [model cache](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/src/transcription/model_cache.rs)).

That precedent makes a `transcribe.cpp` XCFramework and its GGUF model families viable for MiniWhisper. MiniWhisper need not inherit Whispering's Tauri/Rust/audio stack: the official Swift binding consumes a prebuilt native XCFramework directly and MiniWhisper already owns capture and resampling. It also provides a better model seam than separate Whisper/Parakeet libraries because runtime capability metadata identifies the loaded family and whether it supports batch, timestamps, language selection, cancellation, and streaming.

### FluidAudio dependency graph

FluidAudio main is a Swift 6 package requiring macOS 14+/iOS 17+. Its [`Package.swift` at `300165b`](https://github.com/FluidInference/FluidAudio/blob/300165b240c4/Package.swift) declares no source-package dependencies, but the `FluidAudio` library target depends on:

- `FastClusterWrapper`, a local C/C++ target;
- `MachTaskSelfWrapper`, a local C target;
- `NemoTextProcessing`, a mandatory prebuilt XCFramework downloaded from `FluidInference/text-processing-rs` v0.3.0 with a fixed checksum;
- Foundation, AVFoundation, CoreML, Accelerate/OSLog and other Apple frameworks used by the source;
- model files downloaded separately at runtime from FluidInference Hugging Face repositories unless the registry URL/cache is overridden.

“No package dependencies” therefore does not mean “Apple frameworks only.” The prebuilt `NemoTextProcessing.xcframework` is shipped code. Its source release is Apache-2.0 and directly declares `lazy_static`, with optional `rustfst` and `flate2` for its compiled-FST engine; `Cargo.lock` records their Rust transitive graph ([`Cargo.toml`](https://github.com/FluidInference/text-processing-rs/blob/v0.3.0/Cargo.toml), [`Cargo.lock`](https://github.com/FluidInference/text-processing-rs/blob/v0.3.0/Cargo.lock), [release](https://github.com/FluidInference/text-processing-rs/releases/tag/v0.3.0)). A formal dependency review would need to inspect the shipped binary's enabled features and notices rather than assume every lockfile development dependency is linked.

The relevant runtime model graph is also multi-file:

- TDT v3 default int8: `Preprocessor.mlmodelc` (~0.5 MB), `Encoder.mlmodelc` (~446 MB), `Decoder.mlmodelc` (~23.6 MB), `JointDecisionv3.mlmodelc` (~12.7 MB), and vocabulary (~0.15 MB), about **483 MB required on disk**. The Hugging Face repository totals 2.99 GB because it contains alternate and older artifacts. The v2 model card reports roughly 800 MB peak process memory; v3 must be measured independently.
- Parakeet EOU 320 ms streaming: `streaming_encoder.mlmodelc` (~214 MB), `decoder.mlmodelc` (~7.89 MB), `joint_decision.mlmodelc` (~2.81 MB), and vocabulary, about **225 MB required model data**. Its repository's 320 ms folder totals 448 MB because it also contains conversion scripts and other material.
- Native whisper.cpp Parakeet v3: one converted GGML file. The official ggml-org repository currently offers F16 1.26 GB, q8_0 669 MB, q4_k 416 MB, and q4_0 356 MB variants ([`ggml-org/parakeet-GGUF`](https://huggingface.co/ggml-org/parakeet-GGUF/tree/main)). This path uses whisper.cpp/GGML and Metal rather than FluidAudio/Core ML, so it has a substantially better allowlist shape, but it is brand-new batch support and has not been validated for MiniWhisper.

FluidAudio's model registry defaults to public Hugging Face but supports a programmatic or environment base-URL override ([`ModelRegistry.swift`](https://github.com/FluidInference/FluidAudio/blob/300165b240c4/Sources/FluidAudio/ModelRegistry.swift)). That helps controlled-network deployment but does not remove the runtime code or model-license review.

### Licenses are separate

- FluidAudio source is [Apache-2.0](https://github.com/FluidInference/FluidAudio/blob/300165b240c4/LICENSE).
- `text-processing-rs` source and its NVIDIA NeMo Text Processing-derived notices are Apache-2.0 ([license](https://github.com/FluidInference/text-processing-rs/blob/v0.3.0/LICENSE), [notice](https://github.com/FluidInference/text-processing-rs/blob/v0.3.0/NOTICE)). Each linked Rust crate retains its own license obligations.
- NVIDIA Parakeet TDT 0.6B v2 is English, 600M parameters, requires at least 2 GB RAM in NVIDIA's NeMo reference runtime, and its weights are [CC-BY-4.0](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2).
- NVIDIA Parakeet TDT 0.6B v3 is 600M parameters, supports 25 European languages, and its weights are [CC-BY-4.0](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). NVIDIA's reference support matrix is NeMo 2.4 on Linux/NVIDIA GPUs; Apple support comes from third-party conversions, not NVIDIA's card.
- NVIDIA Parakeet Realtime EOU 120M v1 weights use the [NVIDIA Open Model License](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1), not CC-BY-4.0.
- The FluidInference v3 Core ML repository metadata says CC-BY-4.0 while one paragraph in its model card says Apache-2.0. The original NVIDIA v3 weights are unambiguously CC-BY-4.0, so redistribution should conservatively preserve that attribution unless the artifact owner resolves the inconsistency. The ggml-org converted repository currently labels itself MIT while deriving from the same NVIDIA model; that metadata mismatch also needs resolution before redistribution.

### Allowlist verdict

- **transcribe.cpp/GGUF/Metal: viable precedent.** Whispering already ships this capability and a Parakeet GGUF. MiniWhisper can build, sign, and publish the chosen runtime on the development Mac, then install only the finished artifact at work, so Whispering's exact 0.1.2 version is not a work-machine build constraint. Still pin MiniWhisper's chosen release for reproducibility and rollback.
- **Native whisper.cpp Whisper: viable.** This remains the conservative approved runtime.
- **Native whisper.cpp Parakeet: likely viable but immature.** The runtime is inside whisper.cpp and uses one converted model file, but wait for a release whose Apple builder packages `libparakeet`, resolve converted-weight license metadata, and benchmark it.
- **FluidAudio: not viable.** It is separately verified unavailable and necessarily pulls the `NemoTextProcessing` binary. Whispering does not use it, so Whispering's approval changes nothing about this path.

Licensing and allowlisting are separate. Managed import avoids bundling model weights in MiniWhisper releases, but the app should still preserve model identity/license metadata and surface required attribution for CC-BY Parakeet models.

## 6. Small Swift protocol and model seam

Recommended MVP sketch:

```swift
public struct TranscriptionAudio: Sendable {
  public let samples16kMono: [Float]

  public init(samples16kMono: [Float]) {
    self.samples16kMono = samples16kMono
  }
}

public protocol TranscriptionEngine: Sendable {
  func transcribe(_ audio: TranscriptionAudio) async throws -> String
}
```

This is deliberately small:

- `TranscriptionAudio` names the invariant every current candidate needs and prevents an unlabeled `[Float]` from crossing the package boundary. Audio conversion belongs at the capture/engine edge, not in every caller.
- English is concrete engine configuration, not optional per-call state. MiniWhisper does not need to carry unused multilingual policy through every reducer action.
- The protocol is `Sendable` but not `Actor`. Swift's `Sendable` permits safe use across concurrency domains; requiring every future engine to be an actor would prescribe implementation. The concrete native wrapper should serialize inference according to its C runtime's threading contract.
- Returning `String` is enough for the batch vertical. Segment timestamps, confidence, model identity, and progress have no MVP consumer.

Model swapping stays easy by keeping it **outside** this protocol. The managed model descriptor records a runtime kind and file identity. An engine factory loads that managed URL once and returns a configured engine; changing models replaces the loaded engine instance. The same `TranscribeCppEngine` can load Whisper, Parakeet, or another supported GGUF without a new app-level protocol case, while a genuinely different runtime such as `WhisperCppEngine` conforms to the same two-line interface. Do not pass a model URL on every transcription call or encode checkpoints in a closed `WhisperModelSize` enum—the loaded context is expensive state, while model names are data.

Cancellation uses Swift structured concurrency: cancelling the task awaiting `transcribe` must cause `CancellationError`. No actor-isolated `cancel()` method is needed; it may queue behind the blocking inference call and arrive after completion—an impressively decorative cancel button. `transcribe.cpp`'s Swift binding already provides a thread-safe cancellation token polled by its native abort callback ([`Cancellation.swift`](https://github.com/handy-computer/transcribe.cpp/blob/a94e021ef658dc7c788837341a13f6acea3baf3c/bindings/swift/Sources/TranscribeCpp/Cancellation.swift)). Wrap it in `withTaskCancellationHandler`. The whisper.cpp fallback instead bridges the same task contract through `whisper_full_params.abort_callback` ([C API](https://github.com/ggml-org/whisper.cpp/blob/080bbbe85230f624f0b52127f1ae1218247989f9/include/whisper.h)). In both cases the callback state must outlive the native call, and cancellation must be distinguished from a real engine error.

Do not return `AsyncThrowingStream` in the MVP. If a selected model later reports genuine streaming capability, add it without changing batch callers:

```swift
public enum TranscriptionEvent: Sendable, Equatable {
  case partial(String)
  case final(String)
}

public protocol IncrementalTranscriptionEngine: TranscriptionEngine {
  func makeSession() async throws -> any IncrementalTranscriptionSession
}

public protocol IncrementalTranscriptionSession: Sendable {
  var events: AsyncThrowingStream<TranscriptionEvent, any Error> { get }

  func append(_ audio: TranscriptionAudio) async throws
  func finish() async throws
}
```

That future protocol is a seam, not code to add now. A session is necessary because genuine streaming retains decoder/encoder state across appended audio chunks; replaying a complete `TranscriptionAudio` through an event-returning method would merely disguise batch inference. Offline Whisper and Parakeet remain batch engines even under a runtime that also supports streaming families; capability comes from the loaded model, not the container extension.

## Audit trail

Primary snapshots used:

- whisper.cpp [`080bbbe85230`, 2026-07-11](https://github.com/ggml-org/whisper.cpp/tree/080bbbe85230f624f0b52127f1ae1218247989f9); stable [`v1.9.1`, 2026-06-19](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.9.1).
- transcribe.cpp [`v0.1.3` / `a94e021ef658`, published 2026-07-12](https://github.com/handy-computer/transcribe.cpp/tree/a94e021ef658dc7c788837341a13f6acea3baf3c); its Swift XCFramework release digest is recorded in section 1.
- Whispering/Epicenter [`cb12bccfdeba`](https://github.com/EpicenterHQ/epicenter/tree/cb12bccfdeba2ba6bad65bd905d78ea92130e99d), including its `transcribe-cpp` 0.1.2 lock, GGUF catalog, Metal backend, resident cache, and batch transcription path.
- The adjacent GhosttyKit signing reference was inspected locally on 2026-07-18 at `.github/workflows/release.yml` and `scripts/build-release-archive.sh`.
- Hex [`ca9642799024`, 2026-07-09](https://github.com/kitlangton/Hex/tree/ca96427990249223cc31027d14c1f2c9ded57910).
- VoiceInk [`69ed170c1d7f`, 2026-07-16](https://github.com/Beingpax/VoiceInk/tree/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75).
- FluidAudio [`300165b240c4`, 2026-07-16](https://github.com/FluidInference/FluidAudio/tree/300165b240c45375add402265f62410b6df33cf1); Hex's pinned stable dependency is FluidAudio `0.15.5` at `19600a485baa`, 2026-07-07.
- Hugging Face metadata was read on 2026-07-18: OpenAI Turbo [`41f01f3fe87f`, last modified 2024-10-04](https://huggingface.co/openai/whisper-large-v3-turbo/tree/41f01f3fe87f28c78e2fbf8b568835947dd65ed9); Distil-Large-v3 [`8031d2e6ce66`, 2026-04-21](https://huggingface.co/distil-whisper/distil-large-v3/tree/8031d2e6ce6631b7fc45629dddfc00271116d981); converted whisper.cpp models [`5359861c739e`, 2024-10-29](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1).
- NVIDIA model cards were read on 2026-07-18: TDT v2 [`ae9ad07059c7`, last modified 2026-06-29](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2/tree/ae9ad07059c7c739ffaf932226a8fe64ae2620b0), TDT v3 [`7c35754d166c`, 2026-06-29](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/tree/7c35754d166cca382ad1e53e68b01e7c575f3a1d), and Realtime EOU 120M v1 [`a7e2b4629593`, 2025-12-03](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1/tree/a7e2b4629593dce0ec19f600e00e9904353fda2d).
- Converted Parakeet artifacts were read on 2026-07-18: FluidInference TDT v3 [`aed027400592`, last modified 2026-04-30](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/aed02740059203c4a87495924f685de3722ae9ce), FluidInference EOU [`40a23f4c0b33`, 2026-03-14](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml/tree/40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355), and ggml-org Parakeet [`35156454d1a3`, 2026-06-16](https://huggingface.co/ggml-org/parakeet-GGUF/tree/35156454d1a39de06863303dd209fd2bed6ee079).
