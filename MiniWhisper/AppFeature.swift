import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import HotkeyListener
import OSLog

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")
private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")
private let deliveryLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "delivery")
private let soundsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "sounds")
private let menuLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "menu")
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

  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()
    var pill = PillFeature.State()
    var onboarding = OnboardingFeature.State()
    var engineReadiness: EngineReadiness = .modelMissing
    var transcriptionGeneration = 0
    var soundsEnabled = false
    var hotkeyTap = HotkeyTapStatus.idle
    var inputDeviceName: String?
    var launchAtLoginRegistered = false
    var lastTranscript: String?
    var currentFocusedContext: ContextCapture?
    var accessibilityGranted = false
    var onboardingCompleted = false
    var modelDownloadConsented = false

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
        soundsEnabled: soundsEnabled, launchAtLoginRegistered: launchAtLoginRegistered,
      )
    }
  }

  enum Action: Equatable {
    case task
    case startupResolved(StartupFacts)
    case applicationBecameActive
    case accessibilityObserved(Bool)
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
    case contextCaptured(Int, ContextCapture)
    case deliveryCompleted(Int, DeliveryOutcome)
    case deliveryFailed(Int, String)
  }

  @Dependency(\.accessibilityPermission) var accessibilityPermission
  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.audioCapture) var audioCapture
  @Dependency(\.contextCapture) var contextCapture
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
            do { try await send(.soundsEnabledLoaded(sounds.loadIsEnabled())) } catch {
              await send(.soundsSettingsFailed(error.localizedDescription))
            }
          },
        )
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
              .cancel(id: CancelID.delivery), .send(.recording(.startRecording)),
              playSound(.recordStart, enabled: state.soundsEnabled),
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
          return listenForHotkeyEvents()
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
        let enabled = !state.soundsEnabled
        return .run { send in
          do {
            try await sounds.setIsEnabled(enabled)
            await send(.soundsEnabledSaved(enabled))
          } catch { await send(.soundsPersistenceFailed(error.localizedDescription)) }
        }
      case let .soundsEnabledSaved(enabled):
        state.soundsEnabled = enabled
        return .none
      case let .soundsPersistenceFailed(message):
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
            playSound(.error, enabled: state.soundsEnabled)
          } else {
            .none
          }
        return .merge(onboardingUpdate, failureSound)
      case let .soundsEnabledLoaded(enabled):
        state.soundsEnabled = enabled
        return .none
      case let .soundsSettingsFailed(message):
        state.soundsEnabled = false
        soundsLogger.error("Sounds setting failed to load: \(message, privacy: .public)")
        return .none
      case .recording(.micStatusUpdated):
        return .none
      case let .recording(.delegate(.recordingStarted(inputDeviceName))):
        return .send(.pill(.recordingStarted(inputDeviceName: inputDeviceName)))
      case let .recording(.delegate(.levelChanged(level))):
        return .send(.pill(.levelUpdated(level)))
      case let .recording(.delegate(.completed(recording))):
        let generation = state.transcriptionGeneration
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
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.cancel)),
          playSound(.cancel, enabled: state.soundsEnabled),
        )
      case .recording(.delegate(.failed)):
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.cancel)),
          playSound(.error, enabled: state.soundsEnabled),
        )
      case .recording:
        return .none
      case let .transcriptionCompleted(generation, _, .transcript(transcript)):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.lastTranscript = transcript
        engineLogger.notice("Transcript: \(transcript, privacy: .public)")
        return deliveryEffect(generation: generation, transcript: transcript)
      case let .transcriptionCompleted(generation, suppressNotice, .noSpeech):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        engineLogger.notice("Gate rejected recording: no speech")
        return .merge(
          .cancel(id: CancelID.capture),
          .send(.pill(suppressNotice ? .dismiss : .noSpeechDetected)),
          onboardingTryIt(
            .failed("No speech was detected. Hold Right Option and try again."), state,
          ),
          playSound(.cancel, enabled: state.soundsEnabled),
        )
      case let .transcriptionCompleted(generation, _, .engineEmpty):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        engineLogger.notice("Engine accepted speech but returned an empty transcript")
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.noSpeechDetected)),
          onboardingTryIt(
            .failed("The speech model returned no text. Try a longer phrase."), state,
          ),
          playSound(.cancel, enabled: state.soundsEnabled),
        )
      case let .transcriptionFailed(generation, message):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.engineReadiness = .failed(message)
        engineLogger.error("Transcription failed: \(message, privacy: .public)")
        return .merge(
          .cancel(id: CancelID.capture), .send(.pill(.dismiss)),
          onboardingTryIt(.failed(message), state), playSound(.error, enabled: state.soundsEnabled),
        )
      case let .contextCaptured(generation, capture):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.currentFocusedContext = capture
        return .none
      case let .deliveryCompleted(generation, .pasted(restoration)):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
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
        return .merge(
          .send(.pill(pill)), onboardingSuccess, playSound(.commit, enabled: state.soundsEnabled),
        )
      case let .deliveryCompleted(generation, .copied(fallback)):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
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
        return .merge(
          .send(.pill(.copiedToClipboard)),
          onboardingTryIt(
            .failed(
              "The transcript was copied, but macOS did not allow it to be pasted. Check Accessibility and try again.",
            ), state,
          ), playSound(.error, enabled: state.soundsEnabled),
        )
      case let .deliveryFailed(generation, message):
        guard generation == state.transcriptionGeneration else {
          return .none
        }
        state.currentFocusedContext = nil
        deliveryLogger.error("Transcript delivery failed: \(message, privacy: .public)")
        return .merge(
          .send(.pill(.dismiss)), onboardingTryIt(.failed(message), state),
          playSound(.error, enabled: state.soundsEnabled),
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
  }

  // MARK: Private

  private enum CancelID { case transcription, capture, delivery, hotkeyEvents }

  private enum OnboardingTryItResult {
    case delivered(String)
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
      do {
        let outcome = try await delivery.deliver(adjusted)
        await send(.deliveryCompleted(generation, outcome))
      } catch { await send(.deliveryFailed(generation, error.localizedDescription)) }
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
    return listenForHotkeyEvents()
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

  private func listenForHotkeyEvents() -> Effect<Action> {
    .run { send in
      do {
        let events = try await hotkeyListener.events()
        for await event in events {
          await send(.hotkeyListenerEvent(event))
        }
        await send(.hotkeyListenerFinished)
      } catch { await send(.hotkeyListenerFailed(String(describing: error))) }
    }.cancellable(id: CancelID.hotkeyEvents, cancelInFlight: true)
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
