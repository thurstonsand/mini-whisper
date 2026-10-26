import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import ModelLibrary
import OSLog
import TranscriptCleanup

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
  case keys
  case permissions
  case shortcut
  case model
  case tryIt
  case ready

  // MARK: Internal

  static func derive(
    from snapshot: OnboardingSnapshot, isMissingKeys: Bool, isSetUp: Bool,
    hasCompletedShortcut: Bool,
  ) -> Self {
    guard !isMissingKeys else {
      return .keys
    }
    guard snapshot.permissions.allGranted else {
      return .permissions
    }
    guard hasCompletedShortcut else {
      return .shortcut
    }
    guard isSetUp else {
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
      _settings = settings
      _health = health
    }

    // MARK: Internal

    enum CompletionIntent: Equatable {
      case dictation
      case skip
    }

    @Shared var settings: MiniWhisperSettings
    @Shared var health: AppHealth
    /// Which of the active profile's keys the Keychain holds. Unread is not missing: until the
    /// Keychain has answered, no step is shown that it might not need.
    var storedKeys: Set<CredentialSlot>?
    var keyDrafts: [CredentialSlot: String] = [:]
    /// The user chose to go on without the keys. Not advised: the profile does not dictate until
    /// they are added in Settings.
    var hasSkippedKeys = false
    /// The cleanup key is being proven against its endpoint before it is stored.
    var isCheckingKeys = false
    var assets: [ModelAsset: AssetState] = [:]
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
        from: snapshot, isMissingKeys: !missingKeys.isEmpty && !hasSkippedKeys, isSetUp: isSetUp,
        hasCompletedShortcut: hasCompletedShortcut,
      )
    }

    var profile: Profile {
      settings.activeProfile
    }

    var missingKeys: [CredentialSlot] {
      guard let storedKeys else {
        return []
      }
      return profile.credentials.filter { !storedKeys.contains($0) }
    }

    /// Every missing key has something typed for it, and none is already being proven.
    var canContinueFromKeys: Bool {
      visibleStep == .keys && !isCheckingKeys
        && missingKeys.allSatisfy { !draft(for: $0).isEmpty }
    }

    /// Models the profile needs that no engine owns. The engine's own models report through its
    /// readiness; these report only through the library.
    var cleanupAssets: [ModelAsset] {
      profile.assets.filter { !profile.engine.assets.contains($0) }
    }

    var isSetUp: Bool {
      engineReadiness == .ready && cleanupAssets.allSatisfy { assets[$0]?.isInstalled == true }
    }

    /// What the welcome button downloads. The gate is a megabyte and goes along silently, so it
    /// never names the button on its own.
    var pendingDownloads: [ModelAsset] {
      profile.assets.filter { $0 != .gate && assets[$0]?.isInstalled != true }
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

    /// Try It needs a dictation that can run, and a profile still missing its key cannot.
    var canTryDictation: Bool {
      step == .tryIt && missingKeys.isEmpty
    }

    var welcomeActionTitle: String {
      switch pendingDownloads.count {
      case 0:
        "Get Started"
      default:
        "Download \(pendingDownloads.map(\.name).formatted(.list(type: .and)))"
      }
    }

    var welcomeFootnote: String {
      var sentences: [String] = []
      if !pendingDownloads.isEmpty {
        let bytes = pendingDownloads.map(\.pinnedBytes).reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        sentences.append("\(size) downloads while you finish setup.")
      }
      if !missingKeys.isEmpty {
        sentences.append("You’ll add \(Self.keysPhrase(missingKeys)) next.")
      }
      return sentences.isEmpty
        ? "Everything it needs is already on this Mac." : sentences.joined(separator: " ")
    }

    /// A missing key is the key step's business, not a download's.
    var needsModelSetup: Bool {
      let engineNeedsSetup = !engineReadiness.isSetupInProgress && engineReadiness != .ready
        && engineReadiness != .credentialMissing
      return engineNeedsSetup || cleanupAssets.contains { assets[$0]?.isDownloadable == true }
    }

    var canContinueFromModel: Bool {
      visibleStep == .model && isSetUp && step.rawValue > OnboardingStep.model.rawValue
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

    /// The keys as a sentence names them: "an Anthropic key", "ElevenLabs and Google keys".
    static func keysPhrase(_ slots: [CredentialSlot]) -> String {
      guard slots.count > 1 else {
        return slots[0].provider.keyPhrase
      }
      return "\(slots.map(\.provider.displayName).formatted(.list(type: .and))) keys"
    }

    func draft(for slot: CredentialSlot) -> String {
      (keyDrafts[slot] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
    case task
    case assetsUpdated([ModelAsset: AssetState])
    case present(OnboardingSnapshot)
    case profileSelected(ProfileID)
    case keyEdited(CredentialSlot, String)
    case keysContinueTapped
    case keysVerified
    case keysCheckFailed(String)
    case keysSkipped
    case useCustomTapped
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
    case modelContinueTapped
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
      case profileSelected
      case keysStored
      case dismissed
      case setupModelRequested
      case permissionsUpdated(OnboardingPermissionStatuses)
      case completed
    }
  }

  static let permissionPollInterval = Duration.seconds(1)

  @Dependency(\.accessibilityPermission) var accessibilityPermission
  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.cleanup) var cleanup
  @Dependency(\.continuousClock) var clock
  @Dependency(\.keychain) var keychain
  @Dependency(\.microphonePermission) var microphonePermission
  @Dependency(\.modelLibrary) var modelLibrary
  @Dependency(\.onboardingCompletion) var onboardingCompletion
  @Dependency(\.workspace) var workspace

  var body: some ReducerOf<Self> {
    Scope(state: \.shortcutBindings, action: \.shortcutBindings) { HotkeyBindingsFeature() }

    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in
          for await states in modelLibrary.states() {
            await send(.assetsUpdated(states))
          }
        }
      case let .assetsUpdated(states):
        state.assets = states
        return .none
      case let .present(snapshot):
        state.isPresented = true
        state.storedKeys = storedKeys(of: state.profile)
        state.keyDrafts = [:]
        state.hasSkippedKeys = false
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
      // The choice is made before anything downloads, so it is only ever a choice: the button
      // under the cards is what starts this profile's download.
      case let .profileSelected(id):
        guard state.isShowingWelcome, !state.isRecordingModelDownloadConsent else {
          return .none
        }
        state.$settings.withLock { $0.profiles.active = id }
        state.storedKeys = storedKeys(of: state.profile)
        state.keyDrafts = [:]
        state.hasSkippedKeys = false
        return .send(.delegate(.profileSelected))
      case let .keyEdited(slot, text):
        state.keyDrafts[slot] = text
        return .none
      // Every key is proven before any is stored, as the pane's Save proves them.
      case .keysContinueTapped:
        guard state.canContinueFromKeys else {
          return .none
        }
        let engine = state.profile.engine
        var engineKey: (provider: String, key: String)?
        if let slot = state.profile.engineCredential, state.missingKeys.contains(slot) {
          engineKey = (slot.provider.displayName, state.draft(for: slot))
        }
        var cleanupKey: (provider: String, key: String, configuration: CleanupConfiguration)?
        if let leg = state.profile.endpointLeg, state.missingKeys.contains(leg.credential),
           let endpoint = leg.endpoint, let model = leg.model
        {
          cleanupKey = (
            leg.credential.provider.displayName, state.draft(for: leg.credential),
            CleanupConfiguration(
              endpoint: endpoint, model: model, timeout: CleanupConfiguration.verificationTimeout,
              additionalInstructions: "",
            ),
          )
        }
        guard engineKey != nil || cleanupKey != nil else {
          return .send(.keysVerified)
        }
        state.isCheckingKeys = true
        state.failureMessage = nil
        return .run { [engineKey, cleanupKey] send in
          if let (provider, key) = engineKey {
            do {
              try await asrEngine.verifyKey(engine, key)
            } catch ASREngineError.credentialRejected {
              await send(.keysCheckFailed("Invalid \(provider) key."))
              return
            } catch is URLError {
              await send(.keysCheckFailed("Couldn’t reach \(provider)."))
              return
            } catch {
              onboardingLogger.error(
                "Key check failed: \(error.localizedDescription, privacy: .public)",
              )
              await send(.keysCheckFailed("Couldn’t check the key with \(provider)."))
              return
            }
          }
          if let (provider, key, configuration) = cleanupKey {
            switch await cleanup.verify(configuration, key) {
            case .verified:
              break
            case .cancelled:
              await send(.keysCheckFailed("Couldn’t check the key with \(provider)."))
              return
            case let .failed(failure):
              onboardingLogger.error(
                "Key check failed: \(failure.localizedDescription, privacy: .public)",
              )
              if failure.rejectsKey {
                await send(.keysCheckFailed("Invalid \(provider) key."))
                return
              }
              switch failure {
              case .unreachable,
                   .timedOut:
                await send(.keysCheckFailed("Couldn’t reach \(provider)."))
              default:
                await send(.keysCheckFailed("Couldn’t check the key with \(provider)."))
              }
              return
            }
          }
          await send(.keysVerified)
        }
      case let .keysCheckFailed(message):
        state.isCheckingKeys = false
        state.failureMessage = message
        return .none
      case .keysVerified:
        state.isCheckingKeys = false
        do {
          for slot in state.missingKeys {
            try keychain.store(state.draft(for: slot), slot)
          }
        } catch {
          state.failureMessage = "Couldn’t save the key to the Keychain."
          onboardingLogger
            .error("Key store failed: \(error.localizedDescription, privacy: .public)")
          return .none
        }
        state.storedKeys = storedKeys(of: state.profile)
        state.keyDrafts = [:]
        state.failureMessage = nil
        state.selectedStep = nil
        return .send(.delegate(.keysStored))
      case .keysSkipped:
        guard state.visibleStep == .keys else {
          return .none
        }
        state.hasSkippedKeys = true
        state.keyDrafts = [:]
        state.failureMessage = nil
        state.selectedStep = nil
        return .none
      // The other way past a factory profile's keys is a profile that needs none. Custom shares
      // the factory engine, so whatever is already downloading is still what it needs.
      case .useCustomTapped:
        guard state.visibleStep == .keys else {
          return .none
        }
        state.$settings.withLock {
          $0.profiles.active = .custom
          $0.profiles.custom.cleanupEnabled = false
        }
        state.storedKeys = storedKeys(of: state.profile)
        state.keyDrafts = [:]
        state.failureMessage = nil
        state.selectedStep = nil
        return .send(.delegate(.profileSelected))
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
      case .modelContinueTapped:
        guard state.canContinueFromModel else {
          return .none
        }
        state.selectedStep = nil
        return .none
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

  private func storedKeys(of profile: Profile) -> Set<CredentialSlot> {
    Set(profile.credentials.filter { slot in
      do {
        return try keychain.read(slot) != nil
      } catch {
        onboardingLogger.error("Key unreadable: \(error.localizedDescription, privacy: .public)")
        return false
      }
    })
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
    guard state.snapshot.hasModelDownloadConsent, state.needsModelSetup else {
      return .none
    }
    state.failureMessage = nil
    return .send(.delegate(.setupModelRequested))
  }
}
