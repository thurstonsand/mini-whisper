import AppSettings
import ASREngine
import ComposableArchitecture
import History
import HotkeyListener
import OSLog
import TranscriptCleanup

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - The gesture harness

/// `HotkeyGestureMachine` is a pure value with no clock, so someone has to hold one for it. That
/// is this file's whole job: feed the machine every witnessed input, schedule the one deadline it
/// cannot schedule itself, and turn the events it emits into dictation commands.
extension AppFeature {
  /// The single path into the machine. Physical inputs arrive from the event tap; `deadlineElapsed`
  /// arrives from the timer armed below, and nowhere else.
  func receiveGestureInput(_ input: GestureInput, state: inout State) -> Effect<Action> {
    let wasWaiting = state.gestureMachine.awaitsDeadline
    let event = state.gestureMachine.receive(input)
    var effects: [Effect<Action>] = []

    switch (wasWaiting, state.gestureMachine.awaitsDeadline) {
    case (false, true):
      // The generation token is what makes a deadline that lost its race harmless: it arrives,
      // finds a newer number, and is dropped before the machine ever sees it.
      state.gestureDeadlineGeneration += 1
      let generation = state.gestureDeadlineGeneration
      let window = state.gestureMachine.timing.doubleTapWindow
      effects.append(
        .run { send in
          try await clock.sleep(for: window)
          await send(.gestureDeadlineElapsed(generation))
        }.cancellable(id: CancelID.gestureDeadline, cancelInFlight: true),
      )
    case (true, false):
      effects.append(.cancel(id: CancelID.gestureDeadline))
    case (false, false),
         (true, true):
      break
    }
    if let event {
      effects.append(.send(.hotkeyListenerEvent(.gesture(event))))
    }
    return .merge(effects)
  }

