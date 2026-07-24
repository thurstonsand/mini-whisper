# MiniWhisper scaffolding

For what you’re building (menu-bar utility, global hotkey, local Whisper/Parakeet, heavy emphasis on testability, near-zero deps), the best “scaffolding” is a hybrid:

1. **Xcode’s built-in macOS App template** (to get a signed, sandboxed app bundle, test targets, entitlements, etc.)
2. **SwiftPM packages inside the repo** (to generate clean, testable “core” modules with minimal tooling)

That combo gives you the closest thing macOS has to a dependency-free, maintainable skeleton.

## 1) Skeleton/scaffolding that stays near-zero-dep

### Recommended repo layout (what to scaffold up front)

- `DictationApp/` (Xcode project; SwiftUI menu bar UX, permissions UI)
- `Packages/`

  - `AudioIO/` (AVAudioEngine capture, ring buffer, level meter, VAD gate)
  - `ASRCore/` (protocols + orchestration; no model specifics)
  - `WhisperEngine/` (wrapper around whisper.cpp XCFramework / C-API)
  - `ParakeetEngine/` (CoreML wrapper; keep as optional module until ready)
  - `CleanupClient/` (OpenAI-compatible “text cleanup” via URLSession)
  - `Hotkeys/` (global hotkey via system APIs)

- `Tests/` live with each package (`swift test` is fast and CI-friendly)

**Why this scaffolding works:** Xcode owns the macOS app bundle and signing; SwiftPM owns everything you want to unit/integration test aggressively.

### Menu-bar app scaffolding (no third-party libs)

- Build as a **SwiftUI menu bar app** using `NSStatusItem` and set `LSUIElement=true` to keep it out of Dock/app
  switcher. ([Nil Coalescing][1])
  (MenuBarExtra is a simpler starting point, but `NSStatusItem` gives more control and is what the app uses now.)

### whisper.cpp integration scaffolding you can copy

Use the **whisper.cpp XCFramework workflow** so your app target isn’t compiling C/C++ every build:

- whisper.swiftui example specifically recommends:

  - build whisper as an XCFramework via `./build-xcframework.sh`
  - then drag `build-apple/whisper.xcframework` into your project for embedding ([Hugging Face][2])

- whisper.cpp’s own releases call out the XCFramework workflow as a major simplification for 3rd-party iOS/macOS integration. ([GitHub][3])

This is essentially “scaffolding-by-example”: start from their SwiftUI sample integration and refactor into your package structure.

### Streaming/progressive transcription scaffolding

whisper.cpp includes a real-time streaming example that runs transcription repeatedly on short steps (it samples every ~500ms and continues decoding), but their sample uses SDL2. ([GitHub][4])
Your “zero-dep macOS” equivalent is: **AVAudioEngine → ring buffer → periodic decode windows**. You get progressive text without SDL2.

## 2) “Which model versions are most performant?”

### Whisper (whisper.cpp)

For dictation-style UX, the best performance lever is _model size + quantization + Metal/CoreML acceleration_.

**Practical picks:**

- **Fastest viable dictation:** `tiny.en-q5_1` (about **31 MiB**) ([Hugging Face][5])
- **Best “speed/quality” default:** `base.en-q5_1` (about **57 MiB**) ([Hugging Face][5])
- **If you can spend more compute for accuracy:** `small.en-q5_1` (**181 MiB**) ([Hugging Face][5])
- **High accuracy but still efficiency-minded:** `large-v3-turbo-q5_0` (**547 MiB**) ([Hugging Face][5])

**Why `large-v3-turbo` is interesting:** whisper.cpp’s own Metal benchmarks show `large-v3-turbo` and its quantized variants are very fast on Apple Silicon (their release notes include detailed timings on M2 Ultra and specifically list `large-v3-turbo-q5_0`). ([GitHub][3])

#### Notes that matter for your constraints

- Use **`.en`** variants if you only need English (smaller/faster, simpler decode path). ([Hugging Face][5])
- Quantization: in practice, `q5_1` is often the “sweet spot”; `q8_0` is larger with slightly better fidelity; either is usually fine for dictation.

### Parakeet

If your goal is _raw throughput and low latency_, Parakeet’s 0.6B variants are specifically positioned for that.

- **English-only:** `nvidia/parakeet-tdt-0.6b-v2` (punctuation/caps + timestamps; long-audio support) ([Hugging Face][6])
- **Multilingual (25 European languages, auto language detect):** `nvidia/parakeet-tdt-0.6b-v3` ([Hugging Face][7])

**Best performance option on macOS (if allowed): Core ML conversions**
If you’re on Apple Silicon and want “fastest practical,” the CoreML-converted Parakeet models are compelling:

- `FluidInference/parakeet-tdt-0.6b-v2-coreml` reports **~110× real-time factor on M4 Pro** and lists macOS 14+ support. ([Hugging Face][8])
- `FluidInference/parakeet-tdt-0.6b-v3-coreml` similarly highlights on-device execution and ~110× RTF in batch mode. ([Hugging Face][9])

Caveat: those CoreML artifacts remove the _runtime dependency_ problem (CoreML is system), but you still need the **pre/post-processing and decoding** logic. If you can’t depend on FluidAudio as a package, you can still treat it as a _reference implementation_ or vendor only what you need (respecting licensing/attribution).

## 3) The shortest path to a usable skeleton (actionable plan)

1. Create Xcode macOS App (SwiftUI) **with Unit Tests + UI Tests enabled**.
2. Convert to a menu-bar-only UX (`NSStatusItem`, `LSUIElement=true`). ([Nil Coalescing][1])
3. Add local SwiftPM packages for core modules (AudioIO/ASRCore/CleanupClient/Hotkeys).
4. Bring in whisper.cpp as an **XCFramework** (build script + embed). ([Hugging Face][2])
5. Start with **`base.en-q5_1`** as your default model and benchmark; keep `tiny.en-q5_1` as your “low-latency mode.” ([Hugging Face][5])
6. Leave Parakeet behind an `ASREngine` protocol until you’re ready; if performance is critical and CoreML is permitted, consider the CoreML Parakeet variants as your endgame. ([Hugging Face][8])

If you want, I can propose a concrete module API surface (protocols + data types + dependency boundaries) that makes Whisper and Parakeet plug-compatible while keeping unit/integration tests straightforward.

[1]: https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI?utm_source=chatgpt.com "Build a macOS menu bar utility in SwiftUI - Nil Coalescing"
[2]: https://huggingface.co/spaces/natasa365/whisper.cpp/blob/5ff87859df5e83d61cd4bfc7d9a42fd4345a5bcb/examples/whisper.swiftui/README.md "examples/whisper.swiftui/README.md · natasa365/whisper.cpp at 5ff87859df5e83d61cd4bfc7d9a42fd4345a5bcb"
[3]: https://github.com/ggml-org/whisper.cpp/releases "Releases · ggml-org/whisper.cpp · GitHub"
[4]: https://github.com/ggml-org/whisper.cpp "GitHub - ggml-org/whisper.cpp: Port of OpenAI's Whisper model in C/C++"
[5]: https://huggingface.co/ggerganov/whisper.cpp "ggerganov/whisper.cpp · Hugging Face"
[6]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2 "nvidia/parakeet-tdt-0.6b-v2 · Hugging Face"
[7]: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 "nvidia/parakeet-tdt-0.6b-v3 · Hugging Face"
[8]: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml "FluidInference/parakeet-tdt-0.6b-v2-coreml · Hugging Face"
[9]: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml "FluidInference/parakeet-tdt-0.6b-v3-coreml · Hugging Face"
