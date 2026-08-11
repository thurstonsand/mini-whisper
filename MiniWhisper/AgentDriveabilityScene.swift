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
    case onboardingPermissionsAccessibilitySettings =
      "onboarding-permissions-accessibility-settings"
    case onboardingShortcut = "onboarding-shortcut"
    case onboardingModel = "onboarding-model"
    case onboardingModelActionable = "onboarding-model-actionable"
    case onboardingTryIt = "onboarding-try-it"
    case onboardingReady = "onboarding-ready"
    case settings
    case settingsShortcutsKeyboard = "settings-shortcuts-keyboard"
    case settingsMicrophoneUnavailable = "settings-microphone-unavailable"
    case settingsSoundsNoAudio = "settings-sounds-no-audio"
    case settingsDegraded = "settings-degraded"
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
      case .settingsMicrophoneUnavailable,
           .settingsSoundsNoAudio,
           .settingsDegraded:
        .settings(.settings, initialFocus: nil)
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
      state.$health.withLock {
        $0 = AppHealth(
          hotkeyTap: .active, micStatus: .granted, accessibilityGranted: true,
          engineReadiness: .ready,
        )
      }
      state.inputDeviceName = "Test Microphone"

      switch self {
      case .menuHealthy:
        state.lastTranscript = "A previous transcript"
      case .menuDegraded:
        state.$health.withLock {
          $0.hotkeyTap = .idle
          $0.micStatus = .denied
          $0.accessibilityGranted = false
        }
      case .onboardingWelcome:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(), readiness: .ready, hasConsent: false,
                isShowingWelcome: true)
      case .onboardingPermissionsMicrophone:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(), readiness: .downloading(0.42))
      case .onboardingPermissionsAccessibility:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted), readiness: .downloading(0.42))
      case .onboardingPermissionsAccessibilitySettings:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted), readiness: .downloading(0.42),
                requestedPermissions: [.accessibility])
      case .onboardingShortcut:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .downloading(0.42), selectedStep: .shortcut)
      case .onboardingModel:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .downloading(0.42), selectedStep: .model, hasCompletedShortcut: true)
      case .onboardingModelActionable:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .failed("Model setup failed"), selectedStep: .model,
                hasCompletedShortcut: true)
        // A real failure arrives through the readiness stream, which also posts the message the
        // footer shows — and clearing it is how a retry announces itself.
        state.onboarding.failureMessage = "Model setup failed"
      case .onboardingTryIt:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .ready, selectedStep: .tryIt, hasCompletedShortcut: true)
      case .onboardingReady:
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .ready, hasCompletedShortcut: true, isCompleted: true,
                tryItText: "MiniWhisper is ready.")
      case .settings,
           .settingsMicrophoneUnavailable,
           .settingsSoundsNoAudio:
        state.settingsWindow.settingsPane.launchAtLoginRegistered = true
      case .settingsDegraded:
        state.$health.withLock {
          $0.hotkeyTap = .idle
          $0.micStatus = .denied
          $0.accessibilityGranted = false
          $0.engineReadiness = .failed("Model setup failed")
        }
        state.settingsWindow.settingsPane.launchAtLoginRegistered = true
      case .settingsHistory,
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
      // An onboarding scene's permission truth is its snapshot; the app-level fields follow it, so
      // the seeded state and the seeded clients can never disagree about what has been granted.
      if state.onboarding.isPresented {
        let snapshot = state.onboarding.snapshot.permissions
        state.$health.withLock {
          $0.micStatus = snapshot.microphoneStatus
          $0.accessibilityGranted = snapshot.hasAccessibilityPermission
        }
      }
      return state
    }

    // MARK: Private

    private var seededSettings: MiniWhisperSettings {
      var settings = MiniWhisperSettings.defaults
      switch self {
      case .settings,
           .settingsShortcutsKeyboard,
           .settingsDegraded:
        break
      case .settingsMicrophoneUnavailable:
        settings.microphone = .device(
          uid: "seeded-disconnected-microphone", lastKnownName: "Studio Microphone",
        )
      case .settingsSoundsNoAudio:
        settings.sounds.cancel = nil
      default:
        return settings
      }
      do {
        try settings.bindings.activate.append(Hotkey(keyCode: 15, modifiers: [.rightControl]))
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

    /// Seeded in place: the onboarding state built by `AppFeature.State` already shares the
    /// scene's settings, and replacing it would hand the window the real settings file instead.
    private func present(
      _ state: inout OnboardingFeature.State,
      permissions: OnboardingPermissionStatuses, readiness: EngineReadiness,
      hasConsent: Bool = true, isShowingWelcome: Bool = false, selectedStep: OnboardingStep? = nil,
      hasCompletedShortcut: Bool = false, isCompleted: Bool = false, tryItText: String = "",
      requestedPermissions: Set<OnboardingPermission> = [],
    ) {
      state.isPresented = true
      state.snapshot = OnboardingSnapshot(
        permissions: permissions, hasModelDownloadConsent: hasConsent, isCompleted: isCompleted,
      )
      state.$health.withLock { $0.engineReadiness = readiness }
      state.selectedStep = selectedStep
      state.isShowingWelcome = isShowingWelcome
      state.hasCompletedShortcut = hasCompletedShortcut
      state.tryItText = tryItText
      state.requestedPermissions = requestedPermissions
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
  /// Caseless on purpose: `AppFeature.Action.agentScenePresented` carries this type, and a
  /// payload with no cases makes that action impossible to construct in Release.
  enum AgentDriveabilityScene: Equatable {
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

    func configure(_: inout DependencyValues) {
      preconditionFailure()
    }
  }
#endif
