import AppKit
import ComposableArchitecture
import HotkeyListener
import OSLog

private let soundsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "sounds")

enum SoundCue: Equatable, Sendable {
  case recordStart
  case commit
  case cancel
  case error
}

@DependencyClient struct SoundsClient: Sendable {
  var loadIsEnabled: @Sendable () async throws -> Bool = { true }
  var play: @Sendable (SoundCue) async -> Void
}

extension SoundsClient: DependencyKey {
  static let liveValue = Self(
    loadIsEnabled: { try SettingsStore().load().soundsEnabled },
    play: { cue in await SystemSounds.play(cue) })
}

extension DependencyValues {
  var sounds: SoundsClient {
    get { self[SoundsClient.self] }
    set { self[SoundsClient.self] = newValue }
  }
}

@MainActor private enum SystemSounds {
  static func play(_ cue: SoundCue) {
    let name: NSSound.Name =
      switch cue {
      case .recordStart: NSSound.Name("Tink")
      case .commit: NSSound.Name("Pop")
      case .cancel: NSSound.Name("Funk")
      case .error: NSSound.Name("Basso")
      }
    guard let sound = NSSound(named: name) else {
      soundsLogger.error("Built-in sound missing: \(name, privacy: .public)")
      return
    }
    sound.play()
  }
}
