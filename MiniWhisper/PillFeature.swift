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
        case copiedToClipboard
        case fieldContextUnavailable
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
    case copiedToClipboard
    case fieldContextUnavailable
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
        return showNotice(.noSpeechDetected, for: .milliseconds(1500), state: &state)
      case .copiedToClipboard:
        return showNotice(.copiedToClipboard, for: .seconds(3), state: &state)
      case .fieldContextUnavailable:
        return showNotice(.fieldContextUnavailable, for: .milliseconds(1500), state: &state)
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
    _ notice: State.Presentation.Notice, for duration: Duration, state: inout State,
  ) -> Effect<Action> {
    state.noticeGeneration += 1
    let generation = state.noticeGeneration
    state.presentation = .notice(notice)
    state.isFadingOut = false
    state.isLatchBouncePending = false
    return .run { send in
      try await clock.sleep(for: duration)
      await send(.noticeDisplayElapsed(generation))
    }.cancellable(id: CancelID.notice, cancelInFlight: true)
  }
}
