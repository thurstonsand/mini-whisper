<!-- markdownlint-disable MD024 -->

# Release notes

## 0.3.0

MiniWhisper now cleans up what you say, learns your words, keeps a history of every dictation, and lets you choose the whole dictation stack as a profile.

### Added

- Profiles: Parakeet + Claude Haiku, Parakeet + Cerebras, Offline, Most accurate (ElevenLabs Scribe v2 with Gemini), and Custom for any OpenAI-compatible endpoint. Exactly one is active, and factory profiles can be overridden field by field.
- The cleanup pass: an LLM pass that fixes punctuation, spoken formatting, and spelled-out words before delivery, with an on-device S1-mini model for Offline.
- A Models library where each model downloads, resumes, and deletes on its own.
- Keys and endpoints are checked before they are stored, for free, and a rejected key reads "Invalid key".
- The dictionary: vocabulary and corrections, a settings pane, and Add to Dictionary in the menu. Taught words also boost recognition itself.
- History of every dictation, with search, copy, playback, re-transcription, and retention settings.
- A settings window: activation and paste-last shortcuts, microphone selection, per-cue sounds, and launch at login.
- Paste-last (⌥⌘V) re-delivers the last transcript wherever the cursor now is.
- Onboarding asks for the profile and the activation shortcut.

### Changed

- Dev, nightly, and release builds are separate apps with their own permissions, settings, and keys, so the nightly cask can be installed beside the release.
- With nothing focused to type into, delivery is withheld and the clipboard is left alone; the pill offers paste-last instead.

### Fixed

- A double-tap or tap-then-hold no longer plays the activate cue twice.

## 0.2.0

MiniWhisper now adapts delivered transcripts to the text around the insertion point and asks for one fewer macOS permission.

### Added

- Context-aware spacing and capitalization for consecutive dictations and mid-sentence insertions.
- Accessibility identifiers and deterministic UI scenes covering onboarding, the menu, About, and every pill state.
- Support for reading focused fields in native apps, Safari, Chromium browsers, and Electron apps.

### Changed

- Reduced onboarding to two permissions: Microphone and Accessibility. Accessibility covers the global hotkey, transcript delivery, and focused-field context; Input Monitoring is no longer requested.

### Fixed

- Recover the hotkey immediately when Accessibility is granted again, without requiring an app restart.

## 0.1.0

Initial MiniWhisper release.

### Added

- Hold and latch dictation from the right Option key.
- Local Parakeet TDT 0.6B v2 transcription with silence rejection.
- Clipboard-safe transcript delivery, menu bar controls, and guided first-run setup.
- Signed, notarized, stapled arm64 release archives and stable/nightly Homebrew casks.
