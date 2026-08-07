import AppSettings
import ComposableArchitecture
import HotkeyListener

// MARK: - SettingsPaneFeature

/// The settings pane's keyboard cursor and pointer highlight. Editing the bindings themselves is
/// `HotkeyBindingsFeature`'s job; this decides only which control the cursor is standing on.
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

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>) {
      bindings = HotkeyBindingsFeature.State(settings: settings)
    }

    // MARK: Internal

    var bindings: HotkeyBindingsFeature.State
    var cursor = Cursor()
    var hoveredRow: Row?

    /// Never empty, so the cursor always has somewhere to be.
    var targets: [Target] {
      let indices = bindings.hotkeys.indices.map(Target.binding)
      if bindings.target == .new {
        return indices + [.recording]
      }
      return indices.isEmpty ? [.set] : indices
    }

    /// Clamped on read as well as on move: the settings file can be edited underneath a live
    /// window, and a shorter binding list must not index off the end of the pane.
    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }
  }

  enum Action: Equatable {
    case bindings(HotkeyBindingsFeature.Action)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case rowHovered(Row)
    case rowExited(Row)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.bindings, action: \.bindings) { HotkeyBindingsFeature() }

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
          return .send(.bindings(.bindingTapped(index)))
        case .recording,
             .set:
          return .send(.bindings(.addTapped))
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
      case .bindings(.delegate(.recordingStopped)),
           .bindings(.delegate(.bindingsChanged)):
        // The target list shrinks when a recording chip disappears or a binding is removed, so the
        // cursor is re-clamped against the list it now has.
        moveTarget(&state, to: state.cursor.target)
        return .none
      case .bindings:
        return .none
      }
    }
  }

  // MARK: Private

  private func moveTarget(_ state: inout State, to index: Int) {
    state.cursor.target = min(max(index, 0), state.targets.count - 1)
  }
}
