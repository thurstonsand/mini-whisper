import AppKit
import ComposableArchitecture
import HotkeyListener
import OSLog

private let soundsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "sounds")

// MARK: - SoundCue

enum SoundCue: Equatable {
  case recordStart
  case commit
  case cancel
  case error
}

// MARK: - SoundsClient

@DependencyClient struct SoundsClient {
  var loadIsEnabled: @Sendable () async throws -> Bool = { true }
  var setIsEnabled: @Sendable (Bool) async throws -> Void
  var play: @Sendable (SoundCue) async -> Void
}

// MARK: DependencyKey

extension SoundsClient: DependencyKey {
  static let liveValue = Self(
    loadIsEnabled: { try SettingsStore().load().soundsEnabled },
    setIsEnabled: { enabled in try SettingsStore().saveSoundsEnabled(enabled) },
    play: { cue in await SystemSounds.play(cue) },
  )
}

extension DependencyValues {
  var sounds: SoundsClient {
    get { self[SoundsClient.self] }
    set { self[SoundsClient.self] = newValue }
  }
}

// MARK: - SystemSounds

@MainActor private enum SystemSounds {
  static func play(_ cue: SoundCue) {
    let name =
      switch cue {
      case .recordStart:
        NSSound.Name("Tink")
      case .commit:
        NSSound.Name("Pop")
      case .cancel:
        NSSound.Name("Funk")
      case .error:
        NSSound.Name("Basso")
      }
    guard let sound = NSSound(named: name) else {
      soundsLogger.error("Built-in sound missing: \(name, privacy: .public)")
      return
    }
    sound.play()
  }
}
