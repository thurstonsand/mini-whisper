import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
import ModelLibrary
import OSLog
import SpeechDictionary
import TranscriptCleanup

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")
private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")
private let deliveryLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "delivery")
private let settingsLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "settings",
)
private let menuLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "menu")
let historyLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "history")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - AppFeature

@Reducer struct AppFeature {
  // MARK: Internal

  struct StartupFacts: Equatable {
    var onboardingCompleted: Bool
    var modelDownloadConsented: Bool
    var permissions: OnboardingPermissionStatuses
    var engineReadiness: EngineReadiness
  }

  struct DeliveryResult: Equatable {
    var text: String
    var targetApp: TargetApp?
    var outcome: DeliveryOutcome
  }

  struct DeliveryFailure: Equatable {
    var text: String
    var targetApp: TargetApp?
    var message: String
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(
      history: Shared<HistoryLog> = Shared(
        wrappedValue: HistoryLog(), .fileStorage(Channel.historyFile),
      ),
      settings: Shared<MiniWhisperSettings> = Shared(
        wrappedValue: .defaults, .settingsFile,
      ),
      dictionary: Shared<DictionaryContents> = Shared(
        wrappedValue: .empty, .dictionaryFile,
      ),
      // Nothing has been read from the system yet, so the app starts as broken as it could be.
      health: Shared<AppHealth> = Shared(value: AppHealth()),
    ) {
      _history = history
      _settings = settings
      _dictionary = dictionary
      _health = health
      recording = RecordingFeature.State(settings: settings, health: health)
      onboarding = OnboardingFeature.State(settings: settings, health: health)
      settingsWindow = SettingsWindowFeature.State(
        history: history, settings: settings, dictionary: dictionary, health: health,
      )
    }

    // MARK: Internal

    var recording: RecordingFeature.State
    var pill = PillFeature.State()
    var onboarding: OnboardingFeature.State
    var settingsWindow: SettingsWindowFeature.State
    var transcriptionGeneration = 0
    /// Escape revoked delivery for the dictation now in flight. Only `startRecording` clears it,
    /// so it can never survive into another one, and only a matching generation can read it.
    var dictationWasCancelled = false
    var gestureMachine = HotkeyGestureMachine()
    var gestureDeadlineGeneration = 0
    var inputDeviceName: String?
    var lastTranscript: String?
    var pendingDictation: PendingDictation?
    /// Dictations whose cleanup pass the user skipped. The press that skipped one handed the
    /// pill, the generation, and the field to its successor, so it is no longer the dictation in
    /// flight — but it is still owed a paste and an entry, and waits here under the generation it
    /// was until it has both.
    var skippedDictations: [Int: PendingDictation] = [:]
    var dictationInFlight = false
    var historyMaintenance = HistoryMaintenanceState.idle
    @Shared var history: HistoryLog
    @Shared var settings: MiniWhisperSettings
    @Shared var dictionary: DictionaryContents
    @Shared var health: AppHealth
    var onboardingCompleted = false

    var storesAudio: Bool {
      settings.retention.audio != .never
    }

    var canBeginDictation: Bool {
      guard onboarding.isPresented else {
        return onboardingCompleted
      }
      return onboarding.step == .tryIt && onboarding.visibleStep == .tryIt
    }

    var menuBar: MenuBarViewState {
      MenuBarViewState(
        degradations: health.degradations, engineReadiness: health.engineReadiness,
        engineStatusText: health.engineStatusText, inputDeviceName: inputDeviceName,
        canCopyLastTranscript: lastTranscript != nil,
      )
    }
  }

  enum Action: Equatable {
    case task
    case startupResolved(StartupFacts)
    case historyMaintenanceRequested
    case historyMaintenanceCompleted(HistoryLog)
    case historyMaintenanceFailed(String)
    case historyEntryPrepared(Int, HistoryEntry)
    case historyEntryAbandoned(Int)
    case historyPersistenceFailed(String)
    case applicationBecameActive
    case recording(RecordingFeature.Action)
    case pill(PillFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case settingsWindow(SettingsWindowFeature.Action)
    case hotkeyListenerEvent(HotkeyListenerEvent<HotkeyAction>)
    case pasteLastTranscript
    case recoveryDeliveryCompleted(DeliveryResult)
    case recoveryDeliveryFailed(DeliveryFailure)
    case hotkeyListenerFailed(String)
    case hotkeyListenerFinished
    case gestureDeadlineElapsed(Int)
    case menuWillOpen
    case repairRequested(Degradation)
    case copyLastTranscript
    case copyLastTranscriptFailed(String)
    case workspaceOpenFailed(String)
    case modelDownloadConsentRecorded
    case modelDownloadConsentRecordingFailed(String)
    case engineReadinessUpdated(SpeechEngine, EngineReadiness)
    /// Agent-driveability state injection. In Release, `AgentDriveabilityScene` has no cases and
    /// no caller constructs either action.
    case agentScenePresented(AgentDriveabilityScene)
    case agentHistoryReplaced(HistoryLog)
    case transcriptionCompleted(Int, TranscriptionOutcome)
    case transcriptionFailed(Int, String)
    case contextCaptured(Int, ContextCapture, TargetApp?)
    case cleanupStarted(Int, CleanupConfiguration)
    case cleanupResolved(Int, CleanupResolution)
    case deliveryCompleted(Int, DeliveryResult)
    case deliveryFailed(Int, DeliveryFailure)
    case skippedDeliveryCompleted(Int, DeliveryResult)
    case skippedDeliveryFailed(Int, DeliveryFailure)
    case skippedDictationArchived(HistoryEntry?)
  }

