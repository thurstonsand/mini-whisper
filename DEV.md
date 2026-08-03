# Development

## Running the app

```sh
mise trust && mise bootstrap
```

### Day to day

```sh
mise run build          # Build the app
mise run test           # Run app unit tests (headless)
mise run test-ui        # Interactive XCUITest suite — takes over the screen, keyboard, and focus
mise run test-packages  # Fast package-only tests (prefer this for quick feedback)
mise run lint           # Run the pre-commit formatting, linting, build, and package-test gate
mise run format         # Format code with SwiftFormat
mise run mw             # Build and run MiniWhisper
mise run mw-fresh                 # Reset TCC permissions and onboarding, then build and run
FRESH_MODEL=1 mise run mw-fresh   # Also delete the speech model to exercise its full setup path
mise run logs                     # run in background; streams and tees to .build/miniwhisper.log
mise run benchmark      # Run deterministic interaction performance budgets
mise run benchmark-live # Build, launch, measure three real capture cycles, and enforce UX budgets
./scripts/capture_menu_screenshot [output.png]  # Screenshot menu dropdown (app must be running)
```

Debug builds are `com.thurstonsand.MiniWhisper.dev` and show up as "MiniWhisper Dev"; Release builds keep `com.thurstonsand.MiniWhisper`. macOS keys permissions by bundle identifier and signing identity, so this is what lets a locally built app hold its own Input Monitoring, Microphone, and Accessibility grants alongside an installed release build — `mise run reset-permissions` only ever touches the dev identity. Settings, onboarding markers, and the downloaded model still live in the shared `~/Library/Application Support/MiniWhisper`, so `mw-fresh` also clears the installed build's onboarding markers. The OSLog subsystem stays `com.thurstonsand.MiniWhisper` in both configurations, so `mise run logs` covers either build.

`benchmark-live` requires microphone permission and a downloaded engine model. Quit MiniWhisper before running it. Logs at `.build/{miniwhisper-performance.log,miniwhisper-performance-app.log}`.

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, NSStatusItem menu, TCA features and clients)
- `Packages/AudioCapture` — AVAudioEngine mic capture, canonical whole-utterance accumulation, level metering
- `Packages/ASREngine` — silence gate + transcription
- `Packages/FieldContext` — focused-field capture payload, fallback taxonomy, and the transcript join rules
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — pinned-modifier event pipeline and hold/latch state machine

Design principle: the app target is a thin shell; business logic lives in packages. Features (`@Reducer`) orchestrate, clients (`@DependencyClient`) wrap system boundaries, pure decision logic gets plain unit tests in its package.

## Accessibility contract

`mise run test-ui` runs the curated XCUITest manifest for onboarding, the menu, About, and every pill presentation. It commandeers the screen and focus, so it is deliberately excluded from `mise run test` and the lint gate: run it when you are specifically testing something interactive, or as an end-to-end pass when concluding a unit of work — not habitually. Debug UI-test launches select deterministic production surfaces with `MINIWHISPER_AGENT_SCENE`; the supported scene catalogue and state mutations live in `AgentDriveabilityScene.swift` and `AgentDriveabilitySceneDriver.swift`. This is an internal test seam, not a demo mode, and Release builds fail fast if the variable is set.
