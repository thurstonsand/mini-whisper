import ASREngine
import AudioCapture
import Foundation

// MARK: - PresentedWindow

enum PresentedWindow {
  case settings
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
        .settings
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
      var state = AppFeature.State()
      state.onboardingCompleted = true
      state.modelDownloadConsented = true
      state.hotkeyTap = .active
      state.recording.micStatus = .granted
      state.accessibilityGranted = true
      state.engineReadiness = .ready
      state.inputDeviceName = "Test Microphone"

      switch self {
      case .menuHealthy:
        state.soundsEnabled = true
        state.launchAtLoginRegistered = true
        state.lastTranscript = "A previous transcript"
      case .menuDegraded:
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
           .about:
        break
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
