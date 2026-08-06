import AppSettings
import ComposableArchitecture
import HotkeyListener
import OSLog

private let shortcutLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "shortcuts",
)

// MARK: - SettingsPaneFeature

@Reducer struct SettingsPaneFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  enum Row: CaseIterable, Equatable {
    case activate
  }

  /// One target is exactly one control the ring can sit on, so no two of these are ever the same
  /// widget: `set` is the empty state's button, `recording` the chip a new binding is captured in.
  enum Target: Equatable {
    case binding(Int)
    case set
    case recording
  }

  struct Cursor: Equatable {
    var row = Row.activate
    var target = 0
  }

  enum RecordingTarget: Equatable {
    case existing(Int)
    case new
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>) {
      _settings = settings
    }

    // MARK: Internal

    @Shared var settings: MiniWhisperSettings
    var recordingTarget: RecordingTarget?
    var liveChord: HotkeyRecordingChord?
    var validationMessage: String?
    var cursor = Cursor()
    var hoveredRow: Row?

    /// Never empty, so the cursor always has somewhere to be.
    var targets: [Target] {
      let bindings = settings.hotkeys.indices.map(Target.binding)
      if recordingTarget == .new {
        return bindings + [.recording]
      }
      return bindings.isEmpty ? [.set] : bindings
    }

    /// Clamped on read as well as on move: the settings file can be edited underneath a live
    /// window, and a shorter binding list must not index off the end of the pane.
    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }

    func isRecording(_ index: Int) -> Bool {
      recordingTarget == .existing(index)
    }
  }

  enum Action: Equatable {
    case bindingTapped(Int)
    case addTapped
    case removeTapped(Int)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case rowHovered(Row)
    case rowExited(Row)
    case recorderReady
    case recorderEvent(HotkeyRecorderEvent)
    case recorderFailed(String)
    case recorderFinished
    case cancelRecording
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      case recordingStarted
      case recordingStopped
      case bindingsChanged
    }
  }

  enum CancelID { case recorder }

  @Dependency(\.hotkeyListener) var hotkeyListener

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .rowMoved(movement):
        let rows = Row.allCases
        guard let current = rows.firstIndex(of: state.cursor.row) else {
          return .none
        }
        let offset = movement == .next ? 1 : -1
        state.cursor.row = rows[min(max(current + offset, 0), rows.count - 1)]
        moveTarget(&state, to: 0)
        return .none
      case .leftPressed:
        // Ascending to the sidebar is the view's move: focus may only be driven by @FocusState,
        // so the window peeks at the edge itself before sending. Left at the edge is a no-op.
        moveTarget(&state, to: state.cursor.target - 1)
        return .none
      case .rightPressed:
        moveTarget(&state, to: state.cursor.target + 1)
        return .none
      case .pressRequested:
        switch state.cursorTarget {
        case let .binding(index):
          beginRecording(.existing(index), state: &state)
          return .send(.delegate(.recordingStarted))
        case .recording,
             .set:
          beginRecording(.new, state: &state)
          return .send(.delegate(.recordingStarted))
        }
      case let .rowHovered(row):
        state.hoveredRow = row
        return .none
      case let .rowExited(row):
        // A neighbouring row can report its entry before this one reports its exit, so only the
        // row that still owns the pointer is allowed to give it up.
        if state.hoveredRow == row {
          state.hoveredRow = nil
        }
        return .none
      case let .bindingTapped(index):
        guard state.settings.hotkeys.indices.contains(index) else {
          return .none
        }
        beginRecording(.existing(index), state: &state)
        return .send(.delegate(.recordingStarted))
      case .addTapped:
        beginRecording(.new, state: &state)
        return .send(.delegate(.recordingStarted))
      case let .removeTapped(index):
        guard state.settings.hotkeys.indices.contains(index) else {
          return .none
        }
        state.$settings.withLock { settings in
          _ = settings.hotkeys.remove(at: index)
        }
        moveTarget(&state, to: state.cursor.target)
        return .send(.delegate(.bindingsChanged))
      case .recorderReady:
        guard state.recordingTarget != nil else {
          return .none
        }
        return .run { send in
          do {
            for await event in try await hotkeyListener.record() {
              await send(.recorderEvent(event))
            }
            await send(.recorderFinished)
          } catch {
            await send(.recorderFailed(String(describing: error)))
          }
        }.cancellable(id: CancelID.recorder, cancelInFlight: true)
      case let .recorderEvent(.chordChanged(chord)):
        state.liveChord = chord
        state.validationMessage = nil
        return .none
      case let .recorderEvent(.validationFailed(error)):
        state.validationMessage = error.message
        return .none
      case let .recorderEvent(.committed(hotkey)):
        guard let target = state.recordingTarget else {
          return .none
        }
        switch target {
        case let .existing(index):
          guard state.settings.hotkeys.indices.contains(index) else {
            shortcutLogger.error(
              "Dropping a recorded hotkey because binding index \(index) no longer exists",
            )
            clearRecording(&state)
            return .send(.delegate(.recordingStopped))
          }
          guard !state.settings.hotkeys.indices.contains(where: {
            $0 != index && state.settings.hotkeys[$0] == hotkey
          }) else {
            clearRecording(&state)
            return .send(.delegate(.recordingStopped))
          }
          state.$settings.withLock { $0.hotkeys[index] = hotkey }
        case .new:
          guard !state.settings.hotkeys.contains(hotkey) else {
            clearRecording(&state)
            return .send(.delegate(.recordingStopped))
          }
          state.$settings.withLock { $0.hotkeys.append(hotkey) }
        }
        clearRecording(&state)
        return .send(.delegate(.recordingStopped))
      case .recorderEvent(.cancelled),
           .cancelRecording:
        guard state.recordingTarget != nil else {
          return .none
        }
        clearRecording(&state)
        return .merge(
          .cancel(id: CancelID.recorder), .send(.delegate(.recordingStopped)),
        )
      case let .recorderFailed(message):
        guard state.recordingTarget != nil else {
          return .none
        }
        shortcutLogger.error("Hotkey recording failed: \(message, privacy: .public)")
        clearRecording(&state)
        return .send(.delegate(.recordingStopped))
      case .recorderFinished:
        guard state.recordingTarget != nil else {
          return .none
        }
        shortcutLogger.error("Hotkey recorder ended before producing a result")
        clearRecording(&state)
        return .send(.delegate(.recordingStopped))
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private func moveTarget(_ state: inout State, to index: Int) {
    state.cursor.target = min(max(index, 0), state.targets.count - 1)
  }

  private func beginRecording(_ target: RecordingTarget, state: inout State) {
    state.recordingTarget = target
    state.liveChord = nil
    state.validationMessage = nil
  }

  private func clearRecording(_ state: inout State) {
    state.recordingTarget = nil
    state.liveChord = nil
    state.validationMessage = nil
    moveTarget(&state, to: state.cursor.target)
  }
}
