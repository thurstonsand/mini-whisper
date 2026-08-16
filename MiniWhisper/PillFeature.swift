import ComposableArchitecture

@Reducer struct PillFeature {
  // MARK: Internal

  @ObservableState struct State: Equatable {
    enum Presentation: Equatable {
      case recording(Recording)
      case transcribing
      case notice(Notice)

      // MARK: Internal

      struct Recording: Equatable {
        var inputDeviceName: String
        var level: Float
        var isLive: Bool
      }

      enum Notice: Equatable {
        case noSpeechDetected
        case noTranscriptToPaste
        case copiedToClipboard
        case noReceiver(pasteShortcut: String?)
        case cancelledSavedToHistory
        case fieldContextUnavailable
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
    case noSpeechDetected
    case noTranscriptToPaste
    case copiedToClipboard
    case noReceiver(pasteShortcut: String?)
    case cancelledSavedToHistory
    case fieldContextUnavailable
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
        return .cancel(id: CancelID.notice)
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
        return .cancel(id: CancelID.notice)
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
        return .cancel(id: CancelID.notice)
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
      case let .speechModelUnavailable(status):
        return showNotice(.speechModelUnavailable(status), state: &state)
      case .dictionarySaveFailed:
        return showNotice(.dictionarySaveFailed, state: &state)
      case .dismiss,
           .cancel:
        state.presentation = nil
        state.isFadingOut = false
        state.isLatchBouncePending = false
        return .cancel(id: CancelID.notice)
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

  private enum CancelID { case notice }

  private static func accessibilityPercentageBucket(_ level: Float) -> Int {
    Int((min(max(level, 0), 1) * 10).rounded()) * 10
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
    return .run { send in
      try await clock.sleep(for: duration)
      await send(.noticeDisplayElapsed(generation))
    }.cancellable(id: CancelID.notice, cancelInFlight: true)
  }
}
