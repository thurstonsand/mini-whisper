import SwiftUI

@MainActor @Observable final class SettingsStore {
  // MARK: - Transcription Settings

  var whisperModelSize: WhisperModelSize = .base

  // MARK: - Cleanup Settings

  var cleanupEnabled: Bool = false

  // MARK: - Hotkey Settings

  var hotkeyEnabled: Bool = true

  // MARK: - Persistence (stubbed)

  init() {
    // TODO: Load from UserDefaults
  }

  func save() {
    // TODO: Persist to UserDefaults
  }
}

enum WhisperModelSize: String, CaseIterable {
  case tiny
  case base
  case small
  case medium
  case large

  var displayName: String { rawValue.capitalized }
}
