import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
import OSLog

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")
private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")
private let deliveryLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "delivery")
private let soundsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "sounds")
private let menuLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "menu")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance")
private let maximumAccidentalLoneTapDuration: TimeInterval = 0.35

private func canProbePasteAccess(
  onboardingCompleted: Bool, hasInputMonitoringPermission: Bool
) -> Bool {
  // AXIsProcessTrusted suppresses macOS's Keystroke Receiving dialog when queried before the IOHID
  // request. Completed users and an existing IOHID grant have already crossed that boundary.
  onboardingCompleted || hasInputMonitoringPermission
}

@Reducer struct AppFeature {
  struct StartupFacts: Equatable, Sendable {
    var onboardingCompleted: Bool
    var modelDownloadConsented: Bool
    var permissions: OnboardingPermissionStatuses
    var engineReadiness: EngineReadiness
  }

  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()
    var pill = PillFeature.State()
    var onboarding = OnboardingFeature.State()
    var engineReadiness: EngineReadiness = .modelMissing
    var transcriptionGeneration = 0
    var soundsEnabled = false
    var hotkeyTap = HotkeyTapStatus.starting
    var inputDeviceName: String?
    var launchAtLoginRegistered = false
    var lastTranscript: String?
    var pasteAccessGranted = false
    var onboardingCompleted = false
    var modelDownloadConsented = false

    var canBeginDictation: Bool {
      guard onboarding.isPresented else { return onboardingCompleted }
      return onboarding.step == .tryIt && onboarding.visibleStep == .tryIt
    }

