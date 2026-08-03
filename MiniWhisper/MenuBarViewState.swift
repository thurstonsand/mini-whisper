import ASREngine
import AudioCapture
import Foundation

// MARK: - HotkeyTapStatus

enum HotkeyTapStatus: Equatable {
  /// Nothing has been started yet: the launch join has not reported the Accessibility grant.
  case idle
  case starting
  case active
  case accessibilityMissing
  case dead
}

// MARK: - MenuBarDegradation

enum MenuBarDegradation: Equatable {
  case hotkeyTapDead
  case microphoneAccessDenied
  case accessibilityDenied
  case modelMissing
  case modelSetupFailed
}

// MARK: - MenuBarRepair

enum MenuBarRepair: Equatable {
  case restartHotkeyListening
  case openMicrophoneSettings
  case openAccessibilitySettings
  case installModel
  case retryModelSetup
}

// MARK: - MenuBarViewState

struct MenuBarViewState: Equatable {
  // MARK: Lifecycle

  init(
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, accessibilityGranted: Bool,
    engineReadiness: EngineReadiness, inputDeviceName: String?, hasLastTranscript: Bool,
    soundsEnabled: Bool, launchAtLoginRegistered: Bool,
  ) {
    let degradation = MenuBarViewState.degradation(
      hotkeyTap: hotkeyTap, micStatus: micStatus, accessibilityGranted: accessibilityGranted,
      engineReadiness: engineReadiness,
    )
    self.degradation = degradation
    statusText =
      degradation.map(MenuBarViewState.statusText)
        ?? MenuBarViewState.readyStatusText(
          engineReadiness: engineReadiness, inputDeviceName: inputDeviceName,
        )
    repair = degradation.map(MenuBarViewState.repair)
    repairTitle = repair.map(MenuBarViewState.repairTitle)
    canCopyLastTranscript = hasLastTranscript
    self.soundsEnabled = soundsEnabled
    self.launchAtLoginRegistered = launchAtLoginRegistered
  }

  // MARK: Internal

  let degradation: MenuBarDegradation?
  let statusText: String
  let repair: MenuBarRepair?
  let repairTitle: String?
  let canCopyLastTranscript: Bool
  let soundsEnabled: Bool
  let launchAtLoginRegistered: Bool

  var iconSymbolName: String {
    degradation == nil ? "mic" : "mic.slash"
  }

  var accessibilityStatusText: String {
    statusText.replacing(" · ", with: "; ")
  }

  // MARK: Private

  private static func degradation(
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, accessibilityGranted: Bool,
    engineReadiness: EngineReadiness,
  ) -> MenuBarDegradation? {
    // One Accessibility grant runs the hotkey tap and the paste, so both failures are the same
    // repair — and a revoked grant outranks a dead tap, because restarting a listener macOS will
    // not let hear anything is a repair that can only fail.
    guard accessibilityGranted else {
      return .accessibilityDenied
    }
    switch hotkeyTap {
    case .accessibilityMissing:
      return .accessibilityDenied
    case .dead:
      return .hotkeyTapDead
    case .idle,
         .starting,
         .active:
      break
    }
    switch micStatus {
    // Capture only accepts `.granted`, so an unreadable status is as structural as a refusal;
    // `.undetermined` belongs to onboarding, which is the one place allowed to ask.
    case .denied,
         .restricted,
         .unknown:
      return .microphoneAccessDenied
    case .granted,
         .undetermined:
      break
    }
    switch engineReadiness {
    case .modelMissing:
      return .modelMissing
    case .failed:
      return .modelSetupFailed
    case .downloading,
         .compiling,
         .prewarming,
         .ready:
      return nil
    }
  }

  private static func statusText(_ degradation: MenuBarDegradation) -> String {
    switch degradation {
    case .hotkeyTapDead:
      "Hotkey listening stopped"
    case .microphoneAccessDenied:
      "Microphone access is off, so nothing can be recorded"
    case .accessibilityDenied:
      "Accessibility is off, so the hotkey and pasting can't work · switch it on"
    case .modelMissing:
      "Parakeet v2 isn't installed yet"
    case .modelSetupFailed:
      "Parakeet v2 setup failed"
    }
  }

  private static func readyStatusText(
    engineReadiness: EngineReadiness, inputDeviceName: String?,
  ) -> String {
    let device = inputDeviceName ?? "No input device"
    switch engineReadiness {
    case .ready:
      return "Ready · Parakeet v2 · \(device)"
    case let .downloading(fraction):
      return "Downloading Parakeet v2 · \(Int(fraction * 100))% · \(device)"
    case .compiling:
      return "Compiling Parakeet v2 · \(device)"
    case .prewarming:
      return "Prewarming Parakeet v2 · \(device)"
    case .modelMissing,
         .failed:
      return "Parakeet v2 · \(device)"
    }
  }

  private static func repair(_ degradation: MenuBarDegradation) -> MenuBarRepair {
    switch degradation {
    case .hotkeyTapDead:
      .restartHotkeyListening
    case .microphoneAccessDenied:
      .openMicrophoneSettings
    case .accessibilityDenied:
      .openAccessibilitySettings
    case .modelMissing:
      .installModel
    case .modelSetupFailed:
      .retryModelSetup
    }
  }

  private static func repairTitle(_ repair: MenuBarRepair) -> String {
    switch repair {
    case .restartHotkeyListening:
      "Restart Hotkey Listening"
    case .openMicrophoneSettings:
      "Open Microphone Settings…"
    case .openAccessibilitySettings:
      "Open Accessibility Settings…"
    case .installModel:
      "Download & Prepare Parakeet v2…"
    case .retryModelSetup:
      "Retry Parakeet v2 Setup…"
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
