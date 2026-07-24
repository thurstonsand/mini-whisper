# Development

## Running the app

```sh
mise trust && mise bootstrap
```

### Day to day

```sh
mise run build          # Build the app
mise run test           # Run all tests (app + UI)
mise run test-packages  # Fast package-only tests (prefer this for quick feedback)
mise run lint           # Run the pre-commit formatting, build, and package-test gate
mise run format         # Format code with swift-format
mise run mw             # Build and run MiniWhisper
mise run mw-fresh       # Reset mic permission, then build and run
mise run logs           # run in background; streams and tees to .build/miniwhisper.log
./scripts/capture_menu_screenshot [output.png]  # Screenshot menu dropdown (app must be running)
```

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, NSStatusItem menu, TCA features and clients)
- `Packages/AudioCapture` — AVAudioEngine mic capture, ring buffer, level metering
- `Packages/ASREngine` — silence gate + transcription
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — pinned-modifier event pipeline and hold/latch state machine

Design principle: the app target is a thin shell; business logic lives in packages. Features (`@Reducer`) orchestrate, clients (`@DependencyClient`) wrap system boundaries, pure decision logic gets plain unit tests in its package.
