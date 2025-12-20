# MiniWhisper

macOS menu bar dictation app using local whisper.cpp for speech-to-text.

## Commands (via justfile)

- `just build` — build app
- `just test` — run all tests (app + UI)
- `just test-packages` — fast package-only tests
- `swift test --package-path Packages/AudioCapture --filter testName` — single test
- `just format` — format code (swift-format)
- `just build-strict` — build with strict concurrency + warnings as errors

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, MenuBarExtra)
- `Packages/AudioCapture` — AVAudioEngine mic capture, ring buffer, VAD
- `Packages/ASREngine` — transcription protocol + whisper.cpp wrapper
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — global hotkey (Carbon API)
- `Frameworks/` — whisper.xcframework (added later)

## Code Style

- 2-space indent, 100 char line length (see .swift-format)
- Swift 6.2, Swift Testing framework
- No external deps except whisper.cpp; use Apple frameworks only
