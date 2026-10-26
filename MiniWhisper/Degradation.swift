import AppSettings
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
  // MARK: Lifecycle

  init(
    hotkeyTap: HotkeyTapStatus = .idle, micStatus: MicPermissionStatus = .undetermined,
    accessibilityGranted: Bool = false, engine: SpeechEngine = .parakeet,
    engineReadiness: EngineReadiness = .modelMissing,
  ) {
    self.hotkeyTap = hotkeyTap
    self.micStatus = micStatus
    self.accessibilityGranted = accessibilityGranted
    self.engine = engine
    readinessByEngine = [engine: engineReadiness]
  }

  // MARK: Internal

  var hotkeyTap: HotkeyTapStatus
  var micStatus: MicPermissionStatus
  var accessibilityGranted: Bool
  /// The active profile's engine: the one a dictation would reach, and the only one whose
  /// readiness can degrade the app.
  var engine: SpeechEngine
  /// Every engine's last known readiness. A download keeps reporting after its profile is
  /// switched away from, and that report belongs to its own engine, not to whichever is active.
  var readinessByEngine: [SpeechEngine: EngineReadiness]
  /// The cleanup key a factory profile was chosen without. A factory profile promises its
  /// cleanup, so it does not dictate raw in the meantime.
  var missingCleanupKey: CredentialProvider?
  /// Keys an endpoint refused on a real request. Said beside the key, not as a degradation: the
  /// dictation still delivered, just uncleaned.
  var rejectedKeys: Set<CredentialSlot> = []

  var engineReadiness: EngineReadiness {
    get { readinessByEngine[engine] ?? .modelMissing }
    set { readinessByEngine[engine] = newValue }
  }

  var engineStatusText: String {
    engineReadiness.statusText(engine)
  }

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
      degradations.append(engine == .parakeet ? .modelMissing : .gateMissing)
    case .failed:
      degradations.append(.modelSetupFailed)
    case .credentialMissing:
      degradations.append(.engineKeyMissing)
    case .downloading,
         .compiling,
         .prewarming,
         .ready:
      break
    }
    if missingCleanupKey != nil {
      degradations.append(.cleanupKeyMissing)
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
  case gateMissing = "gate-missing"
  case modelSetupFailed = "model-setup-failed"
  case engineKeyMissing = "engine-key"
  case cleanupKeyMissing = "cleanup-key"

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
    case .gateMissing:
      Presentation(
        title: "Download the Speech Gate", reason: "Required before any speech leaves this Mac",
      )
    case .modelSetupFailed:
      Presentation(
        title: "Retry Speech Setup", reason: "Setup failed, so nothing can be transcribed",
      )
    case .engineKeyMissing:
      Presentation(
        title: "Add an ElevenLabs Key…", reason: "Most accurate can’t transcribe without one",
      )
    case .cleanupKeyMissing:
      Presentation(
        title: "Add Your API Key…", reason: "Dictation is off until the profile has its key",
      )
    }
  }
}

// MARK: - EngineReadiness Presentation

extension EngineReadiness {
  func statusText(_ engine: SpeechEngine) -> String {
    let name = engine.shortName
    return switch self {
    case .ready:
      "Ready · \(name)"
    case let .downloading(fraction):
      "Downloading \(engine == .parakeet ? name : "speech gate") · \(Int(fraction * 100))%"
    case .compiling:
      "Compiling \(name)"
    case .prewarming:
      "Prewarming \(name)"
    case .modelMissing:
      "Speech model not installed"
    case .credentialMissing:
      "\(name) needs a key"
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
         .credentialMissing,
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

extension SpeechEngine {
  /// The name a one-line status has room for.
  var shortName: String {
    switch self {
    case .parakeet:
      "Parakeet v2"
    case .scribe:
      "Scribe v2"
    }
  }
}
