import AppKit
import ComposableArchitecture
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
  var play: @Sendable (SoundCue) async -> Void
}

// MARK: DependencyKey

extension SoundsClient: DependencyKey {
  static let liveValue = Self(play: { cue in await SystemSounds.play(cue) })
  /// Sounds are on by default, so silence is the right behaviour for tests that are not about
  /// them; the ones that are inject a recorder.
  static let testValue = Self(play: { _ in })
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