  /// One event, one command to the rest of the app. The machine has already decided what the
  /// gesture meant; nothing here re-reads timing or phase.
  func performGesture(_ event: GestureEvent, state: inout State) -> Effect<Action> {
    gestureLogger.notice("\(event.rawValue, privacy: .public)")
    switch event {
    case .startRecording:
      guard state.canBeginDictation else {
        gestureLogger.notice("Dictation ignored until setup reaches its try-it step")
        return .none
      }
      // A cached read of state the engine already reported, so refusing costs the hot path a
      // comparison rather than a round trip to an actor that is busy or absent.
      let readiness = state.health.engineReadiness
      guard readiness == .ready else {
        let status = state.health.engineStatusText
        gestureLogger.notice("Dictation refused: \(status, privacy: .public)")
        return .merge(
          .send(.pill(.speechModelUnavailable(status))),
          playSound(state.settings.sounds.error),
        )
      }
      if let provider = state.health.missingCleanupKey {
        let status = "Needs \(provider.keyPhrase)"
        gestureLogger.notice("Dictation refused: \(status, privacy: .public)")
        return .merge(
          .send(.pill(.speechModelUnavailable(status))),
          playSound(state.settings.sounds.error),
        )
      }
      performanceLogger.notice("benchmark app-activation-received")
      // Only the dictation in the pill gives way; one already in the background keeps its legs.
      let replaced = state.pendingDictation?.generation
      state.transcriptionGeneration += 1
      state.dictationWasCancelled = false
      state.pendingDictation = nil
      state.activationTarget = nil
      state.dictationInFlight = true
      if state.historyMaintenance == .running {
        state.historyMaintenance = .waiting
      }
      return .concatenate(
        .send(
          .pill(
            .recordingStarting(
              inputDeviceName: audioCapture
                .currentInputDeviceName(state.settings.microphone) ?? "Microphone",
            ),
          ),
        ),
        .merge(
          .cancel(id: CancelID.transcription),
          replaced.map { .cancel(id: CancelID.cleanup($0)) } ?? .none,
          replaced.map { .cancel(id: CancelID.delivery($0)) } ?? .none,
          .cancel(id: CancelID.recoveryDelivery), .cancel(id: CancelID.historyMaintenance),
          .send(.recording(.startRecording)),
          captureTargetEffect(generation: state.transcriptionGeneration),
          // The machine emits this exactly once per interaction, so the onset cue needs no
          // suppression flag: one interaction, one sound, at the moment the user acted.
          playSound(state.settings.sounds.activate),
          // Waking a Chromium tree costs far more than delivery can spend, so it happens here.
          .run { _ in await contextCapture.prewarmFrontmostApp() },
          .run { [engine = state.health.engine] send in
            for await readiness in asrEngine.prepareForActivation(engine) {
              await send(.engineReadinessUpdated(engine, readiness))
            }
          },
        ),
      )
    case .stopAndTranscribe:
      performanceLogger.notice("benchmark recording-release-received")
      return .send(.recording(.stopAndRetain))
    case .latchEngaged:
      return .send(.pill(.latchEngaged))
    case .discardRecording:
      // Totally silent: a misfire, an expired lone tap, or an interruption never happened as far
      // as the user, History, and onboarding are concerned.
      let generation = state.transcriptionGeneration
      state.dictationWasCancelled = false
      state.pendingDictation = nil
      state.dictationInFlight = false
      return .merge(
        .cancel(id: CancelID.transcription), .cancel(id: CancelID.cleanup(generation)),
        .cancel(id: CancelID.delivery(generation)),
        .send(.recording(.cancelRecording)),
        .send(.pill(.dismiss)),
      )
    case .skipCleanupAndRecord:
      // Two meanings, one press, in this order: the transcript waiting on the endpoint is let go
      // as heard, and only then does the next dictation take the field.
      let skipped = skipPendingCleanup(&state)
      return .merge(skipped, performGesture(.startRecording, state: &state))
    case .cancelAndArchive:
      // Escape during cleanup: the request is abandoned and nothing is delivered, but the words
      // are still the user's and still reach History.
      if var dictation = state.pendingDictation, let configuration = dictation.cleanup {
        dictation.cleanupRecord = CleanupRecord(
          .attempted(configuration, .skipped(seconds: dictation.elapsedCleanup(now))),
        )
        state.pendingDictation = dictation
        state.dictationWasCancelled = true
        return .merge(
          .cancel(id: CancelID.cleanup(dictation.generation)),
          .cancel(id: CancelID.delivery(dictation.generation)),
          .send(.pill(.cancelledSavedToHistory)), playSound(state.settings.sounds.cancel),
          finishDictation(&state, delivery: nil),
        )
      }
      // Escape revokes delivery, not the user's words. The retained capture still runs through
      // transcription so a successful result can be recovered from History.
      state.dictationWasCancelled = true
      return .merge(
        .cancel(id: CancelID.delivery(state.transcriptionGeneration)),
        .send(.recording(.stopAndRetain)),
        playSound(state.settings.sounds.cancel),
      )
    }
  }

  // MARK: Private

  /// Lets go of the cleanup a press just resolved: the request is cancelled, and the dictation
  /// steps aside into `backgroundDictations` — still owed a paste and an entry — so the next one
  /// can take the pill and the generation while that tail finishes on its own.
  private func skipPendingCleanup(_ state: inout State) -> Effect<Action> {
    guard var dictation = state.pendingDictation, let configuration = dictation.cleanup,
          let transcript = dictation.original?.text, dictation.readyText == nil
    else {
      return .none
    }
    dictation.cleanupRecord = CleanupRecord(
      .attempted(configuration, .skipped(seconds: dictation.elapsedCleanup(now))),
    )
    dictation.readyText = transcript
    state.pendingDictation = nil
    state.backgroundDictations[dictation.generation] = dictation
    gestureLogger.notice("Cleanup skipped; delivering the transcript as heard")
    return .merge(
      .cancel(id: CancelID.cleanup(dictation.generation)), deliverReadyDictations(&state),
    )
  }
}
