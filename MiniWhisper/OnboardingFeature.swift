import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import OSLog

private let onboardingLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "onboarding",
)

// MARK: - OnboardingPermission

enum OnboardingPermission: Int, CaseIterable, Equatable, Hashable {
  case microphone
  case accessibility

  // MARK: Internal

  var settingsPane: URL {
    switch self {
    case .microphone:
      SystemSettingsPane.microphone
    case .accessibility:
      SystemSettingsPane.accessibility
    }
  }
}

// MARK: - OnboardingPermissionStatuses

struct OnboardingPermissionStatuses: Equatable {
  var microphoneStatus: MicPermissionStatus
  var hasAccessibilityPermission: Bool

  var allGranted: Bool {
    microphoneStatus == .granted && hasAccessibilityPermission
  }

  func isGranted(_ permission: OnboardingPermission) -> Bool {
    switch permission {
    case .microphone:
      microphoneStatus == .granted
    case .accessibility:
      hasAccessibilityPermission
    }
  }
}

// MARK: - OnboardingSnapshot

struct OnboardingSnapshot: Equatable {
  var permissions: OnboardingPermissionStatuses
  var hasModelDownloadConsent: Bool
  var isCompleted: Bool
}

// MARK: - OnboardingStep

enum OnboardingStep: Int, Equatable {
  case permissions
  case shortcut
  case model
  case tryIt
  case ready

  // MARK: Internal

  static func derive(
    from snapshot: OnboardingSnapshot, engineReadiness: EngineReadiness,
    hasCompletedShortcut: Bool,
  ) -> Self {
    guard snapshot.permissions.allGranted else {
      return .permissions
    }
    guard hasCompletedShortcut else {
      return .shortcut
    }
    guard engineReadiness == .ready else {
      return .model
    }
    return snapshot.isCompleted ? .ready : .tryIt
  }
}

// MARK: - OnboardingFeature

@Reducer struct OnboardingFeature {
  // MARK: Internal

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(
      settings: Shared<MiniWhisperSettings> = Shared(
        wrappedValue: .defaults, .settingsFile,
      ),
      health: Shared<AppHealth> = Shared(value: AppHealth()),
    ) {
      shortcutBindings = HotkeyBindingsFeature.State(settings: settings, command: .activate)
      _health = health
    }

    // MARK: Internal

    enum CompletionIntent: Equatable {
      case dictation
      case skip
    }

