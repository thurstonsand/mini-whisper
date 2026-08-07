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
    ) {
      _history = history
      _settings = settings
      recording = RecordingFeature.State(settings: settings)
      onboarding = OnboardingFeature.State(settings: settings)
      settingsWindow = SettingsWindowFeature.State(history: history, settings: settings)
    }

    // MARK: Internal

    var recording: RecordingFeature.State
    var pill = PillFeature.State()
    var onboarding: OnboardingFeature.State
    var settingsWindow: SettingsWindowFeature.State
    var engineReadiness: EngineReadiness = .modelMissing
    var transcriptionGeneration = 0
    /// Escape revoked delivery for the dictation now in flight. Only `startRecording` clears it,
    /// so it can never survive into another one, and only a matching generation can read it.
    var dictationWasCancelled = false
    var gestureMachine = HotkeyGestureMachine()
    var gestureDeadlineGeneration = 0
    var hotkeyTap = HotkeyTapStatus.idle
    var inputDeviceName: String?
    var launchAtLoginRegistered = false
    var lastTranscript: String?
    var currentFocusedContext: ContextCapture?
    var pendingDictation: PendingDictation?
    var dictationInFlight = false
    var historyMaintenance = HistoryMaintenanceState.idle
    @Shared var history: HistoryLog
    @Shared var settings: MiniWhisperSettings
    var accessibilityGranted = false
    var onboardingCompleted = false
    var modelDownloadConsented = false

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
        hotkeyTap: hotkeyTap, micStatus: recording.micStatus,
        accessibilityGranted: accessibilityGranted, engineReadiness: engineReadiness,
        inputDeviceName: inputDeviceName, hasLastTranscript: lastTranscript != nil,
        launchAtLoginRegistered: launchAtLoginRegistered,
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
    case accessibilityObserved(Bool)
    case recording(RecordingFeature.Action)
    case pill(PillFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case settingsWindow(SettingsWindowFeature.Action)
    case hotkeyListenerEvent(HotkeyListenerEvent)
    case hotkeyListenerFailed(String)
    case hotkeyListenerFinished
    case gestureDeadlineElapsed(Int)
    case menuWillOpen
    case repairDegradedState
    case copyLastTranscript
    case copyLastTranscriptFailed(String)
    case toggleLaunchAtLogin
    case launchAtLoginUpdated(Bool)
    case launchAtLoginFailed(String)
    case openSettingsFile
    case workspaceOpenFailed(String)
    case engineReadinessUpdated(EngineReadiness)
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
  @Dependency(\.launchAtLogin) var launchAtLogin
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
      case let .settingsWindow(.settingsPane(.delegate(.microphoneChanged(selection)))):
        return .send(.recording(.microphoneChanged(selection)))
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
        state.modelDownloadConsented = facts.modelDownloadConsented
        state.recording.micStatus = facts.permissions.microphoneStatus
        state.engineReadiness = facts.engineReadiness
        logEngineReadiness(facts.engineReadiness)

        var effects = [
          reconcileAccessibility(facts.permissions.hasAccessibilityPermission, &state),
        ]
        if !facts.onboardingCompleted {
          effects.append(
            .send(
              .onboarding(
                .present(
                  OnboardingSnapshot(
                    permissions: facts.permissions, engineReadiness: facts.engineReadiness,
                    hasModelDownloadConsent: facts.modelDownloadConsented, isCompleted: false,
                  ),
                ),
              ),
            ),
          )
        }
        return .merge(effects)
      case .applicationBecameActive:
        // Returning from System Settings is the moment a new grant becomes visible, and macOS
        // never tells the app about it.
        return .send(.accessibilityObserved(accessibilityPermission.hasPermission()))
      case let .accessibilityObserved(granted):
        return reconcileAccessibility(granted, &state)
      case .hotkeyListenerEvent(.accessibilityPermissionMissing):
        gestureLogger.error("Accessibility permission missing — grant in System Settings")
        return reconcileAccessibility(false, &state)
      case .hotkeyListenerEvent(.monitoringStarted):
        state.hotkeyTap = .active
        gestureLogger.notice("Hotkey event tap installed")
        return .none
      case let .hotkeyListenerEvent(.monitoringInterrupted(reason)):
        gestureLogger.error("Hotkey event tap interrupted: \(reason.rawValue, privacy: .public)")
        // Timeout and user-input disables are re-enabled in place; only invalidation kills the tap.
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
        guard state.hotkeyTap != .idle else {
          return .none
        }
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return diagnoseTapLoss(&state)
      case .hotkeyListenerFinished:
        guard state.hotkeyTap != .idle else {
          return .none
        }
        gestureLogger.error("Hotkey event stream ended; the tap is no longer listening")
        return diagnoseTapLoss(&state)
      case .menuWillOpen:
        state.inputDeviceName = audioCapture.currentInputDeviceName(state.settings.microphone)
        state.launchAtLoginRegistered = launchAtLogin.isRegistered()
        return reconcileAccessibility(accessibilityPermission.hasPermission(), &state)
      case .repairDegradedState:
        switch state.menuBar.repair {
        case .openMicrophoneSettings:
          return open(SystemSettingsPane.microphone)
        case .restartHotkeyListening:
          return restartHotkeyListener(&state)
        case .openAccessibilitySettings:
          return open(SystemSettingsPane.accessibility)
        case .installModel,
             .retryModelSetup:
          return .send(.onboarding(.present(onboardingSnapshot(state))))
        case nil:
          return .none
        }
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
      case .toggleLaunchAtLogin:
        let registered = !state.launchAtLoginRegistered
        return .run { send in
          do { try launchAtLogin.setRegistered(registered) } catch {
            await send(.launchAtLoginFailed(error.localizedDescription))
          }
          await send(.launchAtLoginUpdated(launchAtLogin.isRegistered()))
        }
      case let .launchAtLoginUpdated(registered):
        state.launchAtLoginRegistered = registered
        return .none
      case let .launchAtLoginFailed(message):
        menuLogger.error("Launch at login change failed: \(message, privacy: .public)")
        return .none
      case .openSettingsFile:
        return open(Channel.settingsFile)
      case let .workspaceOpenFailed(message):
        menuLogger.error("Opening a menu destination failed: \(message, privacy: .public)")
        return .none
      case let .engineReadinessUpdated(readiness):
        let wasFailed =
          switch state.engineReadiness {
          case .failed:
            true
          default:
            false
          }
        state.engineReadiness = readiness
        logEngineReadiness(readiness)
        let onboardingUpdate =
          state.onboarding.isPresented
            ? Effect<Action>.send(.onboarding(.engineReadinessUpdated(readiness))) : .none
        let failureSound: Effect<Action> =
          if case .failed = readiness, !wasFailed {
            playSound(state.settings.sounds.error)
          } else {
            .none
          }
        return .merge(onboardingUpdate, failureSound)
      case .recording(.micStatusUpdated):
        return .none
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
        state.engineReadiness = .failed(message)
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
      case let .onboarding(.delegate(.engineReadinessUpdated(readiness))):
        return .send(.engineReadinessUpdated(readiness))
      case let .onboarding(.delegate(.permissionsUpdated(permissions))):
        return .merge(
          .send(.recording(.micStatusUpdated(permissions.microphoneStatus))),
          reconcileAccessibility(permissions.hasAccessibilityPermission, &state),
        )
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
    state.accessibilityGranted = granted
    guard granted else {
      state.hotkeyTap = .accessibilityMissing
      return .cancel(id: CancelID.hotkeyEvents)
    }
    guard state.hotkeyTap != .active, state.hotkeyTap != .starting else {
      return .none
    }
    return restartHotkeyListener(&state)
  }

  private func beginHotkeyRecording(
    _ state: inout State, recorderReady: Action,
  ) -> Effect<Action> {
    // Stop the activation tap before the recorder installs its owning tap. This ordering makes
    // recording the activation shortcut race-free: no physical event can reach both consumers.
    state.hotkeyTap = .idle
    return .concatenate(.cancel(id: CancelID.hotkeyEvents), .send(recorderReady))
  }

  /// Every reason for not listening names itself, so the menu bar can tell a missing grant from a
  /// user who has simply unbound every shortcut.
  private func restartHotkeyListener(_ state: inout State) -> Effect<Action> {
    guard state.accessibilityGranted else {
      state.hotkeyTap = .accessibilityMissing
      return .cancel(id: CancelID.hotkeyEvents)
    }
    guard !state.settings.hotkeys.isEmpty else {
      state.hotkeyTap = .idle
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.hotkeyTap = .starting
    return listenForHotkeyEvents(hotkeys: state.settings.hotkeys)
  }

  /// A revoked grant kills the tap exactly the way a genuine failure does. Only a live read tells
  /// them apart, and only one of the two has a repair that can work.
  private func diagnoseTapLoss(_ state: inout State) -> Effect<Action> {
    let granted = accessibilityPermission.hasPermission()
    state.accessibilityGranted = granted
    guard granted else {
      state.hotkeyTap = .accessibilityMissing
      return .cancel(id: CancelID.hotkeyEvents)
    }
    state.hotkeyTap = .dead
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

  /// The menu offers to open `settings.json`, so it has to hold something before the user has
  /// changed anything. Emptiness rather than absence is the test: file storage creates an empty
  /// placeholder to watch, and reads it back as nothing stored. A file that failed to load is
  /// left exactly as it is rather than replaced with defaults.
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

  private func startupEffect() -> Effect<Action> {
    .run { send in
      let onboardingCompleted = onboardingCompletion.isCompleted()
      let modelDownloadConsented = modelDownloadConsent.isConsented()
      let hasAccessibilityPermission = accessibilityPermission.hasPermission()
      async let microphoneStatus = microphonePermission.status()

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

  private func onboardingSnapshot(_ state: State) -> OnboardingSnapshot {
    OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: state.recording.micStatus,
        hasAccessibilityPermission: state.accessibilityGranted,
      ),
      engineReadiness: state.engineReadiness,
      hasModelDownloadConsent: state.modelDownloadConsented || state.onboardingCompleted,
      isCompleted: state.onboardingCompleted,
    )
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
