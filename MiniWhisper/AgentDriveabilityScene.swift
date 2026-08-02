import ASREngine
import AudioCapture
import Foundation

#if DEBUG
  enum AgentDriveabilityScene: String {
    case menuHealthy = "menu-healthy"
    case menuDegraded = "menu-degraded"
    case onboardingWelcome = "onboarding-welcome"
    case onboardingPermissionsInputMonitoring = "onboarding-permissions-input-monitoring"
    case onboardingPermissionsMicrophone = "onboarding-permissions-microphone"
    case onboardingPermissionsPasteAccess = "onboarding-permissions-paste-access"
    case onboardingModel = "onboarding-model"
    case onboardingTryIt = "onboarding-try-it"
    case onboardingReady = "onboarding-ready"
    case about
    case pillRecording = "pill-recording"
    case pillTranscribing = "pill-transcribing"
    case pillNoSpeech = "pill-no-speech"
    case pillCopied = "pill-copied"

    static var current: Self? {
      guard let value = ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_SCENE"] else {
        return nil
      }
      guard let scene = Self(rawValue: value) else {
        preconditionFailure("Unknown agent-driveability scene: \(value)")
      }
      return scene
    }

    var presentsAbout: Bool { self == .about }
    var initialAction: AppFeature.Action? {
      self == .pillRecording ? .pill(.levelUpdated(0.67)) : nil
    }

    var initialState: AppFeature.State {
      var state = AppFeature.State()
      state.onboardingCompleted = true
      state.modelDownloadConsented = true
      state.hotkeyTap = .active
      state.recording.micStatus = .granted
      state.pasteAccessGranted = true
      state.engineReadiness = .ready
      state.inputDeviceName = "Test Microphone"

      switch self {
      case .menuHealthy:
        state.soundsEnabled = true
        state.launchAtLoginRegistered = true
        state.lastTranscript = "A previous transcript"
      case .menuDegraded: state.hotkeyTap = .inputMonitoringMissing
      case .onboardingWelcome:
        state.onboardingCompleted = false
        state.modelDownloadConsented = false
        state.onboarding = onboardingState(
          permissions: permissions(), readiness: .modelMissing, hasConsent: false,
          isShowingWelcome: true)
      case .onboardingPermissionsInputMonitoring:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(), readiness: .downloading(0.42))
      case .onboardingPermissionsMicrophone:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(inputMonitoring: true), readiness: .downloading(0.42))
      case .onboardingPermissionsPasteAccess:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(inputMonitoring: true, microphone: .granted),
          readiness: .downloading(0.42))
      case .onboardingModel:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(inputMonitoring: true, microphone: .granted, pasteAccess: true),
          readiness: .downloading(0.42), selectedStep: .model)
      case .onboardingTryIt:
        state.onboardingCompleted = false
        state.onboarding = onboardingState(
          permissions: permissions(inputMonitoring: true, microphone: .granted, pasteAccess: true),
          readiness: .ready, selectedStep: .tryIt)
      case .onboardingReady:
        state.onboarding = onboardingState(
          permissions: permissions(inputMonitoring: true, microphone: .granted, pasteAccess: true),
          readiness: .ready, isCompleted: true, tryItText: "MiniWhisper is ready.")
      case .about: break
      case .pillRecording:
        state.pill.presentation = .recording(
          PillFeature.State.Presentation.Recording(
            inputDeviceName: "Test Microphone", level: 0, isLive: true))
      case .pillTranscribing: state.pill.presentation = .transcribing
      case .pillNoSpeech: state.pill.presentation = .notice(.noSpeechDetected)
      case .pillCopied: state.pill.presentation = .notice(.copiedToClipboard)
      }
      return state
    }

    private func onboardingState(
      permissions: OnboardingPermissionStatuses, readiness: EngineReadiness,
      hasConsent: Bool = true, isShowingWelcome: Bool = false, selectedStep: OnboardingStep? = nil,
      isCompleted: Bool = false, tryItText: String = ""
    ) -> OnboardingFeature.State {
      var state = OnboardingFeature.State()
      state.isPresented = true
      state.snapshot = OnboardingSnapshot(
        permissions: permissions, engineReadiness: readiness, hasModelDownloadConsent: hasConsent,
        isCompleted: isCompleted)
      state.selectedStep = selectedStep
      state.isShowingWelcome = isShowingWelcome
      state.tryItText = tryItText
      return state
    }

    private func permissions(
      inputMonitoring: Bool = false, microphone: MicPermissionStatus = .undetermined,
      pasteAccess: Bool = false
    ) -> OnboardingPermissionStatuses {
      OnboardingPermissionStatuses(
        hasInputMonitoringPermission: inputMonitoring, microphoneStatus: microphone,
        hasPasteAccess: pasteAccess)
    }
  }
#else
  enum AgentDriveabilityScene {
    static var current: Self? {
      precondition(
        ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_SCENE"] == nil,
        "Agent-driveability scenes are available only in Debug builds")
      return nil
    }

    var presentsAbout: Bool { preconditionFailure() }
    var initialAction: AppFeature.Action? { preconditionFailure() }
    var initialState: AppFeature.State { preconditionFailure() }
  }
#endif
