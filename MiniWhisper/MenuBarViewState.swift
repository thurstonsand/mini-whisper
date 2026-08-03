import ASREngine
import AudioCapture
import Foundation

// MARK: - HotkeyTapStatus

enum HotkeyTapStatus: Equatable {
  case starting
  case active
  case inputMonitoringMissing
  case dead
}

// MARK: - MenuBarDegradation

enum MenuBarDegradation: Equatable {
  case inputMonitoringMissing
  case hotkeyTapDead
  case microphoneAccessDenied
  case pasteAccessDenied
  case modelMissing
  case modelSetupFailed
}

// MARK: - MenuBarRepair

enum MenuBarRepair: Equatable {
  case openInputMonitoringSettings
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
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, pasteAccessGranted: Bool?,
    engineReadiness: EngineReadiness, inputDeviceName: String?, hasLastTranscript: Bool,
    soundsEnabled: Bool, launchAtLoginRegistered: Bool,
  ) {
    let degradation = MenuBarViewState.degradation(
      hotkeyTap: hotkeyTap, micStatus: micStatus, pasteAccessGranted: pasteAccessGranted,
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
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, pasteAccessGranted: Bool?,
    engineReadiness: EngineReadiness,
  ) -> MenuBarDegradation? {
    switch hotkeyTap {
    case .inputMonitoringMissing:
      return .inputMonitoringMissing
    case .dead:
      return .hotkeyTapDead
    case .starting,
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
    if pasteAccessGranted == false {
      return .pasteAccessDenied
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
    case .inputMonitoringMissing:
      "Input Monitoring is off, so MiniWhisper can't see your hotkey · switch it on or add it"
    case .hotkeyTapDead:
      "Hotkey listening stopped"
    case .microphoneAccessDenied:
      "Microphone access is off, so nothing can be recorded"
    case .pasteAccessDenied:
      "Paste access is off, so transcripts can only be copied"
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
    case .inputMonitoringMissing:
      .openInputMonitoringSettings
    case .hotkeyTapDead:
      .restartHotkeyListening
    case .microphoneAccessDenied:
      .openMicrophoneSettings
    case .pasteAccessDenied:
      .openAccessibilitySettings
    case .modelMissing:
      .installModel
    case .modelSetupFailed:
      .retryModelSetup
    }
  }

  private static func repairTitle(_ repair: MenuBarRepair) -> String {
    switch repair {
    case .openInputMonitoringSettings:
      "Open Input Monitoring Settings…"
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
  static let inputMonitoring = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
  )!
  static let microphone = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
  )!
  static let accessibility = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
  )!
}
