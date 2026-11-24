<!-- markdownlint-disable MD024 -->

# Release notes

## Unreleased

## 0.5.0

Sound themes, an in-app Changelog, faster Settings and History, and clearer error recovery.

### Added

- A Changelog pane in Settings to browse release notes inside the app.
- Sound themes (Drop, Pluck, Hum, Bloom, or No audio) with live preview in Settings, replacing individual system sound pickers.
- Export Metrics in the menu bar to inspect dictation timing and cleanup stats.

### Changed

- About now lives in the Settings sidebar, and the Settings window remembers its position and size.
- Opening Settings shows a Dock icon and appears in ⌘-Tab until the window closes.
- The dictation pill now appears on the display with your focused window and fades out smoothly.
- Failed recordings, transcriptions, pastes, and unreadable settings or history files now show clear notices and recovery actions.
- Setting transcript history to Never stops writing dictations to disk.
- Faster History scrolling and instant switching between Settings panes.

### Fixed

- The activation shortcut no longer gets stuck if a key release happens behind a password prompt or the lock screen.
- Additional cleanup instructions are followed more reliably when Expanded context is enabled.
- Copy Last Transcript stays available after relaunching the app.

## 0.4.0

Screen-aware cleanup, background delivery to where you started dictating, and Return to submit.

### Added

- Expanded context: cleanup can read text or a screenshot from the window you're dictating into so names and terms match what's on screen (requires optional Screen Recording access).
- Press Return during a recording, or right after, to end and submit your dictation.
- Background delivery: dictations land in the app, text field, or tmux pane where you started — even after you switch away — without pulling that window to the front.
- Pressing the shortcut during cleanup starts your next dictation while the current one finishes in the background; a single tap skips cleanup.
- Reasoning effort control for each profile's cleanup model.
- Most accurate now supports any ElevenLabs-compatible speech service.
- History now shows the error message when a cleanup request fails.

### Changed

- Everyday and Most accurate now use Gemini 4 Hydrogen for cleanup, and Fastest uses Qwen 3.8 27B on Cerebras. Existing Claude Haiku users are prompted once to switch or keep Haiku as a Custom profile.
- Removed the separate submit shortcut; Return handles it directly.
- Onboarding lets you practice holding and double-tapping your shortcut, and lets you start with Offline or Custom without an API key.

## 0.3.0

Dictation profiles, AI transcript cleanup, a custom dictionary, dictation history, and a Settings window.

### Added

- Profiles to pick your transcription and cleanup stack (Everyday, Fastest, Offline, Most accurate, or Custom), with per-field overrides.
- Optional AI cleanup pass to fix punctuation, formatting, and spelled-out words, including an on-device S1-mini model for Offline mode.
- A Models library to download, resume, and remove on-device models individually.
- API keys and custom endpoints are verified before being saved.
- Custom Dictionary for vocabulary and spelling corrections, with quick-add from the menu bar and recognition boosting.
- Dictation History with search, audio playback, copy, re-transcription, and retention controls.
- A Settings window for shortcuts, microphone selection, sound effects, and launch at login.
- Paste Last (⌥⌘V) to re-paste your latest transcript wherever your cursor is.
- Onboarding now lets you choose a profile and activation shortcut during setup.

### Changed

- Nightly and Release builds are separate apps with their own permissions and settings, so both can be installed side by side.
- When no text field is focused, your clipboard is left untouched and the pill offers Paste Last instead.

### Fixed

- Double-tapping to record hands-free no longer plays the start sound twice.

## 0.2.0

Smarter spacing and capitalization around your cursor, with one fewer macOS permission required.

### Added

- Context-aware spacing and capitalization for mid-sentence insertions and back-to-back dictations.
- Focused-field support in native macOS apps, Safari, Chrome-based browsers, and Electron apps.

### Changed

- Input Monitoring is no longer required — MiniWhisper now needs only Microphone and Accessibility permissions.

### Fixed

- Hotkeys recover immediately when Accessibility access is re-enabled, without restarting the app.

## 0.1.0

Initial release of MiniWhisper.

### Added

- Hold to dictate or double-tap to record hands-free with the right Option key.
- Local Parakeet TDT v2 transcription with automatic silence rejection.
- Clipboard-safe text delivery, menu bar controls, and guided first-run setup.