  enum CancelID: Hashable {
    case transcription
    case capture
    case cleanup
    case delivery
    case skippedDelivery(Int)
    case historyMaintenance
    case hotkeyEvents
    case gestureDeadline
  }

  @Dependency(\.accessibilityPermission) var accessibilityPermission
  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.contextCapture) var contextCapture
  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.delivery) var delivery
  @Dependency(\.historyClient) var historyClient
  @Dependency(\.hotkeyListener) var hotkeyListener
  @Dependency(\.microphonePermission) var microphonePermission
  @Dependency(\.keychain) var keychain
  @Dependency(\.modelDownloadConsent) var modelDownloadConsent
  @Dependency(\.modelLibrary) var modelLibrary
  @Dependency(\.cleanup) var cleanup
  @Dependency(\.onboardingCompletion) var onboardingCompletion
  @Dependency(\.sounds) var sounds
  @Dependency(\.uuid) var uuid
  @Dependency(\.workspace) var workspace

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }
    Scope(state: \.pill, action: \.pill) { PillFeature() }
    Scope(state: \.onboarding, action: \.onboarding) { OnboardingFeature() }
    Scope(state: \.settingsWindow, action: \.settingsWindow) { SettingsWindowFeature() }

    Reduce { state, action in
      switch action {
      case .settingsWindow(.history(.delegate(.retentionChanged))):
        return .send(.historyMaintenanceRequested)
      case .settingsWindow(.dictionary(.delegate(.quickAddPersistenceFailed))):
        return .send(.pill(.dictionarySaveFailed))
      case .settingsWindow(.settingsPane(.task)):
        state.$health.withLock { $0.micStatus = microphonePermission.status() }
        return .none
      case let .settingsWindow(.settingsPane(.delegate(.microphoneChanged(selection)))):
        return .send(.recording(.microphoneChanged(selection)))
      case let .settingsWindow(.settingsPane(.delegate(.repair(repair)))):
        return .send(.repairRequested(repair))
      case let .settingsWindow(.models(.delegate(.deleteAsset(asset)))):
        return deleteAsset(asset, &state)
      // The child has already made the choice; the app follows it to the engine it names.
      case .settingsWindow(.profiles(.profileSelected)):
        checkCleanupKey(&state)
        return .merge(activateEngine(&state), prepareLocalCleanup(state))
      case let .settingsWindow(.models(.delegate(.downloadAsset(asset)))):
        return downloadAsset(asset, &state)
      // A cleanup model downloading during onboarding is part of the Speech Model step, so its
      // failure is said there as well as in the pane.
      case let .settingsWindow(.models(.assetDownloadFailed(message))):
        return state.onboarding.isPresented ? .send(.onboarding(.modelSetupFailed(message))) : .none
      // A hosted engine's key is read when it is needed, so a new one only has to be noticed.
      case let .settingsWindow(.profiles(.delegate(.keysStored(slots)))):
        checkCleanupKey(&state)
        guard let engineSlot = state.settings.activeProfile.engineCredential,
              slots.contains(engineSlot)
        else {
          return .none
        }
        return prepareInstalled(state.health.engine)
      case let .settingsWindow(
        .settingsPane(.bindingEditors(.element(id: command, action: .delegate(.recordingStarted)))),
      ):
        return beginHotkeyRecording(
          &state,
          recorderReady: .settingsWindow(
            .settingsPane(.bindingEditors(.element(id: command, action: .recorderReady))),
          ),
        )
      case .onboarding(.shortcutBindings(.delegate(.recordingStarted))):
        return beginHotkeyRecording(
          &state, recorderReady: .onboarding(.shortcutBindings(.recorderReady)),
        )
      case .settingsWindow(
        .settingsPane(.bindingEditors(.element(id: _, action: .delegate(.recordingStopped)))),
      ),
      .settingsWindow(
        .settingsPane(.bindingEditors(.element(id: _, action: .delegate(.bindingsChanged)))),
      ),
      .onboarding(.shortcutBindings(.delegate(.recordingStopped))),
      .onboarding(.shortcutBindings(.delegate(.bindingsChanged))):
        return restartHotkeyListener(&state)
      case .settingsWindow:
        return .none
      case .task:
        if let error = state.$settings.loadError {
          settingsLogger.error(
            """
            Settings failed to load, so the defaults are in effect and \
            \(Channel.settingsFile.path, privacy: .public) has been left as it is: \
            \(error.localizedDescription, privacy: .public)
            """,
          )
        }
        if let error = state.$dictionary.loadError {
          settingsLogger.error(
            """
            Dictionary failed to load, so corrections are not being applied and \
            \(Channel.dictionaryFile.path, privacy: .public) has been left as it is: \
            \(error.localizedDescription, privacy: .public)
            """,
          )
        }
        state.$health.withLock { $0.engine = state.settings.activeProfile.engine }
        checkCleanupKey(&state)
        return .merge(
          .send(.recording(.task)), startupEffect(state.health.engine),
          prepareLocalCleanup(state), .send(.historyMaintenanceRequested),
          seedSettingsFile(state.$settings),
        )
      case .historyMaintenanceRequested:
        if let error = state.$history.loadError {
          return .send(
            .historyMaintenanceFailed("History failed to load: \(error.localizedDescription)"),
          )
        }
        guard !state.dictationInFlight else {
          state.historyMaintenance = .waiting
          return .none
        }
        state.historyMaintenance = .running
        return historyMaintenanceEffect(
          log: state.history, policy: state.settings.retention, now: now,
        )
      case let .historyMaintenanceCompleted(log):
        state.historyMaintenance = .idle
        state.$history.withLock { $0 = log }
        return saveHistory(state.$history)
      case let .historyMaintenanceFailed(message):
        state.historyMaintenance = .idle
        historyLogger.error("History maintenance failed: \(message, privacy: .public)")
        return .none
      case let .historyEntryPrepared(generation, entry):
        guard generation == state.transcriptionGeneration,
              state.pendingDictation?.generation == generation,
              state.pendingDictation?.isFinishing == true
        else {
          return entry.audio == nil ? .none : deleteHistoryAudio([entry.id])
        }
        state.pendingDictation = nil
        state.dictationInFlight = false
        if let error = state.$history.loadError {
          return .merge(
            entry.audio == nil ? .none : deleteHistoryAudio([entry.id]),
            .send(
              .historyPersistenceFailed(
                "History failed to load; refusing to overwrite it: \(error.localizedDescription)",
              ),
            ),
          )
        }
        state.$history.withLock { $0.entries.insert(entry, at: 0) }
        return saveHistory(state.$history)
      case let .historyEntryAbandoned(generation):
        guard generation == state.transcriptionGeneration,
              state.pendingDictation?.generation == generation,
              state.pendingDictation?.isFinishing == true
        else {
          return .none
        }
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .none
      case let .historyPersistenceFailed(message):
        historyLogger.error("History failed to persist: \(message, privacy: .public)")
        return .none
      case let .startupResolved(facts):
        state.onboardingCompleted = facts.onboardingCompleted
        state.$health.withLock { $0.micStatus = facts.permissions.microphoneStatus }
        state.$health.withLock { $0.engineReadiness = facts.engineReadiness }
        logEngineReadiness(facts.engineReadiness, state.health.engine)

        var effects = [
          reconcileAccessibility(facts.permissions.hasAccessibilityPermission, &state),
        ]
        // Consent is what makes a download durable, so an interrupted one resumes here rather
        // than waiting for a user who has finished onboarding to find the menu bar. A failed
        // setup is left alone: retrying it every launch would be a network loop nobody asked for.
        if facts.modelDownloadConsented,
           facts.engineReadiness == .modelMissing
           || !facts.onboardingCompleted && needsCleanupModel(state)
        {
          effects.append(setUpModel(&state))
        }
        if !facts.onboardingCompleted {
          effects.append(
            .send(
              .onboarding(
                .present(
                  OnboardingSnapshot(
                    permissions: facts.permissions,
                    hasModelDownloadConsent: facts.modelDownloadConsented, isCompleted: false,
                  ),
                ),
              ),
            ),
          )
        }
        return .merge(effects)
      // Returning from System Settings is the moment new grants become visible, and macOS never
      // tells the app about either permission changing. Read exactly as the menu does.
      case .applicationBecameActive:
        state.$health.withLock { $0.micStatus = microphonePermission.status() }
        return reconcileAccessibility(accessibilityPermission.hasPermission(), &state)
      case .hotkeyListenerEvent(.accessibilityPermissionMissing):
        gestureLogger.error("Accessibility permission missing — grant in System Settings")
        return reconcileAccessibility(false, &state)
      case .hotkeyListenerEvent(.monitoringStarted):
        state.$health.withLock { $0.hotkeyTap = .active }
        gestureLogger.notice("Hotkey event tap installed")
        return .none
      case let .hotkeyListenerEvent(.monitoringInterrupted(reason)):
        gestureLogger.error("Hotkey event tap interrupted: \(reason.rawValue, privacy: .public)")
        // Timeout and user-input disables are re-enabled in place; only invalidation kills the
        // tap.
        return reason == .invalidated ? diagnoseTapLoss(&state) : .none
      case let .hotkeyListenerEvent(.gestureInput(input)):
        return receiveGestureInput(input, state: &state)
      case .hotkeyListenerEvent(.action(.pasteLastTranscript)):
        return .send(.pasteLastTranscript)
      case let .gestureDeadlineElapsed(generation):
        guard generation == state.gestureDeadlineGeneration else {
          return .none
        }
        return receiveGestureInput(.deadlineElapsed, state: &state)
      case let .hotkeyListenerEvent(.gesture(event)):
        return performGesture(event, state: &state)
      // A tap the app deliberately stood down — to record a shortcut, or because none is bound —
      // reports its own ending. Only a tap that was wanted can be said to have been lost.
      case let .hotkeyListenerFailed(error):
        guard state.health.hotkeyTap != .idle else {
          return .none
        }
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return diagnoseTapLoss(&state)
      case .hotkeyListenerFinished:
        guard state.health.hotkeyTap != .idle else {
          return .none
        }
        gestureLogger.error("Hotkey event stream ended; the tap is no longer listening")
        return diagnoseTapLoss(&state)
      // Everything the menu is about to say is read here, in full, before it is built: the
      // controller rebuilds on the very next line, and a fact that arrives an effect later
      // arrives behind the menu the user is already reading.
      case .menuWillOpen:
        state.inputDeviceName = audioCapture.currentInputDeviceName(state.settings.microphone)
        state.$health.withLock { $0.micStatus = microphonePermission.status() }
        return reconcileAccessibility(accessibilityPermission.hasPermission(), &state)
      case let .repairRequested(degradation):
        return repair(degradation, state: &state)
      case .pasteLastTranscript:
        guard !state.dictationInFlight else {
          return .none
        }
        guard let transcript = state.lastTranscript ?? state.history.entries.first?.displayText
        else {
          return .send(.pill(.noTranscriptToPaste))
        }
        return recoveryDeliveryEffect(transcript: transcript)
      case let .recoveryDeliveryCompleted(result):
        switch result.outcome {
        case let .pasted(restoration):
          logSuccessfulPaste(restoration)
          return .merge(
            .send(.pill(.dismiss)), playSound(state.settings.sounds.complete),
          )
        case let .copied(fallback):
          logDeliveryFallback(fallback)
          return .merge(
            .send(.pill(.copiedToClipboard)), playSound(state.settings.sounds.error),
          )
        case .noReceiver:
          return .merge(
            .send(.pill(noReceiverNotice(settings: state.settings.bindings))),
            playSound(state.settings.sounds.error),
          )
        }
      case let .recoveryDeliveryFailed(failure):
        deliveryLogger.error(
          "Recovery delivery failed: \(failure.message, privacy: .public)",
        )
        return .merge(
          .send(.pill(.dismiss)), playSound(state.settings.sounds.error),
        )
      case .copyLastTranscript:
        guard let transcript = state.lastTranscript else {
          return .none
        }
        return .run { send in
          do { try await delivery.copy(transcript) } catch {
            await send(.copyLastTranscriptFailed(error.localizedDescription))
          }
        }
      case let .copyLastTranscriptFailed(message):
        deliveryLogger.error("Copying the last transcript failed: \(message, privacy: .public)")
        return .none
      case let .workspaceOpenFailed(message):
        menuLogger.error("Opening a menu destination failed: \(message, privacy: .public)")
        return .none
      case .modelDownloadConsentRecorded:
        guard state.onboarding.isPresented else {
          return .none
        }
        return .send(.onboarding(.modelDownloadConsented))
      case let .modelDownloadConsentRecordingFailed(message):
        let failure = "Could not record download consent: \(message)"
        state.$health.withLock { $0.engineReadiness = .failed(failure) }
        logEngineReadiness(.failed(failure), state.health.engine)
        return .merge(
          state.onboarding.isPresented
            ? .send(.onboarding(.modelDownloadConsentFailed(failure))) : .none,
          playSound(state.settings.sounds.error),
        )
      case let .agentHistoryReplaced(history):
        state.settingsWindow.history.$log.withLock { $0 = history }
        return .none
      case let .agentScenePresented(scene):
        state = scene.initialState
        return scene.initialAction.map { .send($0) } ?? .none
      case let .engineReadinessUpdated(engine, readiness):
        let wasFailed =
          switch state.health.readinessByEngine[engine] {
          case .failed:
            true
          default:
            false
          }
        state.$health.withLock { $0.readinessByEngine[engine] = readiness }
        logEngineReadiness(readiness, engine)
        // A download that outlived its profile reports to the end, but only the active engine's
        // troubles are anybody's to hear about.
        guard engine == state.health.engine else {
          return .none
        }
        let onboardingFailure: Effect<Action> =
          if case let .failed(message) = readiness, state.onboarding.isPresented {
            .send(.onboarding(.modelSetupFailed(message)))
          } else {
            .none
          }
        let failureSound: Effect<Action> =
          if case .failed = readiness, !wasFailed {
            playSound(state.settings.sounds.error)
          } else {
            .none
          }
        return .merge(onboardingFailure, failureSound)
      case let .recording(.delegate(.recordingStarted(inputDeviceName))):
        return .send(.pill(.recordingStarted(inputDeviceName: inputDeviceName)))
      case let .recording(.delegate(.levelChanged(level))):
        return .send(.pill(.levelUpdated(level)))
      case let .recording(.delegate(.completed(recording))):
        let generation = state.transcriptionGeneration
        let engine = state.health.engine
        state.pendingDictation = PendingDictation(
          generation: generation, recording: recording, createdAt: now,
          engine: asrEngine.identity(engine), original: nil,
          cleanupTarget: state.settings.cleanupTarget,
        )
        let dictionary = state.dictionary.transcriptionDictionary(
          boostsVocabulary: state.settings.activeProfile.boostsVocabulary,
        )
        return .concatenate(
          .send(.pill(.transcribingStarted)),
          .run { send in
            performanceLogger.notice("benchmark transcription-started")
            do {
              try await send(
                .transcriptionCompleted(
                  generation, asrEngine.submit(engine, recording, dictionary),
                ),
              )
            } catch {
              // A refused key is the profile needing setup, not the engine breaking: the repair
              // is a new key, and the pane is where it goes.
              if case ASREngineError.credentialRejected = error {
                await send(.engineReadinessUpdated(engine, .credentialMissing))
              }
              await send(.transcriptionFailed(generation, error.localizedDescription))
            }
          }.cancellable(id: CancelID.transcription, cancelInFlight: true),
        )
      case .recording(.delegate(.discarded)):
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(.cancel(id: CancelID.capture), .send(.pill(.dismiss)))
      case .recording(.delegate(.failed)):
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.cancel)),
          playSound(state.settings.sounds.error),
        )
      case .recording:
        return .none
      case let .transcriptionCompleted(generation, outcome):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        switch outcome {
        case let .transcript(transcript):
          if var pending = state.pendingDictation, pending.generation == generation {
            pending.original = History.Transcription(
              text: transcript, engine: pending.engine, transcribedAt: now,
            )
            state.pendingDictation = pending
          }
          engineLogger.notice("Transcript: \(transcript, privacy: .public)")
          // A cancelled dictation is still the last transcript: Copy Last Transcript is the
          // fastest recovery route for an accidental Escape.
          state.lastTranscript = transcript
          guard state.dictationWasCancelled else {
            return captureContextEffect(generation: generation)
          }
          return .merge(
            .send(.pill(.cancelledSavedToHistory)), finishDictation(&state, delivery: nil),
          )
        case .tooShort:
          // The engine logs the measured duration. Below the floor there was no utterance to
          // report, so this end is always wordless.
          return abandonDictation(&state, retryMessage: nil)
        case .noSpeech:
          engineLogger.notice("Gate rejected recording: no speech")
          return abandonDictation(
            &state,
            retryMessage: Self.noSpeechRetryMessage(
              hotkeys: state.settings.bindings.hotkeys(for: .activate),
            ),
          )
        case .engineEmpty:
          engineLogger.notice("Engine accepted speech but returned an empty transcript")
          return abandonDictation(
            &state, retryMessage: "The speech model returned no text. Try a longer phrase.",
          )
        }
      case let .transcriptionFailed(generation, message):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        // A local engine that fails has broken; a hosted one has failed this request, and the
        // next dictation asks the service again.
        if state.health.engine == .parakeet {
          state.$health.withLock { $0.engineReadiness = .failed(message) }
        }
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        let history = finishDictation(&state, delivery: nil)
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.dismiss)),
          onboardingTryIt(.failed(message), state), playSound(state.settings.sounds.error),
          history,
        )
      case let .contextCaptured(generation, capture, targetApp):
        guard generation == state.transcriptionGeneration, var pending = state.pendingDictation,
              pending.generation == generation, let transcript = pending.original?.text
        else {
          return .none
        }
        pending.capture = capture
        pending.targetApp = targetApp
        state.pendingDictation = pending
        // Whether a pass is worth attempting at all. Whether one actually runs is the pipeline's
        // to decide, and it says so by starting one.
        guard let target = pending.cleanupTarget else {
          return .send(.cleanupResolved(generation, .passedThrough))
        }
        return cleanupEffect(
          generation: generation,
          skipComponents: state.settings
            .bindings
            .hotkeys(for: .activate)
            .first?
            .displayComponents ?? [],
          transcript: transcript,
          conditioning: CleanupConditioning(
            fieldContext: capture.focusedTextContext,
            vocabulary: state.dictionary.vocabulary.map(\.text),
            targetBundleID: targetApp?.bundleID,
          ),
          target: target,
        )
      case let .cleanupStarted(generation, configuration):
        guard var pending = state.pendingDictation, pending.generation == generation else {
          return .none
        }
        pending.cleanup = configuration
        pending.cleanupStartedAt = now
        state.pendingDictation = pending
        return .none
      case let .cleanupResolved(generation, resolution):
        guard generation == state.transcriptionGeneration, var pending = state.pendingDictation,
              pending.generation == generation, let capture = pending.capture,
              let transcript = pending.original?.text
        else {
          return .none
        }
        let record = CleanupRecord(resolution)
        noteKeyVerdict(resolution, state: &state)
        pending.cleanupRecord = record
        state.pendingDictation = pending
        let text = record?.cleanedText ?? transcript
        // Paste-last and Copy Last Transcript recover what was delivered, so the rewrite
        // replaces the transcript they answer with the moment it becomes the delivered text.
        if record?.cleanedText != nil {
          state.lastTranscript = text
        }
        return .merge(
          // Only a wait that started has an end to announce.
          pending.cleanup == nil
            ? .none : .send(.hotkeyListenerEvent(.gestureInput(.cleanupEnded))),
          deliverEffect(
            to: .dictation(generation), text: text, capture: capture, targetApp: pending.targetApp,
          ),
        )
      case let .skippedDeliveryCompleted(generation, result):
        let delivery = result.outcome.delivery(of: result.text)
        deliveryLogger.notice(
          "Skipped cleanup delivered as heard: \(delivery.method.rawValue, privacy: .public)",
        )
        return archiveSkippedDictation(generation, state: &state, delivery: delivery)
      case let .skippedDeliveryFailed(generation, failure):
        deliveryLogger.error(
          "Skipped cleanup failed to deliver: \(failure.message, privacy: .public)",
        )
        return archiveSkippedDictation(generation, state: &state, delivery: nil)
      case let .skippedDictationArchived(entry):
        guard let entry else {
          return .none
        }
        guard state.$history.loadError == nil else {
          return entry.audio == nil ? .none : deleteHistoryAudio([entry.id])
        }
        state.$history.withLock { $0.entries.insert(entry, at: 0) }
        return saveHistory(state.$history)
      case let .deliveryCompleted(generation, result):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        switch result.outcome {
        case let .pasted(restoration):
          logSuccessfulPaste(restoration)
          let onboardingSuccess =
            state.lastTranscript.map { onboardingTryIt(.delivered($0), state) } ?? .none
          let pill = state.pendingDictation?.deliveredNotice ?? .dismiss
          let history = finishDeliveredDictation(&state, result: result)
          return .merge(
            .send(.pill(pill)), onboardingSuccess, playSound(state.settings.sounds.complete),
            history,
          )
        case let .copied(fallback):
          logDeliveryFallback(fallback)
          let history = finishDeliveredDictation(&state, result: result)
          return .merge(
            .send(.pill(.copiedToClipboard)), history,
            onboardingTryIt(.failed(onboardingFailureMessage), state),
            playSound(state.settings.sounds.error),
          )
        case let .noReceiver(reason):
          let history = finishDeliveredDictation(&state, result: result)
          return .merge(
            .send(.pill(noReceiverNotice(settings: state.settings.bindings))), history,
            onboardingTryIt(.failed(noReceiverOnboardingMessage(for: reason)), state),
            playSound(state.settings.sounds.error),
          )
        }
      case let .deliveryFailed(generation, failure):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        deliveryLogger.error("Transcript delivery failed: \(failure.message, privacy: .public)")
        let history = finishDictation(
          &state, targetApp: failure.targetApp, delivery: nil,
        )
        return .merge(
          .send(.pill(.dismiss)), onboardingTryIt(.failed(failure.message), state),
          playSound(state.settings.sounds.error), history,
        )
      case .onboarding(.delegate(.setupModelRequested)):
        return setUpModel(&state)
      case .onboarding(.delegate(.profileSelected)):
        checkCleanupKey(&state)
        return .merge(activateEngine(&state), prepareLocalCleanup(state))
      // A hosted engine reads its key at the end of every prepare, so one already running will
      // find it; otherwise it is asked again now that there is something to find.
      case .onboarding(.delegate(.keysStored)):
        checkCleanupKey(&state)
        guard state.settings.activeProfile.engineCredential != nil,
              !state.health.engineReadiness.isSetupInProgress
        else {
          return .none
        }
        return prepareInstalled(state.health.engine)
      case let .onboarding(.delegate(.permissionsUpdated(permissions))):
        state.$health.withLock { $0.micStatus = permissions.microphoneStatus }
        return reconcileAccessibility(permissions.hasAccessibilityPermission, &state)
      case .onboarding(.delegate(.completed)):
        state.onboardingCompleted = true
        return .none
      case .onboarding,
           .pill:
        return .none
      }
    }
    .onChange(of: \.dictationInFlight) { wasInFlight, state in
      guard wasInFlight, !state.dictationInFlight else {
        return .none
      }
      return startDeferredHistoryMaintenance(&state)
    }
  }

  static func noSpeechRetryMessage(hotkeys: [Hotkey]) -> String {
    guard let hotkey = hotkeys.first else {
      return "No speech was detected. Set an activation shortcut in Settings before trying again."
    }
    return "No speech was detected. Hold \(hotkey.displayName) and try again."
  }

  func warmUpCaptureEffect() -> Effect<Action> {
    .run { _ in _ = await contextCapture.capture(.warmUp) }.cancellable(
      id: CancelID.capture, cancelInFlight: true,
    )
  }

  func playSound(_ name: String?) -> Effect<Action> {
    guard let name else {
      return .none
    }
    return .run { _ in await sounds.play(name) }
  }

  // MARK: Private

  private enum OnboardingTryItResult {
    case delivered(String)
    case failed(String)
  }

  private var onboardingFailureMessage: String {
    "The transcript was copied, but macOS did not allow it to be pasted. Check Accessibility and try again."
  }

  /// Every way a dictation ends without words. Nothing is delivered and nothing reaches History;
  /// a retry message is the only thing that separates them, and an Escape suppresses even that —
  /// the cancel cue has already played and said what happened.
  private func abandonDictation(_ state: inout State, retryMessage: String?) -> Effect<Action> {
    state.pendingDictation = nil
    state.dictationInFlight = false
    guard let retryMessage, !state.dictationWasCancelled else {
      return .merge(.cancel(id: CancelID.capture), .send(.pill(.dismiss)))
    }
    return .merge(
      .cancel(id: CancelID.capture), .send(.pill(.noSpeechDetected)),
      onboardingTryIt(.failed(retryMessage), state), playSound(state.settings.sounds.cancel),
    )
  }

  /// Settings are edited by hand as well as by the pane, so the file has to exist and say what
  /// the defaults are before anyone opens it. Emptiness rather than absence is the test: file
  /// storage creates an empty placeholder to watch and reads it back as nothing stored. A file
  /// that failed to load is left exactly as it is rather than replaced with defaults.
  private func seedSettingsFile(_ settings: Shared<MiniWhisperSettings>) -> Effect<Action> {
    let stored = (try? Data(contentsOf: Channel.settingsFile)) ?? Data()
    guard settings.loadError == nil, stored.isEmpty else {
      return .none
    }
    return .run { _ in
      do { try await settings.save() } catch {
        settingsLogger.error(
          "Settings failed to persist: \(error.localizedDescription, privacy: .public)",
        )
      }
    }
  }

  private func repair(_ degradation: Degradation, state: inout State) -> Effect<Action> {
    switch degradation {
    case .microphoneAccessDenied:
      open(SystemSettingsPane.microphone)
    case .hotkeyTapDead:
      restartHotkeyListener(&state)
    case .accessibilityDenied:
      open(SystemSettingsPane.accessibility)
    case .modelMissing,
         .gateMissing,
         .modelSetupFailed:
      setUpModel(&state)
    case .engineKeyMissing,
         .cleanupKeyMissing:
      .send(.settingsWindow(.selectionChanged(.profiles)))
    }
  }

  /// Follows the active profile to its engine. An engine already heard from keeps what it said;
  /// one never asked is asked now. Nothing is downloaded here: a profile that needs a model asks
  /// for it the ordinary way, through the repair it raises.
  private func activateEngine(_ state: inout State) -> Effect<Action> {
    let engine = state.settings.activeProfile.engine
    guard engine != state.health.engine else {
      return .none
    }
    state.$health.withLock { $0.engine = engine }
    if let readiness = state.health.readinessByEngine[engine], readiness.isSetupInProgress {
      return .none
    }
    return prepareInstalled(engine)
  }

  private func prepareInstalled(_ engine: SpeechEngine) -> Effect<Action> {
    .run { send in
      for await readiness in asrEngine.prepareInstalled(engine) {
        await send(.engineReadinessUpdated(engine, readiness))
      }
    }
  }

  /// S1-mini takes seconds to load, so a profile that cleans with it loads it as soon as it is
  /// chosen rather than on its first dictation.
  private func prepareLocalCleanup(_ state: State) -> Effect<Action> {
    guard state.settings.activeProfile.cleanup == .local, modelLibrary.isInstalled(.s1Mini) else {
      return .none
    }
    return .run { _ in await cleanup.prepareLocal() }
  }

  /// An asset the active engine needs is that engine's repair, so it reports where the engine
  /// does; anything else downloads quietly, and the pane hears it through the library.
  private func downloadAsset(_ asset: ModelAsset, _ state: inout State) -> Effect<Action> {
    if state.health.engine.assets.contains(asset) {
      return setUpModel(&state)
    }
    let preparesCleanup = asset == .s1Mini && state.settings.activeProfile.cleanup == .local
    return .run { send in
      await install(asset, preparingCleanup: preparesCleanup, send: send)
    }
  }

  private func install(
    _ asset: ModelAsset, preparingCleanup: Bool, send: Send<Action>,
  ) async {
    do {
      try await modelLibrary.install(asset)
    } catch {
      await send(.settingsWindow(.models(.assetDownloadFailed(error.localizedDescription))))
      return
    }
    if preparingCleanup {
      await cleanup.prepareLocal()
    }
  }

  /// A factory profile's cleanup key is only ever written by this app, so the moments it can
  /// appear or the profile can change are the moments it is read.
  private func checkCleanupKey(_ state: inout State) {
    let profile = state.settings.activeProfile
    var missing: CredentialProvider?
    if !profile.isCustom, let slot = profile.endpointLeg?.credential {
      do {
        missing = try keychain.read(slot) == nil ? slot.provider : nil
      } catch {
        // An unreadable Keychain is a cleanup failure each dictation reports on its own.
        settingsLogger.error(
          "Cleanup key unreadable: \(error.localizedDescription, privacy: .public)",
        )
      }
    }
    state.$health.withLock { $0.missingCleanupKey = missing }
  }

  /// A refused key reads invalid from the dictation that was refused until one that cleans.
  private func noteKeyVerdict(_ resolution: CleanupResolution, state: inout State) {
    guard case let .attempted(_, attempt) = resolution,
          let slot = state.settings.activeProfile.endpointLeg?.credential
    else {
      return
    }
    switch attempt {
    case .cleaned:
      state.$health.withLock { _ = $0.rejectedKeys.remove(slot) }
    case let .failed(_, _, rejectsKey) where rejectsKey:
      state.$health.withLock { _ = $0.rejectedKeys.insert(slot) }
    case .failed,
         .skipped:
      break
    }
  }

  private func needsCleanupModel(_ state: State) -> Bool {
    state.settings.activeProfile.cleanup == .local && !modelLibrary.isInstalled(.s1Mini)
  }

  /// Whatever holds an asset open lets go of it before its files go. An engine then reads as
  /// missing, and the active profile is Degraded until the ordinary repair downloads it again.
  private func deleteAsset(_ asset: ModelAsset, _: inout State) -> Effect<Action> {
    let engines = SpeechEngine.allCases.filter { $0.assets.contains(asset) }
    return .run { send in
      for engine in engines {
        await asrEngine.unload(engine)
        await send(.engineReadinessUpdated(engine, .modelMissing))
      }
      if asset == .s1Mini {
        await cleanup.unloadLocal()
      }
      do {
        try await modelLibrary.delete(asset)
      } catch {
        await send(.settingsWindow(.models(.assetDeletionFailed(error.localizedDescription))))
      }
    }
  }

  private func setUpModel(_ state: inout State) -> Effect<Action> {
    let recordsConsent = !modelDownloadConsent.isConsented()
    let acknowledgesConsent =
      state.onboarding.isPresented && state.onboarding.isRecordingModelDownloadConsent
    let engine = state.health.engine
    let installsModel = state.health.engineReadiness.isInstallable
    // A profile's cleanup model is part of its setup, so it downloads beside the engine's.
    let installsCleanup = needsCleanupModel(state)
    guard recordsConsent || acknowledgesConsent || installsModel || installsCleanup else {
      return .none
    }
    if installsModel {
      state.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    return .run { send in
      if recordsConsent {
        do {
          try modelDownloadConsent.markConsented()
        } catch {
          await send(.modelDownloadConsentRecordingFailed(error.localizedDescription))
          return
        }
      }
      if acknowledgesConsent {
        await send(.modelDownloadConsentRecorded)
      }
      await withTaskGroup(of: Void.self) { group in
        if installsModel {
          group.addTask {
            for await readiness in asrEngine.installAndPrepare(engine) {
              await send(.engineReadinessUpdated(engine, readiness))
            }
          }
        }
        if installsCleanup {
          group.addTask { await install(.s1Mini, preparingCleanup: true, send: send) }
        }
      }
    }
  }

  private func startupEffect(_ engine: SpeechEngine) -> Effect<Action> {
    .run { send in
      let onboardingCompleted = onboardingCompletion.isCompleted()
      let modelDownloadConsented = modelDownloadConsent.isConsented()
      let hasAccessibilityPermission = accessibilityPermission.hasPermission()
      let microphoneStatus = microphonePermission.status()

      var readinessIterator = asrEngine.prepareInstalled(engine).makeAsyncIterator()
      let engineReadiness = await readinessIterator.next() ?? .modelMissing
      await send(
        .startupResolved(
          StartupFacts(
            onboardingCompleted: onboardingCompleted,
            modelDownloadConsented: modelDownloadConsented,
            permissions: OnboardingPermissionStatuses(
              microphoneStatus: microphoneStatus,
              hasAccessibilityPermission: hasAccessibilityPermission,
            ),
            engineReadiness: engineReadiness,
          ),
        ),
      )
      while let readiness = await readinessIterator.next() {
        await send(.engineReadinessUpdated(engine, readiness))
      }
    }
  }

  private func logSuccessfulPaste(_ restoration: ClipboardRestoration) {
    switch restoration {
    case .restored:
      deliveryLogger.notice("Transcript pasted; prior clipboard restored")
    case .skipped:
      deliveryLogger.notice("Transcript pasted; clipboard changed, so restore was skipped")
    case .failed:
      deliveryLogger.error("Transcript pasted; prior clipboard restore failed")
    }
  }

  private func logDeliveryFallback(_ fallback: DeliveryFallback) {
    switch fallback {
    case .accessibilityPermissionMissing:
      deliveryLogger.error(
        "Accessibility permission missing — grant \(Channel.name) in System Settings > Privacy & Security > Accessibility",
      )
    case .secureInput:
      deliveryLogger.notice("Secure input is active; transcript kept on clipboard")
    case .eventCreationFailed:
      deliveryLogger.error("Paste command creation failed; transcript kept on clipboard")
    }
  }

  private func noReceiverNotice(settings: HotkeyBindingsSettings) -> PillFeature.Action {
    .noReceiver(
      pasteShortcut: settings.hotkeys(for: .pasteLastTranscript).first?.compactDisplayName,
    )
  }

  private func noReceiverOnboardingMessage(for reason: NoReceiverReason) -> String {
    switch reason {
    case .noFocusedElement:
      "No text field was focused. Focus one and try again."
    case .nonTextElement:
      "The focused element was not a text field. Focus one and try again."
    }
  }

  private func logEngineReadiness(_ readiness: EngineReadiness, _ engine: SpeechEngine) {
    let name = engine.shortName
    switch readiness {
    case .modelMissing:
      engineLogger.error("\(name, privacy: .public): pinned models are missing")
    case let .downloading(fraction):
      engineLogger.notice(
        "\(name, privacy: .public): pinned model download \(fraction * 100, format: .fixed(precision: 1))%",
      )
    case .compiling:
      engineLogger.notice("\(name, privacy: .public): compiling pinned Core ML models")
    case .prewarming:
      engineLogger.notice("\(name, privacy: .public): prewarming")
    case .credentialMissing:
      engineLogger.error("\(name, privacy: .public): no usable key")
    case .ready:
      engineLogger.notice("\(name, privacy: .public): ready")
    case let .failed(message):
      engineLogger.error("\(name, privacy: .public): setup failed: \(message, privacy: .public)")
    }
  }

  private func onboardingTryIt(_ result: OnboardingTryItResult, _ state: State) -> Effect<Action> {
    guard state.onboarding.isPresented, state.onboarding.step == .tryIt else {
      return .none
    }
    switch result {
    case let .delivered(transcript):
      return .send(.onboarding(.dictationDelivered(transcript)))
    case let .failed(message):
      return .send(.onboarding(.tryItFailed(message)))
    }
  }

  private func open(_ url: URL) -> Effect<Action> {
    .run { send in
      do { try await workspace.open(url) } catch {
        await send(.workspaceOpenFailed(error.localizedDescription))
      }
    }
  }
}
