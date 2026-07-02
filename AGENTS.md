# MiniWhisper

MiniWhisper is a macOS menu bar dictation app using local whisper.cpp for speech-to-text. It's a SwiftUI app that lives in the menu bar (NSStatusItem) and provides global hotkey-triggered transcription.

## User Context

The developer is new to Swift/macOS but experienced in Python, Scala, and Go. When writing code or making decisions:

- Explain Swift-specific patterns and idioms
- Clarify macOS/Apple framework conventions (AppKit, AVFoundation, etc.)
- Note when something is "the Swift way" vs a general pattern
- Explain any non-obvious syntax (property wrappers, result builders, etc.)

## Commands (via mise)

### Setup

```sh
brew install mise
./scripts/mise-setup
```

### Development

```sh
mise run build          # Build the app
mise run test           # Run all tests (app + UI)
mise run test-packages  # Fast package-only tests (prefer this for quick feedback)
mise run format         # Format code with swift-format
mise run run            # Build and run the app
mise run run-fresh      # Reset mic permission, then build and run
./scripts/capture_menu_screenshot [output.png]  # Screenshot menu dropdown (app must be running)
```

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, NSStatusItem menu)
- `Packages/AudioCapture` — AVAudioEngine mic capture, ring buffer, VAD
- `Packages/ASREngine` — transcription protocol + whisper.cpp wrapper
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — global hotkey (Carbon API)
- `Frameworks/` — whisper.xcframework (added later)

Design principle: App target is a thin shell; business logic lives in packages.

## Code Style

- 2-space indentation
- Swift 6.2 with strict concurrency
- Swift Testing framework (`import Testing`, `@Test`, `#expect`) — not XCTest
- No external dependencies except whisper.cpp — use Apple frameworks only