    @Shared var health: AppHealth
    var shortcutBindings: HotkeyBindingsFeature.State
    var isPresented = false
    var snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: false, isCompleted: false,
    )
    var selectedStep: OnboardingStep?
    var isShowingWelcome = false
    var isRecordingModelDownloadConsent = false
    var requestingPermission: OnboardingPermission?
    var pendingSystemPermissionPrompt: OnboardingPermission?
    var requestedPermissions: Set<OnboardingPermission> = []
    var hasCompletedShortcut = false
    var tryItText = ""
    var completionIntent: CompletionIntent?
    var failureMessage: String?

    var step: OnboardingStep {
      OnboardingStep.derive(
        from: snapshot, engineReadiness: health.engineReadiness,
        hasCompletedShortcut: hasCompletedShortcut,
      )
    }

    var engineReadiness: EngineReadiness {
      health.engineReadiness
    }

    var hotkeys: [Hotkey] {
      shortcutBindings.hotkeys
    }

    var isRecordingShortcut: Bool {
      shortcutBindings.isRecording
    }

    var visibleStep: OnboardingStep {
      selectedStep ?? step
    }

    var isRevisitingPermissions: Bool {
      selectedStep == .permissions
    }

    /// The last page always offers the way out, even when the steps before it are unfinished.
    /// Almost nobody should leave here with a permission missing, but the app says plainly what
    /// is broken once they do, and refusing to let them out says nothing at all.
    var canSkip: Bool {
      isPresented && visibleStep == .tryIt
    }

    var isMarkingCompletion: Bool {
      completionIntent != nil
    }

    var shouldShowWelcome: Bool {
      !snapshot.isCompleted && !snapshot.hasModelDownloadConsent
    }

    var activePermission: OnboardingPermission? {
      OnboardingPermission.allCases.first { !snapshot.permissions.isGranted($0) }
    }

    /// macOS prompts at most once per permission, so an unfulfilled request means the rest of the
    /// fix has to happen in System Settings.
    func needsSystemSettings(for permission: OnboardingPermission) -> Bool {
      guard !snapshot.permissions.isGranted(permission) else {
        return false
      }
      return requestedPermissions.contains(permission)
        || (permission == .microphone
          && (snapshot.permissions.microphoneStatus == .denied
            || snapshot.permissions.microphoneStatus == .restricted))
    }

    func canRequest(_ permission: OnboardingPermission) -> Bool {
      activePermission == permission && !requestedPermissions.contains(permission)
    }
  }

  enum Action: Equatable {
    case present(OnboardingSnapshot)
    case downloadModel
    case modelDownloadConsented
    case modelDownloadConsentFailed(String)
    case navigate(OnboardingStep)
    case shortcutBindings(HotkeyBindingsFeature.Action)
    case shortcutContinueTapped
    case requestPermission(OnboardingPermission)
    case microphonePermissionRequested(MicPermissionStatus)
    case accessibilityPermissionRequested(Bool)
    case permissionStatusesObserved(OnboardingPermissionStatuses)
    case refreshPermissionStatuses
    case applicationBecameActive
    case openSystemSettings(OnboardingPermission)
    case workspaceOpenFailed(String)
    case setupModel
    case modelSetupFailed(String)
    case tryItTextChanged(String)
    case tryItFailed(String)
    case dictationDelivered(String)
    case skip
    case completionMarked
    case completionMarkFailed(String)
    case finish
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      case dismissed
      case setupModelRequested
      case permissionsUpdated(OnboardingPermissionStatuses)
      case completed
    }
  }

  static let permissionPollInterval = Duration.seconds(1)

  @Dependency(\.accessibilityPermission) var accessibilityPermission
  @Dependency(\.continuousClock) var clock
  @Dependency(\.microphonePermission) var microphonePermission
  @Dependency(\.onboardingCompletion) var onboardingCompletion
  @Dependency(\.workspace) var workspace

  var body: some ReducerOf<Self> {
    Scope(state: \.shortcutBindings, action: \.shortcutBindings) { HotkeyBindingsFeature() }

    Reduce { state, action in
      switch action {
      case let .present(snapshot):
        state.isPresented = true
        state.snapshot = snapshot
        state.selectedStep = nil
        state.isShowingWelcome = state.shouldShowWelcome
        state.isRecordingModelDownloadConsent = false
        state.requestingPermission = nil
        state.pendingSystemPermissionPrompt = nil
        state.requestedPermissions = []
        state.hasCompletedShortcut = false
        state.tryItText = ""
        state.completionIntent = nil
        state.failureMessage = nil
        let polling = permissionPollingEffect(for: state)
        return snapshot.hasModelDownloadConsent
          ? .merge(polling, modelSetupEffect(for: &state)) : polling
      case .downloadModel:
        guard !state.isRecordingModelDownloadConsent else {
          return .none
        }
        state.isRecordingModelDownloadConsent = true
        state.failureMessage = nil
        return .send(.delegate(.setupModelRequested))
      case .modelDownloadConsented:
        state.snapshot.hasModelDownloadConsent = true
        state.isShowingWelcome = false
        state.isRecordingModelDownloadConsent = false
        return modelSetupEffect(for: &state)
      case let .modelDownloadConsentFailed(message):
        state.isRecordingModelDownloadConsent = false
        state.failureMessage = message
        return .none
      case let .navigate(step):
        guard step != .ready, !state.isRecordingShortcut else {
          return .none
        }
        state.selectedStep = step
        let polling = permissionPollingEffect(for: state)
        return step == .permissions
          ? .merge(refreshPermissionStatuses(for: state), polling) : polling
      case .shortcutContinueTapped:
        guard state.visibleStep == .shortcut, !state.isRecordingShortcut else {
          return .none
        }
        state.hasCompletedShortcut = true
        state.selectedStep = nil
        return .none
      case .shortcutBindings:
        return .none
      case let .requestPermission(permission):
        guard state.requestingPermission == nil, state.canRequest(permission) else {
          return .none
        }
        state.requestingPermission = permission
        state.pendingSystemPermissionPrompt = permission
        state.requestedPermissions.insert(permission)
        state.failureMessage = nil
        let request: Effect<Action> =
          switch permission {
          case .microphone:
            .run { send in
              onboardingLogger.notice("Requesting Microphone permission from onboarding")
              let status = await microphonePermission.requestIfNeeded()
              onboardingLogger.notice("Microphone request returned")
              await send(.microphonePermissionRequested(status))
            }
          case .accessibility:
            .run { send in
              onboardingLogger.notice("Requesting Accessibility permission from onboarding")
              let granted = await accessibilityPermission.requestPermission()
              onboardingLogger.notice("Accessibility request returned granted=\(granted)")
              await send(.accessibilityPermissionRequested(granted))
            }
          }
        return .concatenate(.cancel(id: CancelID.permissionPolling), request)
      case let .microphonePermissionRequested(status):
        state.requestingPermission = nil
        state.pendingSystemPermissionPrompt = nil
        var statuses = state.snapshot.permissions
        statuses.microphoneStatus = status
        return .merge(apply(statuses, to: &state), permissionPollingEffect(for: state))
      case let .accessibilityPermissionRequested(granted):
        state.requestingPermission = nil
        guard granted else {
          return .none
        }
        state.pendingSystemPermissionPrompt = nil
        var statuses = state.snapshot.permissions
        statuses.hasAccessibilityPermission = true
        return .merge(apply(statuses, to: &state), permissionPollingEffect(for: state))
      case let .permissionStatusesObserved(statuses):
        guard state.pendingSystemPermissionPrompt == nil else {
          return .none
        }
        state.requestingPermission = nil
        return apply(statuses, to: &state)
      case .refreshPermissionStatuses:
        return refreshPermissionStatuses(for: state)
      case .applicationBecameActive:
        onboardingLogger.notice("Onboarding became active; resuming permission observation")
        state.pendingSystemPermissionPrompt = nil
        return .merge(refreshPermissionStatuses(for: state), permissionPollingEffect(for: state))
      case let .openSystemSettings(permission):
        let destination = permission.settingsPane
        return .run { send in
          do { try await workspace.open(destination) } catch {
            await send(.workspaceOpenFailed(error.localizedDescription))
          }
        }
      case let .workspaceOpenFailed(message):
        state.failureMessage = message
        return .none
      case .setupModel:
        return modelSetupEffect(for: &state)
      case let .modelSetupFailed(message):
        state.failureMessage = message
        return .none
      case let .tryItTextChanged(text):
        state.tryItText = text
        return .none
      case let .tryItFailed(message):
        guard state.step == .tryIt else {
          return .none
        }
        state.failureMessage = message
        return .none
      case let .dictationDelivered(transcript):
        guard state.step == .tryIt, !state.isMarkingCompletion else {
          return .none
        }
        state.tryItText = transcript
        state.completionIntent = .dictation
        state.failureMessage = nil
        return markCompletion()
      case .skip:
        guard state.canSkip, !state.isMarkingCompletion else {
          return .none
        }
        state.completionIntent = .skip
        state.failureMessage = nil
        return markCompletion()
      case .completionMarked:
        let dismissesAfterCompletion = state.completionIntent == .skip
        state.snapshot.isCompleted = true
        state.selectedStep = nil
        state.completionIntent = nil
        let completed = Effect<Action>.send(.delegate(.completed))
        return dismissesAfterCompletion ? .concatenate(completed, .send(.finish)) : completed
      case let .completionMarkFailed(message):
        state.completionIntent = nil
        state.failureMessage = message
        return .none
      // Onboarding being over is what permits the window to close — not the flow having been
      // walked to its end. A skip from an unfinished step is over just as surely.
      case .finish:
        guard state.snapshot.isCompleted else {
          return .none
        }
        state.isPresented = false
        return .merge(.cancel(id: CancelID.permissionPolling), .send(.delegate(.dismissed)))
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID { case permissionPolling }

  private func apply(
    _ statuses: OnboardingPermissionStatuses, to state: inout State,
  ) -> Effect<Action> {
    let previous = state.snapshot.permissions
    state.snapshot.permissions = statuses
    guard statuses != previous else {
      return .none
    }

    let update = Effect<Action>.send(.delegate(.permissionsUpdated(statuses)))
    return statuses.allGranted && !previous.allGranted
      ? .merge(update, .cancel(id: CancelID.permissionPolling)) : update
  }

  private func observePermissionStatuses() -> OnboardingPermissionStatuses {
    OnboardingPermissionStatuses(
      microphoneStatus: microphonePermission.status(),
      hasAccessibilityPermission: accessibilityPermission.hasPermission(),
    )
  }

  private func refreshPermissionStatuses(for state: State) -> Effect<Action> {
    guard state.pendingSystemPermissionPrompt == nil else {
      return .none
    }
    return .run { send in
      await send(.permissionStatusesObserved(observePermissionStatuses()))
    }
  }

  private func permissionPollingEffect(for state: State) -> Effect<Action> {
    guard state.pendingSystemPermissionPrompt == nil, state.isPresented,
          state.step == .permissions || state.isRevisitingPermissions
    else {
      return .cancel(id: CancelID.permissionPolling)
    }
    return .run { send in
      while true {
        try await clock.sleep(for: Self.permissionPollInterval)
        await send(.refreshPermissionStatuses)
      }
    }.cancellable(id: CancelID.permissionPolling, cancelInFlight: true)
  }

  private func markCompletion() -> Effect<Action> {
    .run { send in
      do {
        try onboardingCompletion.markCompleted()
        await send(.completionMarked)
      } catch { await send(.completionMarkFailed(error.localizedDescription)) }
    }
  }

  private func modelSetupEffect(for state: inout State) -> Effect<Action> {
    guard state.snapshot.hasModelDownloadConsent,
          !state.engineReadiness.isSetupInProgress,
          state.engineReadiness != .ready
    else {
      return .none
    }
    state.failureMessage = nil
    return .send(.delegate(.setupModelRequested))
  }
}
