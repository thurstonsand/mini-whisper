import ASREngine
import AudioCapture
import Foundation

// MARK: - HotkeyTapStatus

enum HotkeyTapStatus: Equatable {
  /// Not listening, and not wrong: nothing has started yet, no shortcut is bound, or the grant
  /// the tap needs is missing. `AppHealth` is what says which.
  case idle
  case starting
  case active
  case dead
}

// MARK: - AppHealth

struct AppHealth: Equatable {
  var hotkeyTap = HotkeyTapStatus.idle
  var micStatus: MicPermissionStatus = .undetermined
  var accessibilityGranted = false
  var engineReadiness = EngineReadiness.modelMissing

  var degradations: [Degradation] {
    var degradations: [Degradation] = []
    if !accessibilityGranted {
      degradations.append(.accessibilityDenied)
    }
    switch micStatus {
    // `.undetermined` is not a failure, because nothing has asked yet. Capture asks on its way to
    // the microphone, so a dictation attempted without the grant raises the prompt rather than
    // finding a dead end — which is what makes leaving onboarding early survivable.
    case .denied,
         .restricted,
         .unknown:
      degradations.append(.microphoneAccessDenied)
    case .granted,
         .undetermined:
      break
    }
    // One Accessibility grant runs the hotkey tap and the paste, so a revoked grant is already
    // reported above, and it outranks the dead tap it caused: restarting a listener that macOS
    // will not let hear anything is a repair that can only fail.
    if accessibilityGranted, hotkeyTap == .dead {
      degradations.insert(.hotkeyTapDead, at: 0)
    }
    switch engineReadiness {
    case .modelMissing:
      degradations.append(.modelMissing)
    case .failed:
      degradations.append(.modelSetupFailed)
    case .downloading,
         .compiling,
         .prewarming,
         .ready:
      break
    }
    return degradations
  }

  var isDegraded: Bool {
    !degradations.isEmpty
  }
}

// MARK: - Degradation

/// The raw value is the identifier fragment both surfaces address a row by, so a failure is named
/// once rather than once per screen it can appear on.
enum Degradation: String, Hashable {
  case hotkeyTapDead = "hotkey-listening"
  case microphoneAccessDenied = "microphone"
  case accessibilityDenied = "accessibility"
  case modelMissing = "model-missing"
  case modelSetupFailed = "model-setup-failed"

  // MARK: Internal

  struct Presentation: Equatable {
    let title: String
    let reason: String
  }

  var presentation: Presentation {
    switch self {
    case .hotkeyTapDead:
      Presentation(
        title: "Restart Hotkey Listening",
        reason: "Listening stopped, so the shortcut does nothing",
      )
    case .microphoneAccessDenied:
      Presentation(title: "Grant Microphone Access…", reason: "Required to record audio")
    case .accessibilityDenied:
      Presentation(
        title: "Grant Accessibility Access…",
        reason: "Required to start dictation and paste text",
      )
    case .modelMissing:
      Presentation(
        title: "Download & Prepare Parakeet v2",
        reason: "Required to transcribe speech",
      )
    case .modelSetupFailed:
      Presentation(
        title: "Retry Parakeet v2 Setup", reason: "Setup failed, so nothing can be transcribed",
      )
    }
  }
}

// MARK: - EngineReadiness Presentation

extension EngineReadiness {
  var statusText: String {
    switch self {
    case .ready:
      "Ready · Parakeet v2"
    case let .downloading(fraction):
      "Downloading Parakeet v2 · \(Int(fraction * 100))%"
    case .compiling:
      "Compiling Parakeet v2"
    case .prewarming:
      "Prewarming Parakeet v2"
    case .modelMissing:
      "Speech model not installed"
    case .failed:
      "Speech model setup failed"
    }
  }

  var isInstallable: Bool {
    switch self {
    case .modelMissing,
         .failed:
      true
    case .downloading,
         .compiling,
         .prewarming,
         .ready:
      false
    }
  }
}

// MARK: - SystemSettingsPane

enum SystemSettingsPane {
  static let microphone = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
  )!
  static let accessibility = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
  )!
}