    var menuBar: MenuBarViewState {
      MenuBarViewState(
        hotkeyTap: hotkeyTap, micStatus: recording.micStatus,
        pasteAccessGranted: pasteAccessGranted, engineReadiness: engineReadiness,
        inputDeviceName: inputDeviceName, hasLastTranscript: lastTranscript != nil,
        soundsEnabled: soundsEnabled, launchAtLoginRegistered: launchAtLoginRegistered)
    }
  }

  enum Action: Equatable {
    case task
    case startupResolved(StartupFacts)
    case recording(RecordingFeature.Action)
    case pill(PillFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case hotkeyListenerEvent(HotkeyListenerEvent)
    case hotkeyListenerFailed(String)
    case hotkeyListenerFinished
    case menuWillOpen
    case repairDegradedState
    case copyLastTranscript
    case copyLastTranscriptFailed(String)
    case toggleSounds
    case soundsEnabledSaved(Bool)
    case soundsPersistenceFailed(String)
    case toggleLaunchAtLogin
    case launchAtLoginUpdated(Bool)
    case launchAtLoginFailed(String)
    case openSettingsFile
    case workspaceOpenFailed(String)
    case engineReadinessUpdated(EngineReadiness)
    case soundsEnabledLoaded(Bool)
    case soundsSettingsFailed(String)
    case transcriptionCompleted(Int, suppressNoSpeechNotice: Bool, TranscriptionOutcome)
    case transcriptionFailed(Int, String)
    case deliveryCompleted(Int, DeliveryOutcome)
    case deliveryFailed(Int, String)
  }

  private enum CancelID { case transcription, hotkeyEvents }

  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.delivery) var delivery
  @Dependency(\.hotkeyListener) var hotkeyListener
  @Dependency(\.launchAtLogin) var launchAtLogin
  @Dependency(\.microphonePermission) var microphonePermission
  @Dependency(\.modelDownloadConsent) var modelDownloadConsent
  @Dependency(\.onboardingCompletion) var onboardingCompletion
  @Dependency(\.sounds) var sounds
  @Dependency(\.workspace) var workspace

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }
    Scope(state: \.pill, action: \.pill) { PillFeature() }
    Scope(state: \.onboarding, action: \.onboarding) { OnboardingFeature() }

    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .send(.recording(.task)), startupEffect(),
          .run { send in
            do { await send(.soundsEnabledLoaded(try await sounds.loadIsEnabled())) } catch {
              await send(.soundsSettingsFailed(error.localizedDescription))
            }
          })
      case .startupResolved(let facts):
        state.onboardingCompleted = facts.onboardingCompleted
        state.modelDownloadConsented = facts.modelDownloadConsented
        state.pasteAccessGranted = facts.permissions.hasPasteAccess
        state.recording.micStatus = facts.permissions.microphoneStatus
        state.engineReadiness = facts.engineReadiness
        state.hotkeyTap =
          facts.permissions.hasInputMonitoringPermission ? .starting : .inputMonitoringMissing
        logEngineReadiness(facts.engineReadiness)

        var effects: [Effect<Action>] = []
        if facts.permissions.hasInputMonitoringPermission {
          effects.append(listenForHotkeyEvents())
        }
        if !facts.onboardingCompleted {
          effects.append(
            .send(
              .onboarding(
                .present(
                  OnboardingSnapshot(
                    permissions: facts.permissions, engineReadiness: facts.engineReadiness,
                    hasModelDownloadConsent: facts.modelDownloadConsented, isCompleted: false)))))
        }
        return .merge(effects)
      case .hotkeyListenerEvent(.inputMonitoringPermissionMissing):
        state.hotkeyTap = .inputMonitoringMissing
        gestureLogger.error("Input Monitoring permission missing — grant in System Settings")
        return .none
      case .hotkeyListenerEvent(.monitoringStarted):
        state.hotkeyTap = .active
        gestureLogger.notice("Hotkey event tap installed")
        return .none
      case .hotkeyListenerEvent(.monitoringInterrupted(let reason)):
        // Timeout and user-input disables are re-enabled in place; only invalidation kills the tap.
        if reason == .invalidated { state.hotkeyTap = .dead }
        gestureLogger.error("Hotkey event tap interrupted: \(reason.rawValue, privacy: .public)")
        return .none
      case .hotkeyListenerEvent(.gesture(let event)):
        gestureLogger.notice("\(event.rawValue, privacy: .public)")
        guard state.canBeginDictation else {
          gestureLogger.notice("Dictation ignored until setup reaches its try-it step")
          return .none
        }
        switch event {
        case .startRecording:
          performanceLogger.notice("benchmark app-activation-received")
          state.transcriptionGeneration += 1
          return .concatenate(
            .send(
              .pill(
                .recordingStarting(
                  inputDeviceName: audioCapture.currentInputDeviceName() ?? "Microphone"))),
            .merge(
              .cancel(id: CancelID.transcription), .send(.recording(.startRecording)),
              playSound(.recordStart, enabled: state.soundsEnabled),
              .run { send in
                for await readiness in asrEngine.prepareForActivation() {
                  await send(.engineReadinessUpdated(readiness))
                }
              }))
        case .stopAndTranscribe:
          performanceLogger.notice("benchmark recording-release-received")
          return .send(.recording(.stopAndRetain))
        case .latchEngaged: return .send(.pill(.latchEngaged))
        case .cancel: return .send(.recording(.cancelRecording))
        }
      case .hotkeyListenerFailed(let error):
        state.hotkeyTap = .dead
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return .none
      case .hotkeyListenerFinished:
        if state.hotkeyTap != .inputMonitoringMissing {
          state.hotkeyTap = .dead
          gestureLogger.error("Hotkey event stream ended; the tap is no longer listening")
        }
        return .none
      case .menuWillOpen:
        state.inputDeviceName = audioCapture.currentInputDeviceName()
        state.launchAtLoginRegistered = launchAtLogin.isRegistered()
        let hasInputMonitoringPermission = hotkeyListener.hasInputMonitoringPermission()
        if canProbePasteAccess(
          onboardingCompleted: state.onboardingCompleted,
          hasInputMonitoringPermission: hasInputMonitoringPermission)
        {
          state.pasteAccessGranted = delivery.hasPasteAccess()
        }
        return .none
      case .repairDegradedState:
        switch state.menuBar.repair {
        case .openInputMonitoringSettings: return open(SystemSettingsPane.inputMonitoring)
        case .openMicrophoneSettings: return open(SystemSettingsPane.microphone)
        case .restartHotkeyListening:
          state.hotkeyTap = .starting
          return listenForHotkeyEvents()
        case .openAccessibilitySettings: return open(SystemSettingsPane.accessibility)
        case .installModel, .retryModelSetup:
          return .send(.onboarding(.present(onboardingSnapshot(state))))
        case nil: return .none
        }
      case .copyLastTranscript:
        guard let transcript = state.lastTranscript else { return .none }
        return .run { send in
          do { try await delivery.copy(transcript) } catch {
            await send(.copyLastTranscriptFailed(error.localizedDescription))
          }
        }
      case .copyLastTranscriptFailed(let message):
        deliveryLogger.error("Copying the last transcript failed: \(message, privacy: .public)")
        return .none
      case .toggleSounds:
        let enabled = !state.soundsEnabled
        return .run { send in
          do {
            try await sounds.setIsEnabled(enabled)
            await send(.soundsEnabledSaved(enabled))
          } catch { await send(.soundsPersistenceFailed(error.localizedDescription)) }
        }
      case .soundsEnabledSaved(let enabled):
        state.soundsEnabled = enabled
        return .none
      case .soundsPersistenceFailed(let message):
        soundsLogger.error("Sounds setting failed to save: \(message, privacy: .public)")
        return .none
      case .toggleLaunchAtLogin:
        let registered = !state.launchAtLoginRegistered
        return .run { send in
          do { try launchAtLogin.setRegistered(registered) } catch {
            await send(.launchAtLoginFailed(error.localizedDescription))
          }
          await send(.launchAtLoginUpdated(launchAtLogin.isRegistered()))
        }
      case .launchAtLoginUpdated(let registered):
        state.launchAtLoginRegistered = registered
        return .none
      case .launchAtLoginFailed(let message):
        menuLogger.error("Launch at login change failed: \(message, privacy: .public)")
        return .none
      case .openSettingsFile: return open(SettingsStore.defaultFileURL)
      case .workspaceOpenFailed(let message):
        menuLogger.error("Opening a menu destination failed: \(message, privacy: .public)")
        return .none
      case .engineReadinessUpdated(let readiness):
        let wasFailed =
          switch state.engineReadiness {
          case .failed: true
          default: false
          }
        state.engineReadiness = readiness
        logEngineReadiness(readiness)
        let onboardingUpdate =
          state.onboarding.isPresented
          ? Effect<Action>.send(.onboarding(.engineReadinessUpdated(readiness))) : .none
        let failureSound: Effect<Action>
        if case .failed = readiness, !wasFailed {
          failureSound = playSound(.error, enabled: state.soundsEnabled)
        } else {
          failureSound = .none
        }
        return .merge(onboardingUpdate, failureSound)
      case .soundsEnabledLoaded(let enabled):
        state.soundsEnabled = enabled
        return .none
      case .soundsSettingsFailed(let message):
        state.soundsEnabled = false
        soundsLogger.error("Sounds setting failed to load: \(message, privacy: .public)")
        return .none
      case .recording(.micStatusUpdated): return .none
      case .recording(.delegate(.recordingStarted(let inputDeviceName))):
        return .send(.pill(.recordingStarted(inputDeviceName: inputDeviceName)))
      case .recording(.delegate(.levelChanged(let level))):
        return .send(.pill(.levelUpdated(level)))
      case .recording(.delegate(.completed(let recording))):
        let generation = state.transcriptionGeneration
        let suppressNoSpeechNotice = recording.durationSeconds <= maximumAccidentalLoneTapDuration
        return .concatenate(
          .send(.pill(.transcribingStarted)),
          .run { send in
            performanceLogger.notice("benchmark transcription-started")
            do {
              await send(
                .transcriptionCompleted(
                  generation, suppressNoSpeechNotice: suppressNoSpeechNotice,
                  try await asrEngine.submit(recording)))
            } catch { await send(.transcriptionFailed(generation, error.localizedDescription)) }
          }.cancellable(id: CancelID.transcription, cancelInFlight: true))
      case .recording(.delegate(.discarded)):
        return .merge(.send(.pill(.cancel)), playSound(.cancel, enabled: state.soundsEnabled))
      case .recording(.delegate(.failed)):
        return .merge(.send(.pill(.cancel)), playSound(.error, enabled: state.soundsEnabled))
      case .recording: return .none
      case .transcriptionCompleted(let generation, _, .transcript(let transcript)):
        guard generation == state.transcriptionGeneration else { return .none }
        state.lastTranscript = transcript
        engineLogger.notice("Transcript: \(transcript, privacy: .public)")
        return .run { send in
          do {
            await send(.deliveryCompleted(generation, try await delivery.deliver(transcript)))
          } catch { await send(.deliveryFailed(generation, error.localizedDescription)) }
        }
      case .transcriptionCompleted(let generation, let suppressNotice, .noSpeech):
        guard generation == state.transcriptionGeneration else { return .none }
        engineLogger.notice("Gate rejected recording: no speech")
        return .merge(
          .send(.pill(suppressNotice ? .dismiss : .noSpeechDetected)),
          onboardingTryIt(
            .failed("No speech was detected. Hold Right Option and try again."), state),
          playSound(.cancel, enabled: state.soundsEnabled))
      case .transcriptionCompleted(let generation, _, .engineEmpty):
        guard generation == state.transcriptionGeneration else { return .none }
        engineLogger.notice("Engine accepted speech but returned an empty transcript")
        return .merge(
          .send(.pill(.noSpeechDetected)),
          onboardingTryIt(
            .failed("The speech model returned no text. Try a longer phrase."), state),
          playSound(.cancel, enabled: state.soundsEnabled))
      case .transcriptionFailed(let generation, let message):
        guard generation == state.transcriptionGeneration else { return .none }
        state.engineReadiness = .failed(message)
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        return .merge(
          .send(.pill(.dismiss)), onboardingTryIt(.failed(message), state),
          playSound(.error, enabled: state.soundsEnabled))
      case .deliveryCompleted(let generation, .pasted(let restoration)):
        guard generation == state.transcriptionGeneration else { return .none }
        switch restoration {
        case .restored: deliveryLogger.notice("Transcript pasted; prior clipboard restored")
        case .skipped:
          deliveryLogger.notice("Transcript pasted; clipboard changed, so restore was skipped")
        case .failed: deliveryLogger.error("Transcript pasted; prior clipboard restore failed")
        }
        let onboardingSuccess =
          state.lastTranscript.map { onboardingTryIt(.delivered($0), state) } ?? .none
        return .merge(
          .send(.pill(.dismiss)), onboardingSuccess,
          playSound(.commit, enabled: state.soundsEnabled))
      case .deliveryCompleted(let generation, .copied(let fallback)):
        guard generation == state.transcriptionGeneration else { return .none }
        switch fallback {
        case .accessibilityPermissionMissing:
          deliveryLogger.error(
            "Accessibility permission missing — grant MiniWhisper in System Settings > Privacy & Security > Accessibility"
          )
        case .secureInput:
          deliveryLogger.notice("Secure input is active; transcript kept on clipboard")
        case .eventCreationFailed:
          deliveryLogger.error("Paste command creation failed; transcript kept on clipboard")
        }
        return .merge(
          .send(.pill(.copiedToClipboard)),
          onboardingTryIt(
            .failed(
              "The transcript was copied, but macOS did not allow it to be pasted. Check Accessibility and try again."
            ), state), playSound(.error, enabled: state.soundsEnabled))
      case .deliveryFailed(let generation, let message):
        guard generation == state.transcriptionGeneration else { return .none }
        deliveryLogger.error("Transcript delivery failed: \(message, privacy: .public)")
        return .merge(
          .send(.pill(.dismiss)), onboardingTryIt(.failed(message), state),
          playSound(.error, enabled: state.soundsEnabled))
      case .onboarding(.delegate(.engineReadinessUpdated(let readiness))):
        return .send(.engineReadinessUpdated(readiness))
      case .onboarding(.delegate(.permissionsUpdated(let permissions))):
        state.pasteAccessGranted = permissions.hasPasteAccess
        var effects = [
          Effect<Action>.send(.recording(.micStatusUpdated(permissions.microphoneStatus)))
        ]
        if permissions.hasInputMonitoringPermission, state.hotkeyTap != .active,
          state.hotkeyTap != .starting
        {
          state.hotkeyTap = .starting
          effects.append(listenForHotkeyEvents())
        }
        return .merge(effects)
      case .onboarding(.delegate(.completed)):
        state.onboardingCompleted = true
        return .none
      case .onboarding, .pill: return .none
      }
    }
  }

  private func listenForHotkeyEvents() -> Effect<Action> {
    .run { send in
      do {
        let events = try await hotkeyListener.events()
        for await event in events { await send(.hotkeyListenerEvent(event)) }
        await send(.hotkeyListenerFinished)
      } catch { await send(.hotkeyListenerFailed(String(describing: error))) }
    }.cancellable(id: CancelID.hotkeyEvents, cancelInFlight: true)
  }

  private func startupEffect() -> Effect<Action> {
    .run { send in
      let onboardingCompleted = onboardingCompletion.isCompleted()
      let modelDownloadConsented = modelDownloadConsent.isConsented()
      let hasInputMonitoringPermission = hotkeyListener.hasInputMonitoringPermission()
      async let microphoneStatus = microphonePermission.status()
      let hasPasteAccess =
        canProbePasteAccess(
          onboardingCompleted: onboardingCompleted,
          hasInputMonitoringPermission: hasInputMonitoringPermission)
        ? delivery.hasPasteAccess() : false

      var readinessIterator = asrEngine.prepareInstalled().makeAsyncIterator()
      let engineReadiness = await readinessIterator.next() ?? .modelMissing
      await send(
        .startupResolved(
          StartupFacts(
            onboardingCompleted: onboardingCompleted,
            modelDownloadConsented: modelDownloadConsented,
            permissions: OnboardingPermissionStatuses(
              hasInputMonitoringPermission: hasInputMonitoringPermission,
              microphoneStatus: await microphoneStatus, hasPasteAccess: hasPasteAccess),
            engineReadiness: engineReadiness)))
      while let readiness = await readinessIterator.next() {
        await send(.engineReadinessUpdated(readiness))
      }
    }
  }

  private func onboardingSnapshot(_ state: State) -> OnboardingSnapshot {
    OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: hotkeyListener.hasInputMonitoringPermission(),
        microphoneStatus: state.recording.micStatus, hasPasteAccess: state.pasteAccessGranted),
      engineReadiness: state.engineReadiness,
      hasModelDownloadConsent: state.modelDownloadConsented || state.onboardingCompleted,
      isCompleted: state.onboardingCompleted)
  }

  private func logEngineReadiness(_ readiness: EngineReadiness) {
    switch readiness {
    case .modelMissing: engineLogger.error("Pinned speech models are missing")
    case .downloading(let fraction):
      engineLogger.notice("Pinned model download \(fraction * 100, format: .fixed(precision: 1))%")
    case .compiling: engineLogger.notice("Compiling pinned Core ML models")
    case .prewarming: engineLogger.notice("Prewarming resident speech engine")
    case .ready: engineLogger.notice("Resident speech engine ready")
    case .failed(let message):
      engineLogger.error("Speech engine setup failed: \(message, privacy: .public)")
    }
  }

  private enum OnboardingTryItResult {
    case delivered(String)
    case failed(String)
  }

  private func onboardingTryIt(_ result: OnboardingTryItResult, _ state: State) -> Effect<Action> {
    guard state.onboarding.isPresented, state.onboarding.step == .tryIt else { return .none }
    switch result {
    case .delivered(let transcript): return .send(.onboarding(.dictationDelivered(transcript)))
    case .failed(let message): return .send(.onboarding(.tryItFailed(message)))
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
    guard enabled else { return .none }
    return .run { _ in await sounds.play(cue) }
  }
}
