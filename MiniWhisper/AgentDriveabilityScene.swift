import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import History
import HotkeyListener
import ModelLibrary
import SpeechDictionary
import TranscriptCleanup

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
    case onboardingWelcomeOffline = "onboarding-welcome-offline"
    case onboardingKeys = "onboarding-keys"
    case onboardingKeysAccurate = "onboarding-keys-accurate"
    case onboardingPermissionsMicrophone = "onboarding-permissions-microphone"
    case onboardingPermissionsAccessibility = "onboarding-permissions-accessibility"
    case onboardingPermissionsAccessibilitySettings =
      "onboarding-permissions-accessibility-settings"
    case onboardingShortcut = "onboarding-shortcut"
    case onboardingModel = "onboarding-model"
    case onboardingModelActionable = "onboarding-model-actionable"
    case onboardingModelOffline = "onboarding-model-offline"
    case onboardingTryIt = "onboarding-try-it"
    case onboardingTryItKeySkipped = "onboarding-try-it-key-skipped"
    case onboardingReady = "onboarding-ready"
    case settings
    case settingsShortcutsKeyboard = "settings-shortcuts-keyboard"
    case settingsMicrophoneUnavailable = "settings-microphone-unavailable"
    case settingsSoundsNoAudio = "settings-sounds-no-audio"
    case settingsDegraded = "settings-degraded"
    case settingsKeyMissing = "settings-key-missing"
    case settingsHistory = "settings-history"
    case settingsDictionary = "settings-dictionary"
    case settingsDictionaryUnreadable = "settings-dictionary-unreadable"
    case settingsProfiles = "settings-profiles"
    case settingsProfilesKeyboard = "settings-profiles-keyboard"
    case settingsProfilesUnconfigured = "settings-profiles-unconfigured"
    case settingsProfilesFactory = "settings-profiles-factory"
    case settingsProfilesOverridden = "settings-profiles-overridden"
    case settingsProfilesDownloading = "settings-profiles-downloading"
    case settingsProfilesAccurate = "settings-profiles-accurate"
    case settingsProfilesOffline = "settings-profiles-offline"
    case settingsProfilesRejected = "settings-profiles-rejected"
    case settingsModels = "settings-models"
    case settingsModelsStates = "settings-models-states"
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
           .settingsDegraded,
           .settingsKeyMissing:
        .settings(.settings, initialFocus: nil)
      case .settingsHistory:
        .settings(.history, initialFocus: nil)
      case .settingsDictionary,
           .settingsDictionaryUnreadable:
        .settings(.dictionary, initialFocus: nil)
      case .settingsProfiles,
           .settingsProfilesUnconfigured,
           .settingsProfilesFactory,
           .settingsProfilesOverridden,
           .settingsProfilesDownloading,
           .settingsProfilesAccurate,
           .settingsProfilesOffline,
           .settingsProfilesRejected:
        .settings(.profiles, initialFocus: nil)
      case .settingsModels,
           .settingsModelsStates:
        .settings(.models, initialFocus: nil)
      case .settingsProfilesKeyboard:
        .settings(.profiles, initialFocus: .detail)
      case .about:
        .about
      default:
        nil
      }
    }

    var initialAction: AppFeature.Action? {
      self == .pillRecording ? .pill(.levelUpdated(0.67)) : nil
    }

    /// What the scene's Keychain already holds, per slot. A pane that has a key and a pane that
    /// does not are different screens, and only the Keychain can say which one this is.
    var seededKeys: [CredentialSlot: String] {
      let custom = CredentialSlot(profile: .custom, provider: .endpoint)
      let haiku = CredentialSlot(profile: .haiku, provider: .anthropic)
      switch self {
      case .settingsProfiles,
           .settingsProfilesKeyboard:
        return [custom: "sk-agent-000000000000", haiku: "sk-ant-agent-scene"]
      case .settingsProfilesOverridden,
           .settingsProfilesDownloading,
           .settingsModels,
           .settingsModelsStates:
        return [haiku: "sk-ant-agent-scene"]
      // The scene's endpoint refuses this key, the way a revoked one is refused.
      case .settingsProfilesRejected:
        return [haiku: "sk-rejected-scene"]
      case .settingsProfilesAccurate:
        return [CredentialSlot(profile: .accurate, provider: .google): "AIzaSyAgentScene"]
      // Past the key page, the default profile's key is in the Keychain the scene answers for.
      case .onboardingPermissionsMicrophone,
           .onboardingPermissionsAccessibility,
           .onboardingPermissionsAccessibilitySettings,
           .onboardingShortcut,
           .onboardingModel,
           .onboardingModelActionable,
           .onboardingTryIt,
           .onboardingReady:
        return [haiku: "sk-ant-agent-scene"]
      default:
        return [:]
      }
    }

    /// What the scene's model library holds. Most scenes have everything installed; a first run
    /// has nothing, and the downloading scenes are partway through.
    var seededAssets: [ModelAsset: AssetState] {
      switch self {
      case .onboardingWelcome,
           .onboardingWelcomeOffline:
        return Dictionary(uniqueKeysWithValues: ModelAsset.allCases.map { ($0, .missing) })
      case .onboardingModelOffline:
        return [
          .gate: .installed(bytes: 3),
          .parakeet: .downloading(0.42),
          .s1Mini: .downloading(0.18),
        ]
      default:
        break
      }
      var assets = Dictionary(
        uniqueKeysWithValues: ModelAsset.allCases.map {
          ($0, AssetState.installed(bytes: $0.pinnedBytes))
        },
      )
      if self == .settingsProfilesDownloading {
        assets[.parakeet] = .downloading(0.42)
      }
      if self == .settingsModelsStates {
        assets[.parakeet] = .downloading(0.42)
        assets[.s1Mini] = .failed("The scene’s download failed.")
      }
      // Offline chosen before its cleanup model is on disk: the picker and the row both say so.
      if self == .settingsProfilesOffline {
        assets[.s1Mini] = .missing
      }
      return assets
    }

    var initialState: AppFeature.State {
      var state = AppFeature.State(
        history: Shared(value: seededHistory), settings: Shared(value: seededSettings),
        dictionary: makeSeededDictionary(),
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
      case .onboardingWelcome,
           .onboardingWelcomeOffline:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(), readiness: .modelMissing, hasConsent: false,
                isShowingWelcome: true)
        state.onboarding.storedKeys = []
      // Consent given and the download running behind the page; the key is what stands between
      // the user and the rest of the rail.
      case .onboardingKeys,
           .onboardingKeysAccurate:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(), readiness: .downloading(0.42))
        state.onboarding.storedKeys = []
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
      case .onboardingModelOffline:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .downloading(0.42), selectedStep: .model, hasCompletedShortcut: true)
      // The key was skipped on its page: the rail went on, and nothing can dictate.
      case .onboardingTryItKeySkipped:
        state.onboardingCompleted = false
        present(&state.onboarding,
                permissions: permissions(microphone: .granted, accessibility: true),
                readiness: .ready, selectedStep: .tryIt, hasCompletedShortcut: true)
        state.onboarding.storedKeys = []
        state.onboarding.hasSkippedKeys = true
        state.$health.withLock { $0.missingCleanupKey = .anthropic }
      case .settingsKeyMissing:
        state.settingsWindow.settingsPane.launchAtLoginRegistered = true
        state.$health.withLock { $0.missingCleanupKey = .anthropic }
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
           .settingsDictionary,
           .settingsDictionaryUnreadable,
           .about:
        break
      case .settingsShortcutsKeyboard:
        state.settingsWindow.interaction.mode = .keyboard
      case .settingsProfiles,
           .settingsProfilesUnconfigured,
           .settingsProfilesFactory,
           .settingsProfilesOverridden,
           .settingsProfilesOffline:
        break
      case .settingsModels:
        break
      case .settingsProfilesDownloading,
           .settingsModelsStates:
        state.$health.withLock { $0.engineReadiness = .downloading(0.42) }
      // The last dictation's cleanup was refused with this key.
      case .settingsProfilesRejected:
        state.$health.withLock {
          _ = $0.rejectedKeys.insert(CredentialSlot(profile: .haiku, provider: .anthropic))
        }
      // Most accurate with only its Google key: the engine is installed and cannot hear yet.
      case .settingsProfilesAccurate:
        state.$health.withLock {
          $0.engine = .scribe
          $0.engineReadiness = .credentialMissing
        }
      case .settingsProfilesKeyboard:
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

    /// File-backed dictionary scenes use the real persistence path; the harness gives each test
    /// process its own file so concurrent runs cannot read each other's words.
    private static let dictionaryFileURL: URL = {
      if let path = ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_DICTIONARY_FILE"] {
        return URL(fileURLWithPath: path)
      }
      return FileManager.default.temporaryDirectory.appending(
        path: "miniwhisper-agent-dictionary-\(ProcessInfo.processInfo.processIdentifier).json",
      )
    }()

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
      case .settingsProfiles,
           .settingsProfilesKeyboard:
        settings.profiles.active = .custom
        settings.profiles.custom = CustomProfileSettings(
          cleanupEnabled: true, endpoint: URL(string: "https://gateway.example/v1"),
          model: "gpt-oss-120b", boostsVocabulary: false,
        )
        settings.additionalInstructions = "Keep my terminology. Never expand contractions."
        return settings
      case .settingsProfilesUnconfigured:
        settings.profiles.active = .custom
        return settings
      case .settingsProfilesFactory,
           .settingsProfilesDownloading,
           .settingsProfilesRejected,
           .settingsModels:
        return settings
      case .settingsProfilesAccurate:
        settings.profiles.active = .accurate
        return settings
      case .settingsProfilesOffline,
           .settingsModelsStates,
           .onboardingWelcomeOffline,
           .onboardingModelOffline:
        settings.profiles.active = .offline
        return settings
      case .onboardingKeysAccurate:
        settings.profiles.active = .accurate
        return settings
      // The dictionary pane's scene runs a profile that never reads the vocabulary, so both of
      // its emphases and Quick Add's marker are on screen without a toggle to reach them.
      case .settingsDictionary:
        settings.profiles.active = .custom
        settings.profiles.custom.boostsVocabulary = false
        return settings
      case .settingsProfilesOverridden:
        settings.profiles.setEndpoint(
          URL(string: "https://aig.thurstons.house/v1")!, for: .haiku,
        )
        return settings
      default:
        return settings
      }
      do {
        try settings.bindings.append(
          Hotkey(keyCode: 15, modifiers: [.rightControl]), for: .activate,
        )
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
          // The one cleaned entry in the catalogue: the row shows the rewrite and holds the
          // transcript underneath it.
          original: Transcription(
            text: "um the history pane keeps every transcript close at hand",
            engine: "test-engine", transcribedAt: today,
            cleanup: CleanupRecord(
              disposition: .cleaned("The history pane keeps every transcript close at hand."),
              model: "gpt-oss-120b", endpoint: URL(string: "https://gateway.example/v1")!,
              durationSeconds: 1.2,
            ),
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
          // A second cleaned entry, so the catalogue can show that the peek is the pane's and
          // not one row's.
          original: Transcription(
            text: "a second deterministic transcript for search and deletion",
            engine: "test-engine", transcribedAt: today,
            cleanup: CleanupRecord(
              disposition: .cleaned("A second deterministic transcript for search and deletion."),
              model: "gpt-oss-120b", endpoint: URL(string: "https://gateway.example/v1")!,
              durationSeconds: 0.9,
            ),
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

    private func makeSeededDictionary() -> Shared<DictionaryContents> {
      if self == .menuHealthy {
        if !FileManager.default.fileExists(atPath: Self.dictionaryFileURL.path) {
          writeDictionaryFixture(encodedEmptyDictionary())
        }
        return fileBacked(Self.dictionaryFileURL)
      }
      if self == .settingsDictionaryUnreadable {
        writeDictionaryFixture(Data("{ unreadable".utf8))
        return fileBacked(Self.dictionaryFileURL)
      }
      guard self == .settingsDictionary else {
        return Shared(value: .empty)
      }
      return Shared(
        value: DictionaryContents(
          vocabulary: [
            VocabularyEntry(
              text: "MiniWhisper", addedAt: Date(timeIntervalSince1970: 1_754_352_000),
            ),
          ],
          corrections: [
            CorrectionEntry(
              misspelling: "mini whisperer", text: "MiniWhisper",
              addedAt: Date(timeIntervalSince1970: 1_754_351_000),
            ),
          ],
        ),
      )
    }

    /// File-backed rather than in-memory: a scene that drives a save has to write where the app
    /// really writes, and the caller has already put the bytes it wants read back at `url`.
    private func encodedEmptyDictionary() -> Data {
      do {
        return try DictionaryCoding.encode(.empty)
      } catch {
        preconditionFailure("Agent scene could not encode an empty dictionary: \(error)")
      }
    }

    private func writeDictionaryFixture(_ data: Data) {
      do {
        try data.write(to: Self.dictionaryFileURL)
      } catch {
        preconditionFailure("Agent scene could not seed dictionary.json: \(error)")
      }
    }

    private func fileBacked(_ url: URL) -> Shared<DictionaryContents> {
      withDependencies {
        $0.defaultFileStorage = .fileSystem
      } operation: {
        Shared(
          wrappedValue: .empty,
          .fileStorage(
            url, decode: DictionaryCoding.decode, encode: DictionaryCoding.encode,
          ),
        )
      }
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
      // A scene's user has already given the profile its keys; the key scenes take them back.
      state.storedKeys = Set(state.profile.credentials)
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
