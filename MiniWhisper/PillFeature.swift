import ComposableArchitecture

@Reducer struct PillFeature {
  // MARK: Internal

  @ObservableState struct State: Equatable {
    enum Presentation: Equatable {
      case recording(Recording)
      case transcribing
      /// The blocking cleanup pass. Its own phase and colour, because it is the network leg and
      /// the only one the user can walk away from.
      case polishing(Polishing)
      case notice(Notice)

      // MARK: Internal

      struct Recording: Equatable {
        var inputDeviceName: String
        var level: Float
        var isLive: Bool
      }

      /// The skip chord travels with the phase rather than being read at reveal time, so the chip
      /// shows the binding the dictation actually started under.
      struct Polishing: Equatable {
        var skipComponents: [String]
        var isSkipRevealed = false
      }

      enum Notice: Equatable {
        case noSpeechDetected
        case noTranscriptToPaste
        case copiedToClipboard
        case noReceiver(pasteShortcut: String?)
        case cancelledSavedToHistory
        case fieldContextUnavailable
        case cleanupUnavailable
        case speechModelUnavailable(String)
        case dictionarySaveFailed

        // MARK: Internal

        struct Content: Equatable {
          let text: String
          let phase: String
          let isSubdued: Bool
          let duration: Duration
        }

        var content: Content {
          switch self {
          case .noSpeechDetected:
            Content(
              text: "No speech detected", phase: "No speech detected", isSubdued: true,
              duration: .milliseconds(1500),
            )
          case .noTranscriptToPaste:
            Content(
              text: "No transcript to paste yet", phase: "No transcript to paste yet",
              isSubdued: true, duration: .milliseconds(1500),
            )
          case .copiedToClipboard:
            Content(
              text: "Copied — ⌘V to paste", phase: "Copied", isSubdued: false,
              duration: .seconds(3),
            )
          case let .noReceiver(pasteShortcut):
            Content(
              text: Self.noReceiverText(pasteShortcut: pasteShortcut), phase: "Nowhere to paste",
              isSubdued: false, duration: .seconds(3),
            )
          case .cancelledSavedToHistory:
            Content(
              text: "Cancelled — saved to History", phase: "Cancelled and saved to History",
              isSubdued: false, duration: .seconds(3),
            )
          case .fieldContextUnavailable:
            Content(
              text: "Pasted — could not collect surrounding context",
              phase: "Pasted without field context", isSubdued: true,
              duration: .milliseconds(1500),
            )
          case .cleanupUnavailable:
            Content(
              text: "Cleanup unavailable — pasted as heard", phase: "Pasted without cleanup",
              isSubdued: true, duration: .milliseconds(1500),
            )
          case let .speechModelUnavailable(status):
            Content(
              text: status, phase: status, isSubdued: true, duration: .seconds(3),
            )
          case .dictionarySaveFailed:
            Content(
              text: "Couldn’t save dictionary entry", phase: "Dictionary entry not saved",
              isSubdued: false, duration: .seconds(3),
            )
          }
        }

        // MARK: Private

        private static func noReceiverText(pasteShortcut: String?) -> String {
          pasteShortcut.map { "Nowhere to paste — \($0) to retry" }
            ?? "Nowhere to paste — transcript saved to History"
        }
      }
    }

    var presentation: Presentation?
    var isFadingOut = false
    var bounceCount = 0
    var isLatchBouncePending = false
    var accessibilityLevel = 0
    var noticeGeneration = 0
  }

  enum Action: Equatable {
    case recordingStarting(inputDeviceName: String)
    case recordingStarted(inputDeviceName: String)
    case levelUpdated(Float)
    case latchEngaged
    case transcribingStarted
    case polishingStarted(skipComponents: [String])
    case skipAffordanceRevealed
    case noSpeechDetected
    case noTranscriptToPaste
    case copiedToClipboard
    case noReceiver(pasteShortcut: String?)
    case cancelledSavedToHistory
    case fieldContextUnavailable
    case cleanupUnavailable
    case speechModelUnavailable(String)
    case dictionarySaveFailed
    case dismiss
    case cancel
    case noticeDisplayElapsed(Int)
    case noticeFadeElapsed(Int)
  }

