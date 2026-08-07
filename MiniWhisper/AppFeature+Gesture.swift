import AppSettings
import ComposableArchitecture
import HotkeyListener
import OSLog

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
      performanceLogger.notice("benchmark app-activation-received")
      state.transcriptionGeneration += 1
      state.dictationWasCancelled = false
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
              inputDeviceName: audioCapture
                .currentInputDeviceName(state.settings.microphone) ?? "Microphone",
            ),
          ),
        ),
        .merge(
          .cancel(id: CancelID.transcription), .cancel(id: CancelID.capture),
          .cancel(id: CancelID.delivery), .cancel(id: CancelID.historyMaintenance),
          .send(.recording(.startRecording)),
          // The machine emits this exactly once per interaction, so the onset cue needs no
          // suppression flag: one interaction, one sound, at the moment the user acted.
          playSound(state.settings.sounds.activate),
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
      // millisecond. Its result is deliberately discarded — by the time the transcript arrives
      // the user may have typed, moved the caret, or switched windows, so only the read taken at
      // delivery is trustworthy enough to join against.
      return .merge(.send(.recording(.stopAndRetain)), warmUpCaptureEffect())
    case .latchEngaged:
      return .send(.pill(.latchEngaged))
    case .discardRecording:
      // Totally silent: a misfire, an expired lone tap, or an interruption never happened as far
      // as the user, History, and onboarding are concerned.
      state.dictationWasCancelled = false
      state.currentFocusedContext = nil
      state.pendingDictation = nil
      state.dictationInFlight = false
      return .merge(
        .cancel(id: CancelID.transcription), .cancel(id: CancelID.capture),
        .cancel(id: CancelID.delivery), .send(.recording(.cancelRecording)),
        .send(.pill(.dismiss)),
      )
    case .cancelAndArchive:
      // Escape revokes delivery, not the user's words. The retained capture still runs through
      // transcription so a successful result can be recovered from History.
      state.currentFocusedContext = nil
      state.dictationWasCancelled = true
      return .merge(
        .cancel(id: CancelID.delivery), .send(.recording(.stopAndRetain)),
        playSound(state.settings.sounds.cancel),
      )
    }
  }
}
