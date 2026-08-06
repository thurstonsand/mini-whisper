import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import History
import HotkeyListener

// MARK: - PresentedWindow

enum PresentedWindow: Equatable {
  case settings(SettingsDestination, initialFocus: SettingsWindowFocus?)
  case about
}

#if DEBUG
  enum AgentDriveabilityScene: String {
    case menuHealthy = "menu-healthy"
    case menuDegraded = "menu-degraded"
    case onboardingWelcome = "onboarding-welcome"
    case onboardingPermissionsMicrophone = "onboarding-permissions-microphone"
    case onboardingPermissionsAccessibility = "onboarding-permissions-accessibility"
    case onboardingModel = "onboarding-model"
    case onboardingTryIt = "onboarding-try-it"
    case onboardingReady = "onboarding-ready"
    case settings
    case settingsShortcutsKeyboard = "settings-shortcuts-keyboard"
    case settingsHistory = "settings-history"
    case about
    case pillRecording = "pill-recording"
    case pillTranscribing = "pill-transcribing"
    case pillNoSpeech = "pill-no-speech"
    case pillCopied = "pill-copied"

    // MARK: Internal

    static var current: Self? {
      guard let value = ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_SCENE"] else {
        return nil
      }
      guard let scene = Self(rawValue: value) else {
        preconditionFailure("Unknown agent-driveability scene: \(value)")
      }
      return scene
    }

    var presentedWindow: PresentedWindow? {
      switch self {
      case .settings:
        .settings(.settings, initialFocus: nil)
      case .settingsShortcutsKeyboard:
        .settings(.settings, initialFocus: .detail)
      case .settingsHistory:
        .settings(.history, initialFocus: nil)
      case .about:
        .about
      default:
        nil
      }
    }

    var initialAction: AppFeature.Action? {
      self == .pillRecording ? .pill(.levelUpdated(0.67)) : nil
    }

    var initialState: AppFeature.State {
      var state = AppFeature.State(
        history: Shared(value: seededHistory), settings: Shared(value: seededSettings),
      )
      state.onboardingCompleted = true
      state.modelDownloadConsented = true
      state.hotkeyTap = .active
      state.recording.micStatus = .granted
      state.accessibilityGranted = true
      state.engineReadiness = .ready
      state.inputDeviceName = "Test Microphone"

      switch self {
      case .menuHealthy:
        state.$settings.withLock { $0.soundsEnabled = true }
        state.launchAtLoginRegistered = true
        state.lastTranscript = "A previous transcript"
      case .menuDegraded:
        state.$settings.withLock { $0.soundsEnabled = false }
        state.hotkeyTap = .accessibilityMissing
        state.accessibilityGranted = false
      case .onboardingWelcome:
        state.onboardingCompleted = false
        state.modelDownloadConsented = false
        state.onboarding = onboardingState(
          permissions: permissions(), readiness: .modelMissing, hasConsent: false,
          isShowingWelcome: true,
        )
      case .onboardingPermissionsMicrophone:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(), readiness: .downloading(0.42),
        )
      case .onboardingPermissionsAccessibility:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(microphone: .granted), readiness: .downloading(0.42),
        )
      case .onboardingModel:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(microphone: .granted, accessibility: true),
          readiness: .downloading(0.42), selectedStep: .model,
        )
      case .onboardingTryIt:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(microphone: .granted, accessibility: true),
          readiness: .ready, selectedStep: .tryIt,
        )
      case .onboardingReady:
        state.onboarding = onboardingState(
          permissions: permissions(microphone: .granted, accessibility: true),
          readiness: .ready, isCompleted: true, tryItText: "MiniWhisper is ready.",
        )
      case .settings,
           .settingsHistory,
           .about:
        break
      case .settingsShortcutsKeyboard:
        state.settingsWindow.interaction.mode = .keyboard
      case .pillRecording:
        state.pill.presentation = .recording(
          PillFeature.State.Presentation.Recording(
            inputDeviceName: "Test Microphone", level: 0, isLive: true,
          ),
        )
      case .pillTranscribing:
        state.pill.presentation = .transcribing
      case .pillNoSpeech:
        state.pill.presentation = .notice(.noSpeechDetected)
      case .pillCopied:
        state.pill.presentation = .notice(.copiedToClipboard)
      }
      return state
    }

    // MARK: Private

    private var seededSettings: MiniWhisperSettings {
      var settings = MiniWhisperSettings.defaults
      guard self == .settings || self == .settingsShortcutsKeyboard else {
        return settings
      }
      do {
        try settings.hotkeys.append(Hotkey(keyCode: 15, modifiers: [.rightControl]))
      } catch {
        preconditionFailure("The seeded settings hotkey is invalid: \(error)")
      }
      return settings
    }

    /// Only the History scene needs entries; every other scene starts from an empty log so the
    /// pane it does show is not quietly seeded behind it.
    private var seededHistory: HistoryLog {
      guard self == .settingsHistory else {
        return HistoryLog()
      }
      let calendar = Calendar(identifier: .gregorian)
      let today = Date(timeIntervalSince1970: 1_754_352_000)
      var entries = [
        HistoryEntry(
          id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
          createdAt: today.addingTimeInterval(9 * 3600 + 42 * 60),
          targetApp: TargetApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
          original: Transcription(
            text: "The history pane keeps every transcript close at hand.",
            engine: "test-engine", transcribedAt: today,
          ),
          delivery: Delivery(
            text: "The history pane keeps every transcript close at hand.",
            method: .pasted,
            detail: nil,
          ),
          audio: AudioMetadata(durationSeconds: 8.4, byteCount: 537_600),
        ),
        HistoryEntry(
          id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
          createdAt: calendar.date(byAdding: .day, value: -1, to: today)!,
          targetApp: TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
          original: Transcription(
            text: "A second deterministic transcript for search and deletion.",
            engine: "test-engine", transcribedAt: today,
          ),
          delivery: Delivery(
            text: "A second deterministic transcript for search and deletion.",
            method: .copied,
            detail: nil,
          ),
          audio: nil,
        ),
      ]
      entries.append(contentsOf: (3 ... 32).map { index in
        let text = "Deterministic transcript \(index) for keyboard scrolling."
        return HistoryEntry(
          id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
          createdAt: calendar.date(byAdding: .day, value: -2, to: today)!
            .addingTimeInterval(-Double(index) * 60),
          targetApp: TargetApp(bundleID: "com.apple.Terminal", name: "Terminal"),
          original: Transcription(text: text, engine: "test-engine", transcribedAt: today),
          delivery: Delivery(text: text, method: .copied, detail: nil),
          audio: nil,
        )
      })
      return HistoryLog(entries: entries)
    }

    private func onboardingState(
      permissions: OnboardingPermissionStatuses, readiness: EngineReadiness,
      hasConsent: Bool = true, isShowingWelcome: Bool = false, selectedStep: OnboardingStep? = nil,
      isCompleted: Bool = false, tryItText: String = "",
    ) -> OnboardingFeature.State {
      var state = OnboardingFeature.State()
      state.isPresented = true
      state.snapshot = OnboardingSnapshot(
        permissions: permissions, engineReadiness: readiness, hasModelDownloadConsent: hasConsent,
        isCompleted: isCompleted,
      )
      state.selectedStep = selectedStep
      state.isShowingWelcome = isShowingWelcome
      state.tryItText = tryItText
      return state
    }

    private func permissions(
      microphone: MicPermissionStatus = .undetermined, accessibility: Bool = false,
    ) -> OnboardingPermissionStatuses {
      OnboardingPermissionStatuses(
        microphoneStatus: microphone, hasAccessibilityPermission: accessibility,
      )
    }
  }
#else
  enum AgentDriveabilityScene {
    static var current: Self? {
      precondition(
        ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_SCENE"] == nil,
        "Agent-driveability scenes are available only in Debug builds",
      )
      return nil
    }

    var presentedWindow: PresentedWindow? {
      preconditionFailure()
    }

    var initialAction: AppFeature.Action? {
      preconditionFailure()
    }

    var initialState: AppFeature.State {
      preconditionFailure()
    }
  }
#endif
