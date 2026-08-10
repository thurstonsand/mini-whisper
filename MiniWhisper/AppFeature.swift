import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
import OSLog

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
      // Nothing has been read from the system yet, so the app starts as broken as it could be.
      health: Shared<AppHealth> = Shared(value: AppHealth()),
    ) {
      _history = history
      _settings = settings
      _health = health
      recording = RecordingFeature.State(settings: settings, health: health)
      onboarding = OnboardingFeature.State(settings: settings, health: health)
      settingsWindow = SettingsWindowFeature.State(
        history: history, settings: settings, health: health,
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
    var currentFocusedContext: ContextCapture?
    var pendingDictation: PendingDictation?
    var dictationInFlight = false
    var historyMaintenance = HistoryMaintenanceState.idle
    @Shared var history: HistoryLog
    @Shared var settings: MiniWhisperSettings
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
        inputDeviceName: inputDeviceName, canCopyLastTranscript: lastTranscript != nil,
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
    case hotkeyListenerEvent(HotkeyListenerEvent)
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
    case engineReadinessUpdated(EngineReadiness)
    /// The agent-driveability seam's scene swap. In Release, `AgentDriveabilityScene` has no
    /// cases, so this action cannot be constructed there.
    case agentScenePresented(AgentDriveabilityScene)
    case transcriptionCompleted(Int, TranscriptionOutcome)
    case transcriptionFailed(Int, String)
    case contextCaptured(Int, ContextCapture)
    case deliveryCompleted(Int, DeliveryResult)
    case deliveryFailed(Int, DeliveryFailure)
  }

  enum CancelID {
    case transcription
    case capture
    case delivery
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
  @Dependency(\.modelDownloadConsent) var modelDownloadConsent
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
      case .settingsWindow(.settingsPane(.task)):
        state.$health.withLock { $0.micStatus = microphonePermission.status() }
        return .none
      case let .settingsWindow(.settingsPane(.delegate(.microphoneChanged(selection)))):
        return .send(.recording(.microphoneChanged(selection)))
      case let .settingsWindow(.settingsPane(.delegate(.repair(repair)))):
        return .send(.repairRequested(repair))
      case .settingsWindow(.settingsPane(.bindings(.delegate(.recordingStarted)))):
        return beginHotkeyRecording(
          &state, recorderReady: .settingsWindow(.settingsPane(.bindings(.recorderReady))),
        )
      case .onboarding(.shortcutBindings(.delegate(.recordingStarted))):
        return beginHotkeyRecording(
          &state, recorderReady: .onboarding(.shortcutBindings(.recorderReady)),
        )
      case .settingsWindow(.settingsPane(.bindings(.delegate(.recordingStopped)))),
           .settingsWindow(.settingsPane(.bindings(.delegate(.bindingsChanged)))),
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
        return .merge(
          .send(.recording(.task)), startupEffect(), .send(.historyMaintenanceRequested),
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
        logEngineReadiness(facts.engineReadiness)

        var effects = [
          reconcileAccessibility(facts.permissions.hasAccessibilityPermission, &state),
        ]
        // Consent is what makes a download durable, so an interrupted one resumes here rather
        // than waiting for a user who has finished onboarding to find the menu bar. A failed
        // setup is left alone: retrying it every launch would be a network loop nobody asked for.
        if facts.modelDownloadConsented, facts.engineReadiness == .modelMissing {
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
        logEngineReadiness(.failed(failure))
        return .merge(
          state.onboarding.isPresented
            ? .send(.onboarding(.modelDownloadConsentFailed(failure))) : .none,
          playSound(state.settings.sounds.error),
        )
      case let .agentScenePresented(scene):
        state = scene.initialState
        return scene.initialAction.map { .send($0) } ?? .none
      case let .engineReadinessUpdated(readiness):
        let wasFailed =
          switch state.health.engineReadiness {
          case .failed:
            true
          default:
            false
          }
        state.$health.withLock { $0.engineReadiness = readiness }
        logEngineReadiness(readiness)
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
        state.pendingDictation = PendingDictation(
          generation: generation, recording: recording, createdAt: now,
          engine: asrEngine.identity(), original: nil,
        )
        return .concatenate(
          .send(.pill(.transcribingStarted)),
          .run { send in
            performanceLogger.notice("benchmark transcription-started")
            do {
              try await send(.transcriptionCompleted(generation, asrEngine.submit(recording)))
            } catch { await send(.transcriptionFailed(generation, error.localizedDescription)) }
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
            return deliveryEffect(generation: generation, transcript: transcript)
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
            &state, retryMessage: Self.noSpeechRetryMessage(hotkeys: state.settings.hotkeys),
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
        state.$health.withLock { $0.engineReadiness = .failed(message) }
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        let history = finishDictation(&state, delivery: nil)
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.dismiss)),
          onboardingTryIt(.failed(message), state), playSound(state.settings.sounds.error),
          history,
        )
      case let .contextCaptured(generation, capture):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.currentFocusedContext = capture
        return .none
      case let .deliveryCompleted(generation, result):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        switch result.outcome {
        case let .pasted(restoration):
          switch restoration {
          case .restored:
            deliveryLogger.notice("Transcript pasted; prior clipboard restored")
          case .skipped:
            deliveryLogger.notice("Transcript pasted; clipboard changed, so restore was skipped")
          case .failed:
            deliveryLogger.error("Transcript pasted; prior clipboard restore failed")
          }
          let onboardingSuccess =
            state.lastTranscript.map { onboardingTryIt(.delivered($0), state) } ?? .none
          let pill: PillFeature.Action =
            if case .unavailable = state.currentFocusedContext {
              .fieldContextUnavailable
            } else {
              .dismiss
            }
          state.currentFocusedContext = nil
          let history = finishDeliveredDictation(
            &state, result: result, method: .pasted, detail: restoration.historyDetail,
          )
          return .merge(
            .send(.pill(pill)), onboardingSuccess, playSound(state.settings.sounds.complete),
            history,
          )
        case let .copied(fallback):
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
          state.currentFocusedContext = nil
          let history = finishDeliveredDictation(
            &state, result: result, method: .copied, detail: fallback.historyDetail,
          )
          return .merge(
            .send(.pill(.copiedToClipboard)), history,
            onboardingTryIt(
              .failed(
                "The transcript was copied, but macOS did not allow it to be pasted. Check Accessibility and try again.",
              ), state,
            ), playSound(state.settings.sounds.error),
          )
        }
      case let .deliveryFailed(generation, failure):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.currentFocusedContext = nil
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

  private enum DeliveryAttempt {
    case delivered(DeliveryOutcome)
    case failed(String)
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

  /// The capture happens here, immediately before the paste, because it is the only moment whose
  /// answer is still true: during transcription the user can type, move the caret, or switch
  /// windows without ever leaving the application. It is a best-effort snapshot of the frontmost
  /// field rather than a guarantee — nothing stops a third application from taking the front
  /// between this read and the synthetic ⌘V — but the window is now microseconds wide instead of
  /// as long as a transcription.
  private func deliveryEffect(generation: Int, transcript: String) -> Effect<Action> {
    .run { send in
      async let targetApplication = workspace.frontmostApplication()
      let capture = await contextCapture.capture(.delivery)
      // A newer dictation has already claimed the field; this paste would land in it.
      guard !Task.isCancelled else {
        return
      }
      await send(.contextCaptured(generation, capture))
      let adjusted = capture.adjusted(transcript)
      guard !Task.isCancelled else {
        return
      }
      let attempt: DeliveryAttempt
      do {
        attempt = try await .delivered(delivery.deliver(adjusted))
      } catch {
        attempt = .failed(error.localizedDescription)
      }
      let targetApp = await targetApplication.map {
        TargetApp(bundleID: $0.bundleID, name: $0.name)
      }
      switch attempt {
      case let .delivered(outcome):
        await send(
          .deliveryCompleted(
            generation, DeliveryResult(text: adjusted, targetApp: targetApp, outcome: outcome),
          ),
        )
      case let .failed(message):
        await send(
          .deliveryFailed(
            generation, DeliveryFailure(text: adjusted, targetApp: targetApp, message: message),
          ),
        )
      }
    }.cancellable(id: CancelID.delivery, cancelInFlight: true)
  }

  /// The single place the Accessibility grant is turned into hotkey-listening state: every
  /// observation of it — startup, onboarding, activation, the menu — lands here so a grant made
  /// after setup starts the listener and a revocation stops it, without a relaunch either way.
  private func reconcileAccessibility(_ granted: Bool, _ state: inout State) -> Effect<Action> {
    state.$health.withLock { $0.accessibilityGranted = granted }
    guard granted else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    guard state.health.hotkeyTap != .active, state.health.hotkeyTap != .starting else {
      return .none
    }
    return restartHotkeyListener(&state)
  }

  private func beginHotkeyRecording(
    _ state: inout State, recorderReady: Action,
  ) -> Effect<Action> {
    // Stop the activation tap before the recorder installs its owning tap. This ordering makes
    // recording the activation shortcut race-free: no physical event can reach both consumers.
    state.$health.withLock { $0.hotkeyTap = .idle }
    return .concatenate(.cancel(id: CancelID.hotkeyEvents), .send(recorderReady))
  }

  /// Not listening is not a failure by itself: a missing grant and an unbound shortcut both end
  /// here, and `health` is what tells the menu bar which of the two to say.
  private func restartHotkeyListener(_ state: inout State) -> Effect<Action> {
    guard state.health.accessibilityGranted, !state.settings.hotkeys.isEmpty else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.$health.withLock { $0.hotkeyTap = .starting }
    return listenForHotkeyEvents(hotkeys: state.settings.hotkeys)
  }

  /// A revoked grant kills the tap exactly the way a genuine failure does. Only a live read tells
  /// them apart, and only one of the two has a repair that can work.
  private func diagnoseTapLoss(_ state: inout State) -> Effect<Action> {
    let granted = accessibilityPermission.hasPermission()
    state.$health.withLock { $0.accessibilityGranted = granted }
    guard granted else {
      state.$health.withLock { $0.hotkeyTap = .idle }
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.$health.withLock { $0.hotkeyTap = .dead }
    return .none
  }

  private func listenForHotkeyEvents(hotkeys: [Hotkey]) -> Effect<Action> {
    .run { send in
      do {
        let events = try await hotkeyListener.events(hotkeys)
        for await event in events {
          await send(.hotkeyListenerEvent(event))
        }
        await send(.hotkeyListenerFinished)
      } catch {
        await send(.hotkeyListenerFailed(String(describing: error)))
      }
    }.cancellable(id: CancelID.hotkeyEvents, cancelInFlight: true)
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
         .modelSetupFailed:
      setUpModel(&state)
    }
  }

  private func setUpModel(_ state: inout State) -> Effect<Action> {
    let recordsConsent = !modelDownloadConsent.isConsented()
    let acknowledgesConsent =
      state.onboarding.isPresented && state.onboarding.isRecordingModelDownloadConsent
    let installsModel = state.health.engineReadiness.isInstallable
    guard recordsConsent || acknowledgesConsent || installsModel else {
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
      guard installsModel else {
        return
      }
      for await readiness in asrEngine.installAndPrepare() {
        await send(.engineReadinessUpdated(readiness))
      }
    }
  }

  private func startupEffect() -> Effect<Action> {
    .run { send in
      let onboardingCompleted = onboardingCompletion.isCompleted()
      let modelDownloadConsented = modelDownloadConsent.isConsented()
      let hasAccessibilityPermission = accessibilityPermission.hasPermission()
      let microphoneStatus = microphonePermission.status()

      var readinessIterator = asrEngine.prepareInstalled().makeAsyncIterator()
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
        await send(.engineReadinessUpdated(readiness))
      }
    }
  }

  private func logEngineReadiness(_ readiness: EngineReadiness) {
    switch readiness {
    case .modelMissing:
      engineLogger.error("Pinned speech models are missing")
    case let .downloading(fraction):
      engineLogger.notice("Pinned model download \(fraction * 100, format: .fixed(precision: 1))%")
    case .compiling:
      engineLogger.notice("Compiling pinned Core ML models")
    case .prewarming:
      engineLogger.notice("Prewarming resident speech engine")
    case .ready:
      engineLogger.notice("Resident speech engine ready")
    case let .failed(message):
      engineLogger.error("Speech engine setup failed: \(message, privacy: .public)")
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
