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
private let maximumAccidentalLoneTapDuration: TimeInterval = 0.35

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
      settingsWindow = SettingsWindowFeature.State(
        history: history, retention: settings.retention,
      )
    }

    // MARK: Internal

    var recording = RecordingFeature.State()
    var pill = PillFeature.State()
    var onboarding = OnboardingFeature.State()
    var settingsWindow: SettingsWindowFeature.State
    var engineReadiness: EngineReadiness = .modelMissing
    var transcriptionGeneration = 0
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
        soundsEnabled: settings.soundsEnabled,
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
    case menuWillOpen
    case repairDegradedState
    case copyLastTranscript
    case copyLastTranscriptFailed(String)
    case toggleSounds
    case toggleLaunchAtLogin
    case launchAtLoginUpdated(Bool)
    case launchAtLoginFailed(String)
    case openSettingsFile
    case workspaceOpenFailed(String)
    case engineReadinessUpdated(EngineReadiness)
    case transcriptionCompleted(Int, suppressNoSpeechNotice: Bool, TranscriptionOutcome)
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
  }

  @Dependency(\.accessibilityPermission) var accessibilityPermission
  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.contextCapture) var contextCapture
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
      case let .hotkeyListenerEvent(.gesture(event)):
        gestureLogger.notice("\(event.rawValue, privacy: .public)")
        guard state.canBeginDictation else {
          gestureLogger.notice("Dictation ignored until setup reaches its try-it step")
          return .none
        }
        switch event {
        case .startRecording:
          performanceLogger.notice("benchmark app-activation-received")
          state.transcriptionGeneration += 1
          state.currentFocusedContext = nil
          state.pendingDictation = nil
          state.dictationInFlight = true
          if state.historyMaintenance == .running {
            state.historyMaintenance = .waiting
          }
          return .concatenate(
            .send(
              .pill(
                .recordingStarting(
                  inputDeviceName: audioCapture.currentInputDeviceName() ?? "Microphone",
                ),
              ),
            ),
            .merge(
              .cancel(id: CancelID.transcription), .cancel(id: CancelID.capture),
              .cancel(id: CancelID.delivery), .cancel(id: CancelID.historyMaintenance),
              .send(.recording(.startRecording)),
              playSound(.recordStart, enabled: state.settings.soundsEnabled),
              // Waking a Chromium tree costs far more than delivery can spend, so it happens here.
              .run { _ in await contextCapture.prewarmFrontmostApp() },
              .run { send in
                for await readiness in asrEngine.prepareForActivation() {
                  await send(.engineReadinessUpdated(readiness))
                }
              },
            ),
          )
        case .stopAndTranscribe:
          performanceLogger.notice("benchmark recording-release-received")
          // A throwaway read that runs beside transcription purely to warm the target: the first
          // Accessibility call into a process costs 8-30 ms, every later one a fraction of a
          // millisecond. Its result is deliberately discarded — by the time the transcript
          // arrives the user may have typed, moved the caret, or switched windows, so only the
          // read taken at delivery is trustworthy enough to join against.
          return .merge(.send(.recording(.stopAndRetain)), warmUpCaptureEffect())
        case .latchEngaged:
          return .send(.pill(.latchEngaged))
        case .cancel:
          // Nothing from this dictation may reach a field after the user has waved it off.
          state.currentFocusedContext = nil
          state.pendingDictation = nil
          state.dictationInFlight = false
          return .merge(
            .cancel(id: CancelID.transcription), .cancel(id: CancelID.capture),
            .cancel(id: CancelID.delivery), .send(.recording(.cancelRecording)),
          )
        }
      case let .hotkeyListenerFailed(error):
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return diagnoseTapLoss(&state)
      case .hotkeyListenerFinished:
        gestureLogger.error("Hotkey event stream ended; the tap is no longer listening")
        return diagnoseTapLoss(&state)
      case .menuWillOpen:
        state.inputDeviceName = audioCapture.currentInputDeviceName()
        state.launchAtLoginRegistered = launchAtLogin.isRegistered()
        return reconcileAccessibility(accessibilityPermission.hasPermission(), &state)
      case .repairDegradedState:
        switch state.menuBar.repair {
        case .openMicrophoneSettings:
          return open(SystemSettingsPane.microphone)
        case .restartHotkeyListening:
          state.hotkeyTap = .starting
          return listenForHotkeyEvents(hotkey: state.settings.hotkey)
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
      case .toggleSounds:
        state.$settings.withLock { $0.soundsEnabled.toggle() }
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
            playSound(.error, enabled: state.settings.soundsEnabled)
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
        let suppressNoSpeechNotice = recording.durationSeconds <= maximumAccidentalLoneTapDuration
        return .concatenate(
          .send(.pill(.transcribingStarted)),
          .run { send in
            performanceLogger.notice("benchmark transcription-started")
            do {
              try await send(
                .transcriptionCompleted(
                  generation, suppressNoSpeechNotice: suppressNoSpeechNotice,
                  asrEngine.submit(recording),
                ),
              )
            } catch { await send(.transcriptionFailed(generation, error.localizedDescription)) }
          }.cancellable(id: CancelID.transcription, cancelInFlight: true),
        )
      case .recording(.delegate(.discarded)):
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.cancel)),
          playSound(.cancel, enabled: state.settings.soundsEnabled),
        )
      case .recording(.delegate(.failed)):
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.cancel)),
          playSound(.error, enabled: state.settings.soundsEnabled),
        )
      case .recording:
        return .none
      case let .transcriptionCompleted(generation, _, .transcript(transcript)):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.lastTranscript = transcript
        if var pending = state.pendingDictation, pending.generation == generation {
          pending.original = History.Transcription(
            text: transcript, engine: pending.engine, transcribedAt: now,
          )
          state.pendingDictation = pending
        }
        engineLogger.notice("Transcript: \(transcript, privacy: .public)")
        return deliveryEffect(generation: generation, transcript: transcript)
      case let .transcriptionCompleted(generation, suppressNotice, .noSpeech):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        engineLogger.notice("Gate rejected recording: no speech")
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(
          .cancel(id: CancelID.capture),
          .send(.pill(suppressNotice ? .dismiss : .noSpeechDetected)),
          onboardingTryIt(
            .failed("No speech was detected. Hold Right Option and try again."), state,
          ),
          playSound(.cancel, enabled: state.settings.soundsEnabled),
        )
      case let .transcriptionCompleted(generation, _, .engineEmpty):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        engineLogger.notice("Engine accepted speech but returned an empty transcript")
        state.pendingDictation = nil
        state.dictationInFlight = false
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.noSpeechDetected)),
          onboardingTryIt(
            .failed("The speech model returned no text. Try a longer phrase."), state,
          ),
          playSound(.cancel, enabled: state.settings.soundsEnabled),
        )
      case let .transcriptionFailed(generation, message):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.engineReadiness = .failed(message)
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        let history = finishDictation(&state, delivery: nil)
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.dismiss)),
          onboardingTryIt(.failed(message), state), playSound(
            .error,
            enabled: state.settings.soundsEnabled,
          ),
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
            .send(.pill(pill)), onboardingSuccess, playSound(
              .commit,
              enabled: state.settings.soundsEnabled,
            ),
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
            ), playSound(.error, enabled: state.settings.soundsEnabled),
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
          playSound(.error, enabled: state.settings.soundsEnabled), history,
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

  // MARK: Private

  private enum OnboardingTryItResult {
    case delivered(String)
    case failed(String)
  }

  private enum DeliveryAttempt {
    case delivered(DeliveryOutcome)
    case failed(String)
  }

  private func warmUpCaptureEffect() -> Effect<Action> {
    .run { _ in _ = await contextCapture.capture(.warmUp) }.cancellable(
      id: CancelID.capture, cancelInFlight: true,
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
    state.hotkeyTap = .starting
    return listenForHotkeyEvents(hotkey: state.settings.hotkey)
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

  private func listenForHotkeyEvents(hotkey: Hotkey) -> Effect<Action> {
    .run { send in
      do {
        let events = try await hotkeyListener.events(hotkey)
        for await event in events {
          await send(.hotkeyListenerEvent(event))
        }
        await send(.hotkeyListenerFinished)
      } catch { await send(.hotkeyListenerFailed(String(describing: error))) }
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

  private func playSound(_ cue: SoundCue, enabled: Bool) -> Effect<Action> {
    guard enabled else {
      return .none
    }
    return .run { _ in await sounds.play(cue) }
  }
}
