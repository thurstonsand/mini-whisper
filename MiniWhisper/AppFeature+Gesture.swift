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
      if let refusal = refuseDictation(&state) {
        return refusal
      }
      performanceLogger.notice("benchmark app-activation-received")
      // A dictation with words is never dropped by the next one: it steps into the background
      // and finishes there. Only one still transcribing gives way, as the press means try again.
      let replaced = detachPendingDictation(&state)
      state.transcriptionGeneration += 1
      state.dictationWasCancelled = false
      state.pendingDictation = nil
      state.activationTarget = nil
      state.recordingSubmits = false
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
    case .stopAndTranscribe,
         .stopAndSubmit:
      performanceLogger.notice("benchmark recording-release-received")
      state.recordingSubmits = event == .stopAndSubmit
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
    case .detachAndRecord:
      // The polishing dictation keeps its cleanup and delivers itself; the press only decides,
      // once it is over, whether a lone tap means skip. A press that cannot record detaches
      // nothing, and the dictation stays in the pill.
      if let refusal = refuseDictation(&state) {
        return refusal
      }
      let detached = state.pendingDictation?.generation
      _ = detachPendingDictation(&state)
      state.detachedByPress = detached
      return performGesture(.startRecording, state: &state)
    case .skipCleanup:
      let discarded = performGesture(.discardRecording, state: &state)
      guard let generation = state.detachedByPress else {
        return discarded
      }
      state.detachedByPress = nil
      return .merge(discarded, skipCleanup(generation, &state))
    case .submitDetached:
      let discarded = performGesture(.discardRecording, state: &state)
      guard let generation = state.detachedByPress,
            var dictation = state.dictation(generation), !dictation.isDelivering
      else {
        return discarded
      }
      state.detachedByPress = nil
      dictation.submits = true
      state.updateDictation(dictation)
      gestureLogger.notice("Dictation \(generation) will submit once it lands")
      return discarded
    case .cancelAndArchive:
      // Escape during cleanup cancels only where the user still is: the same key is how a
      // terminal agent is interrupted, and the dictation may be bound for one far away.
      if let dictation = state.pendingDictation, dictation.cleanup != nil,
         dictation.readyText == nil
      {
        guard let target = dictation.target else {
          return cancelPolishing(&state)
        }
        return .run { [generation = dictation.generation] send in
          await send(.escapeJudged(generation, atTarget: deliveryTarget.isCurrent(target)))
        }
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

  /// Escape during cleanup: the request is abandoned and nothing is delivered, but the words are
  /// still the user's and still reach History.
  func cancelPolishing(_ state: inout State) -> Effect<Action> {
    guard var dictation = state.pendingDictation, let configuration = dictation.cleanup,
          dictation.readyText == nil
    else {
      return .none
    }
    dictation.cleanupRecord = CleanupRecord(
      .attempted(configuration, .skipped(seconds: dictation.elapsedCleanup(now))),
    )
    state.pendingDictation = dictation
    state.dictationWasCancelled = true
    return .merge(
      .cancel(id: CancelID.cleanup(dictation.generation)),
      .cancel(id: CancelID.delivery(dictation.generation)),
      .send(.hotkeyListenerEvent(.gestureInput(.cleanupEnded))),
      .send(.pill(.cancelledSavedToHistory)), playSound(state.settings.sounds.cancel),
      finishDictation(&state, delivery: nil),
    )
  }

  // MARK: Private

  /// Why a press cannot start a recording, said to the user, with the machine told to stand
  /// down so the rest of the press acts on nothing; nil when it can.
  private func refuseDictation(_ state: inout State) -> Effect<Action>? {
    guard state.canBeginDictation else {
      gestureLogger.notice("Dictation ignored until setup reaches its try-it step")
      return receiveGestureInput(.refused, state: &state)
    }
    // A cached read of state the engine already reported, so refusing costs the hot path a
    // comparison rather than a round trip to an actor that is busy or absent.
    let status: String
    if state.health.engineReadiness != .ready {
      status = state.health.engineStatusText
    } else if let provider = state.health.missingCleanupKey {
      status = "Needs \(provider.keyPhrase)"
    } else {
      return nil
    }
    gestureLogger.notice("Dictation refused: \(status, privacy: .public)")
    return .merge(
      receiveGestureInput(.refused, state: &state), .send(.pill(.speechModelUnavailable(status))),
      playSound(state.settings.sounds.error),
    )
  }

  /// Moves the dictation in the pill into the background if it has words to deliver, and
  /// answers the generation of one that had none and so must be cancelled instead.
  private func detachPendingDictation(_ state: inout State) -> Int? {
    guard let dictation = state.pendingDictation else {
      return nil
    }
    state.pendingDictation = nil
    guard dictation.original != nil else {
      return dictation.generation
    }
    state.backgroundDictations[dictation.generation] = dictation
    gestureLogger.notice("Dictation \(dictation.generation) detached")
    return nil
  }

  /// Lets go of a detached dictation's cleanup: the request is cancelled and the transcript
  /// delivers as heard.
  private func skipCleanup(_ generation: Int, _ state: inout State) -> Effect<Action> {
    guard var dictation = state.dictation(generation), let configuration = dictation.cleanup,
          let transcript = dictation.original?.text, dictation.readyText == nil
    else {
      return .none
    }
    dictation.cleanupRecord = CleanupRecord(
      .attempted(configuration, .skipped(seconds: dictation.elapsedCleanup(now))),
    )
    dictation.readyText = transcript
    state.updateDictation(dictation)
    gestureLogger.notice("Cleanup skipped; delivering the transcript as heard")
    return .merge(.cancel(id: CancelID.cleanup(generation)), deliverReadyDictations(&state))
  }
}
