<!-- markdownlint-disable MD024 -->

# Release notes

## 0.4.0

MiniWhisper now reads the window you dictate into to spell what's on screen, delivers to where you started even after you've moved on, and sends what you said with Return.

### Added

- Expanded context: cleanup can see the window you're dictating into, as its text or as a screenshot, so names and terms on screen come out spelled the way they appear. It is chosen per profile and needs Screen Recording, which onboarding now offers as an optional step.
- Return submits: press Return during a recording to end it and send it, or at the same app before it has been delivered.
- A dictation is delivered to the app, field, or tmux pane it started in, even after you've switched away, without pulling that app to the front.
- Pressing the shortcut while a dictation is being cleaned up moves it to the background so you can start the next one; a single tap still skips cleanup.
- A reasoning effort for each profile's cleanup model.
- Most accurate can use any ElevenLabs-compatible speech service.
- When cleanup fails, History shows the error the endpoint gave.

### Changed

- Everyday cleans up with Gemini 4 Hydrogen instead of Claude Haiku, and makes fewer mistakes for it; Most accurate uses Hydrogen too. If you were on Everyday with Haiku, MiniWhisper asks once: switch to Hydrogen, or keep Haiku as your Custom profile with its endpoint, model, and key.
- Fastest cleanup runs Qwen 3.8 27B on Cerebras.
- The separate submit shortcut is gone; Return does its job.
- Onboarding lets you practice holding and double-tapping the shortcut, and offers Offline or Custom when you don't have a key.

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