  @Dependency(\.continuousClock) var clock

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .recordingStarting(inputDeviceName):
        state.presentation = .recording(
          State.Presentation.Recording(inputDeviceName: inputDeviceName, level: 0, isLive: false),
        )
        state.isFadingOut = false
        state.accessibilityLevel = 0
        return cancelPresentationTimers()
      case let .recordingStarted(inputDeviceName):
        state.presentation = .recording(
          State.Presentation.Recording(inputDeviceName: inputDeviceName, level: 0, isLive: true),
        )
        state.isFadingOut = false
        state.accessibilityLevel = 0
        if state.isLatchBouncePending {
          state.bounceCount += 1
          state.isLatchBouncePending = false
        }
        return cancelPresentationTimers()
      case let .levelUpdated(level):
        guard case var .recording(recording) = state.presentation, recording.isLive else {
          return .none
        }
        recording.level = level
        state.presentation = .recording(recording)
        let accessibilityLevel = Self.accessibilityPercentageBucket(level)
        if accessibilityLevel != state.accessibilityLevel {
          state.accessibilityLevel = accessibilityLevel
        }
        return .none
      case .latchEngaged:
        if case .recording = state.presentation {
          state.bounceCount += 1
        } else {
          state.isLatchBouncePending = true
        }
        return .none
      case .transcribingStarted:
        state.presentation = .transcribing
        state.isFadingOut = false
        state.isLatchBouncePending = false
        return cancelPresentationTimers()
      case let .polishingStarted(skipComponents):
        state.presentation = .polishing(
          State.Presentation.Polishing(skipComponents: skipComponents),
        )
        state.isFadingOut = false
        state.isLatchBouncePending = false
        return .merge(
          .cancel(id: CancelID.notice),
          // Long enough that an ordinary cleanup finishes unannounced; short enough that a wait
          // the user notices comes with its way out.
          .run { send in
            try await clock.sleep(for: .seconds(3))
            await send(.skipAffordanceRevealed)
          }.cancellable(id: CancelID.polishing, cancelInFlight: true),
        )
      // No generation to check: every presentation change cancels this timer, and a second
      // Polishing cancels the first in flight, so a reveal that arrives is always its own.
      case .skipAffordanceRevealed:
        guard case var .polishing(polishing) = state.presentation,
              !polishing.skipComponents.isEmpty
        else {
          return .none
        }
        polishing.isSkipRevealed = true
        state.presentation = .polishing(polishing)
        return .none
      case .noSpeechDetected:
        return showNotice(.noSpeechDetected, state: &state)
      case .noTranscriptToPaste:
        return showNotice(.noTranscriptToPaste, state: &state)
      case .copiedToClipboard:
        return showNotice(.copiedToClipboard, state: &state)
      case let .noReceiver(pasteShortcut):
        return showNotice(.noReceiver(pasteShortcut: pasteShortcut), state: &state)
      case .cancelledSavedToHistory:
        return showNotice(.cancelledSavedToHistory, state: &state)
      case .fieldContextUnavailable:
        switch state.presentation {
        case .notice(.copiedToClipboard),
             .notice(.noReceiver):
          return .none
        default:
          return showNotice(.fieldContextUnavailable, state: &state)
        }
      case .cleanupUnavailable:
        return showNotice(.cleanupUnavailable, state: &state)
      case let .speechModelUnavailable(status):
        return showNotice(.speechModelUnavailable(status), state: &state)
      case .dictionarySaveFailed:
        return showNotice(.dictionarySaveFailed, state: &state)
      case .dismiss,
           .cancel:
        state.presentation = nil
        state.isFadingOut = false
        state.isLatchBouncePending = false
        return cancelPresentationTimers()
      case let .noticeDisplayElapsed(generation):
        guard generation == state.noticeGeneration, case .notice = state.presentation else {
          return .none
        }
        state.isFadingOut = true
        return .run { send in
          try await clock.sleep(for: .milliseconds(180))
          await send(.noticeFadeElapsed(generation))
        }.cancellable(id: CancelID.notice, cancelInFlight: true)
      case let .noticeFadeElapsed(generation):
        guard generation == state.noticeGeneration, case .notice = state.presentation else {
          return .none
        }
        state.presentation = nil
        state.isFadingOut = false
        return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID {
    case notice
    case polishing
  }

  private static func accessibilityPercentageBucket(_ level: Float) -> Int {
    Int((min(max(level, 0), 1) * 10).rounded()) * 10
  }

  /// Every presentation change owns the whole pill, so it silences both of the pill's timers:
  /// a notice's dismissal and a cleanup's skip reveal.
  private func cancelPresentationTimers() -> Effect<Action> {
    .merge(.cancel(id: CancelID.notice), .cancel(id: CancelID.polishing))
  }

  private func showNotice(
    _ notice: State.Presentation.Notice, state: inout State,
  ) -> Effect<Action> {
    state.noticeGeneration += 1
    let generation = state.noticeGeneration
    state.presentation = .notice(notice)
    state.isFadingOut = false
    state.isLatchBouncePending = false
    let duration = notice.content.duration
    return .merge(
      .cancel(id: CancelID.polishing),
      .run { send in
        try await clock.sleep(for: duration)
        await send(.noticeDisplayElapsed(generation))
      }.cancellable(id: CancelID.notice, cancelInFlight: true),
    )
  }
}
