# Development

## Running the app

```sh
mise trust && mise bootstrap
```

### Day to day

```sh
mise run build          # Build the app
mise run test           # Run app unit tests (headless)
mise run test:ui        # Full XCUITest suite — takes over the screen; prefer a surface slice
mise run test:ui:<surface>  # One surface's UI tests (onboarding, menu, dictionary, history, settings, pill)
mise run test:packages  # Fast package-only tests (prefer this for quick feedback)
mise run lint           # Run the pre-commit formatting, linting, build, and package-test gate
mise run format         # Format code with SwiftFormat
mise run mw             # Build and run MiniWhisper
mise run mw:fresh                 # Reset the dev channel, then build and run
FRESH_MODEL=1 mise run mw:fresh   # Also delete the speech model to exercise its full setup path
mise run reset [dev|nightly|release]  # Reset one channel's TCC grants and setup state
mise run logs                     # run in background; streams and tees to .build/miniwhisper.log
mise run benchmark      # Run deterministic interaction performance budgets
mise run benchmark:live # Build, launch, measure three real capture cycles, and enforce UX budgets
./scripts/capture_menu_screenshot [output.png]  # Screenshot menu dropdown (app must be running)
```

## Channels

Three build configurations produce three separate apps, so all three can be installed at once and none of them can borrow another's permissions or state.

| configuration | app                     | bundle identifier                      | built by              |
| ------------- | ----------------------- | -------------------------------------- | --------------------- |
| Debug         | MiniWhisper Dev.app     | `com.thurstonsand.MiniWhisper.dev`     | `mise run build`      |
| Nightly       | MiniWhisper Nightly.app | `com.thurstonsand.MiniWhisper.nightly` | CI, on push to `main` |
| Release       | MiniWhisper.app         | `com.thurstonsand.MiniWhisper`         | CI, on a `v*` tag     |

`benchmark:live` requires microphone permission and a downloaded engine model. Quit MiniWhisper before running it. Logs at `.build/{miniwhisper-performance.log,miniwhisper-performance-app.log}`.

## Architecture

- `MiniWhisper/` — SwiftUI app target (thin shell, NSStatusItem menu, TCA features and clients)
- `Packages/AudioCapture` — AVAudioEngine mic capture, input-device selection and observation, canonical whole-utterance accumulation, level metering
- `Packages/ASREngine` — silence gate + transcription, vocabulary boost and corrections
- `Packages/SpeechDictionary` — the `dictionary.json` entry model and codec
- `Packages/FieldContext` — focused-field capture payload, fallback taxonomy, and the transcript join rules
- `Packages/TranscriptCleanup` — optional LLM cleanup client
- `Packages/HotkeyListener` — event pipeline routing action-bound bindings and the chord recorder
- `Packages/History` — history log model, retention policy, and the audio vault
- `Packages/AppSettings` — the `settings.json` model and store, aggregating settings from the feature packages

Design principle: the app target is a thin shell; business logic lives in packages. Features (`@Reducer`) orchestrate, clients (`@DependencyClient`) wrap system boundaries, pure decision logic gets plain unit tests in its package.

## Accessibility contract

`mise run test:ui` runs the curated XCUITest manifest for onboarding, the menu, About, the settings window, and every pill presentation. It commandeers the screen and focus, so it is deliberately excluded from `mise run test` and the lint gate: run it when you are specifically testing something interactive, or as an end-to-end pass when concluding a unit of work — not habitually. Debug UI-test launches select deterministic production surfaces with `MINIWHISPER_AGENT_SCENE`; the supported scene catalogue and state mutations live in `AgentDriveabilityScene.swift` and `AgentDriveabilitySceneDriver.swift`. This is an internal test seam, not a demo mode, and Release builds fail fast if the variable is set.
