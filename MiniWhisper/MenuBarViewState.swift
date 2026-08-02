import ASREngine
import AudioCapture
import Foundation

enum HotkeyTapStatus: Equatable, Sendable {
  case starting
  case active
  case inputMonitoringMissing
  case dead
}

enum MenuBarDegradation: Equatable, Sendable {
  case inputMonitoringMissing
  case hotkeyTapDead
  case microphoneAccessDenied
  case pasteAccessDenied
  case modelMissing
  case modelSetupFailed
}

enum MenuBarRepair: Equatable, Sendable {
  case openInputMonitoringSettings
  case restartHotkeyListening
  case openMicrophoneSettings
  case openAccessibilitySettings
  case installModel
  case retryModelSetup
}

struct MenuBarViewState: Equatable {
  let degradation: MenuBarDegradation?
  let statusText: String
  let repair: MenuBarRepair?
  let repairTitle: String?
  let canCopyLastTranscript: Bool
  let soundsEnabled: Bool
  let launchAtLoginRegistered: Bool

  var iconSymbolName: String { degradation == nil ? "mic" : "mic.slash" }
  var accessibilityStatusText: String { statusText.replacingOccurrences(of: " · ", with: "; ") }

  init(
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, pasteAccessGranted: Bool?,
    engineReadiness: EngineReadiness, inputDeviceName: String?, hasLastTranscript: Bool,
    soundsEnabled: Bool, launchAtLoginRegistered: Bool
  ) {
    let degradation = MenuBarViewState.degradation(
      hotkeyTap: hotkeyTap, micStatus: micStatus, pasteAccessGranted: pasteAccessGranted,
      engineReadiness: engineReadiness)
    self.degradation = degradation
    self.statusText =
      degradation.map(MenuBarViewState.statusText)
      ?? MenuBarViewState.readyStatusText(
        engineReadiness: engineReadiness, inputDeviceName: inputDeviceName)
    self.repair = degradation.map(MenuBarViewState.repair)
    self.repairTitle = self.repair.map(MenuBarViewState.repairTitle)
    self.canCopyLastTranscript = hasLastTranscript
    self.soundsEnabled = soundsEnabled
    self.launchAtLoginRegistered = launchAtLoginRegistered
  }

  private static func degradation(
    hotkeyTap: HotkeyTapStatus, micStatus: MicPermissionStatus, pasteAccessGranted: Bool?,
    engineReadiness: EngineReadiness
  ) -> MenuBarDegradation? {
    switch hotkeyTap {
    case .inputMonitoringMissing: return .inputMonitoringMissing
    case .dead: return .hotkeyTapDead
    case .starting, .active: break
    }
    switch micStatus {
    // Capture only accepts `.granted`, so an unreadable status is as structural as a refusal;
    // `.undetermined` belongs to onboarding, which is the one place allowed to ask.
    case .denied, .restricted, .unknown: return .microphoneAccessDenied
    case .granted, .undetermined: break
    }
    if pasteAccessGranted == false { return .pasteAccessDenied }
    switch engineReadiness {
    case .modelMissing: return .modelMissing
    case .failed: return .modelSetupFailed
    case .downloading, .compiling, .prewarming, .ready: return nil
    }
  }

  private static func statusText(_ degradation: MenuBarDegradation) -> String {
    switch degradation {
    case .inputMonitoringMissing: "Input Monitoring is off, so MiniWhisper can't see your hotkey"
    case .hotkeyTapDead: "Hotkey listening stopped"
    case .microphoneAccessDenied: "Microphone access is off, so nothing can be recorded"
    case .pasteAccessDenied: "Paste access is off, so transcripts can only be copied"
    case .modelMissing: "Parakeet v2 isn't installed yet"
    case .modelSetupFailed: "Parakeet v2 setup failed"
    }
  }

  private static func readyStatusText(
    engineReadiness: EngineReadiness, inputDeviceName: String?
  ) -> String {
    let device = inputDeviceName ?? "No input device"
    switch engineReadiness {
    case .ready: return "Ready · Parakeet v2 · \(device)"
    case .downloading(let fraction):
      return "Downloading Parakeet v2 · \(Int(fraction * 100))% · \(device)"
    case .compiling: return "Compiling Parakeet v2 · \(device)"
    case .prewarming: return "Prewarming Parakeet v2 · \(device)"
    case .modelMissing, .failed: return "Parakeet v2 · \(device)"
    }
  }

  private static func repair(_ degradation: MenuBarDegradation) -> MenuBarRepair {
    switch degradation {
    case .inputMonitoringMissing: .openInputMonitoringSettings
    case .hotkeyTapDead: .restartHotkeyListening
    case .microphoneAccessDenied: .openMicrophoneSettings
    case .pasteAccessDenied: .openAccessibilitySettings
    case .modelMissing: .installModel
    case .modelSetupFailed: .retryModelSetup
    }
  }

  private static func repairTitle(_ repair: MenuBarRepair) -> String {
    switch repair {
    case .openInputMonitoringSettings: "Open Input Monitoring Settings…"
    case .restartHotkeyListening: "Restart Hotkey Listening"
    case .openMicrophoneSettings: "Open Microphone Settings…"
    case .openAccessibilitySettings: "Open Accessibility Settings…"
    case .installModel: "Download & Prepare Parakeet v2…"
    case .retryModelSetup: "Retry Parakeet v2 Setup…"
    }
  }
}

enum SystemSettingsPane {
  static let inputMonitoring = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
  static let microphone = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
  static let accessibility = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
