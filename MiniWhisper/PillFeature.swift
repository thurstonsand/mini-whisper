import ComposableArchitecture

@Reducer struct PillFeature {
  @ObservableState struct State: Equatable {
    enum Presentation: Equatable {
      struct Recording: Equatable {
        var inputDeviceName: String
        var level: Float
      }

      enum Notice: Equatable {
        case noSpeechDetected
        case copiedToClipboard
      }

      case recording(Recording)
      case transcribing
      case notice(Notice)
    }

    var presentation: Presentation?
    var isFadingOut = false
    var bounceCount = 0
    var isLatchBouncePending = false
    var noticeGeneration = 0
  }

  enum Action: Equatable {
    case recordingStarted(inputDeviceName: String)
    case levelUpdated(Float)
    case latchEngaged
    case transcribingStarted
    case noSpeechDetected
    case copiedToClipboard
    case dismiss
    case cancel
    case noticeDisplayElapsed(Int)
    case noticeFadeElapsed(Int)
  }

  private enum CancelID { case notice }

  @Dependency(\.continuousClock) var clock

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .recordingStarted(let inputDeviceName):
        state.presentation = .recording(
          State.Presentation.Recording(inputDeviceName: inputDeviceName, level: 0))
        state.isFadingOut = false
        if state.isLatchBouncePending {
          state.bounceCount += 1
          state.isLatchBouncePending = false
        }
        return .cancel(id: CancelID.notice)
      case .levelUpdated(let level):
        guard case .recording(var recording) = state.presentation else { return .none }
        recording.level = level
        state.presentation = .recording(recording)
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
        return showNotice(.noSpeechDetected, for: .milliseconds(1_500), state: &state)
      case .copiedToClipboard:
        return showNotice(.copiedToClipboard, for: .seconds(3), state: &state)
      case .dismiss, .cancel:
        state.presentation = nil
        state.isFadingOut = false
        state.isLatchBouncePending = false
        return .cancel(id: CancelID.notice)
      case .noticeDisplayElapsed(let generation):
        guard generation == state.noticeGeneration, case .notice = state.presentation else {
          return .none
        }
        state.isFadingOut = true
        return .run { send in
          try await clock.sleep(for: .milliseconds(180))
          await send(.noticeFadeElapsed(generation))
        }.cancellable(id: CancelID.notice, cancelInFlight: true)
      case .noticeFadeElapsed(let generation):
        guard generation == state.noticeGeneration, case .notice = state.presentation else {
          return .none
        }
        state.presentation = nil
        state.isFadingOut = false
        return .none
      }
    }
  }

  private func showNotice(
    _ notice: State.Presentation.Notice, for duration: Duration, state: inout State
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
