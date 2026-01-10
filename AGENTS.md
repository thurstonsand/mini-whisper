# MiniWhisper

macOS menu bar dictation app using local whisper.cpp for speech-to-text.

## Behavior

I am brand new to Swift/MacOS development, so I would appreciate some extra explanations of things that you're doing, code that you're writing, decisions that you're making, and any other insights you can provide.
However, I am an experienced developer with plenty of experience with other languages: Python, Scala, Golang. I understand the concepts, I'm just foreign to the world of Apple development.

## Commands (via mise)

- `mise run build` — build app
- `mise run test` — run all tests (app + UI)
- `mise run test-packages` — fast package-only tests
- `swift test --package-path Packages/AudioCapture --filter testName` — single test
- `mise run format` — format code (swift-format)
- `mise run run` — build and run app
- `mise run run-fresh` — reset mic permission then build and run
- `./scripts/capture_menu_screenshot [output.png]` — screenshot menu dropdown (app must be running)

### Setup

```sh
brew install mise
./scripts/mise-setup
```

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, NSStatusItem menu)
- `Packages/AudioCapture` — AVAudioEngine mic capture, ring buffer, VAD
- `Packages/ASREngine` — transcription protocol + whisper.cpp wrapper
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — global hotkey (Carbon API)
- `Frameworks/` — whisper.xcframework (added later)

## Code Style

- 2-space indent, 100 char line length (see .swift-format)
- Swift 6.2, Swift Testing framework
- No external deps except whisper.cpp; use Apple frameworks only
