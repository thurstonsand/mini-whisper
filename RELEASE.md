<!-- markdownlint-disable MD024 -->

# Release notes

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
