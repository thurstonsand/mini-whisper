import AppSettings
import AudioCapture
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
    case microphone
  }

  /// One target is exactly one control the ring can sit on, so no two of these are ever the same
  /// widget: `set` is the empty state's button, `recording` the chip a new binding is captured in.
  enum Target: Equatable {
    case binding(Int)
    case set
    case recording
    case microphone
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
    var inputDevices = AudioInputDeviceSnapshot.empty
    var inputLevel: AudioLevel?
    /// Return on this row has to reach an AppKit pop-up button that only opens when it is clicked,
    /// and a view cannot be told to do something twice by a value that stays the same. The count
    /// is the message; nothing reads it but the button.
    var microphoneActivation = 0

    var microphone: MicrophoneSelection {
      bindings.settings.microphone
    }

    /// Which device the selection actually leads to right now, so the pane can tell a route change
    /// from mere churn in the device list.
    var resolvedMicrophoneUID: String? {
      switch microphone {
      case .systemDefault:
        inputDevices.defaultDevice?.uid
      case let .device(uid, _):
        inputDevices.devices.contains(where: { $0.uid == uid })
          ? uid
          : inputDevices.defaultDevice?.uid
      }
    }

    var unavailableMicrophoneName: String? {
      guard case let .device(uid, lastKnownName) = microphone,
            !inputDevices.devices.contains(where: { $0.uid == uid })
      else {
        return nil
      }
      return lastKnownName
    }

    /// Never empty, so the cursor always has somewhere to be.
    var targets: [Target] {
      switch cursor.row {
      case .activate:
        let indices = bindings.hotkeys.indices.map(Target.binding)
        if bindings.target == .new {
          return indices + [.recording]
        }
        return indices.isEmpty ? [.set] : indices
      case .microphone:
        return [.microphone]
      }
    }

    /// Clamped on read as well as on move: the settings file can be edited underneath a live
    /// window, and a shorter binding list must not index off the end of the pane.
    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }
  }

  enum Action: Equatable {
    case bindings(HotkeyBindingsFeature.Action)
    case delegate(Delegate)
    case task
    case paneClosed
    case inputDevicesUpdated(AudioInputDeviceSnapshot)
    case inputLevelUpdated(AudioLevel?)
    case microphoneSelected(MicrophoneSelection)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case rowHovered(Row)
    case rowExited(Row)
  }

  enum Delegate: Equatable {
    case microphoneChanged(MicrophoneSelection)
  }

  @Dependency(\.audioInputDevices) var audioInputDevices
  @Dependency(\.audioInputLevels) var audioInputLevels

  var body: some ReducerOf<Self> {
    Scope(state: \.bindings, action: \.bindings) { HotkeyBindingsFeature() }

    Reduce { state, action in
      switch action {
      // Both listeners run for exactly as long as the pane is on screen, and both cost a live
      // CoreAudio client, so neither may outlive it.
      case .task:
        state.inputLevel = nil
        return .merge(
          .run { send in
            for await snapshot in audioInputDevices.snapshots() {
              await send(.inputDevicesUpdated(snapshot))
            }
          }.cancellable(id: CancelID.deviceObservation, cancelInFlight: true),
          monitorLevels(selection: state.microphone),
        )
      case .paneClosed:
        state.inputLevel = nil
        return .merge(
          .cancel(id: CancelID.deviceObservation), .cancel(id: CancelID.levelMonitoring),
        )
      case let .inputLevelUpdated(level):
        state.inputLevel = level
        return .none
      case let .inputDevicesUpdated(snapshot):
        let previousResolvedUID = state.resolvedMicrophoneUID
        state.inputDevices = snapshot
        if case let .device(uid, lastKnownName) = state.microphone,
           let device = snapshot.devices.first(where: { $0.uid == uid }),
           device.name != lastKnownName
        {
          state.bindings.$settings.withLock {
            $0.microphone = .device(uid: uid, lastKnownName: device.name)
          }
        }
        guard let previousResolvedUID, let currentResolvedUID = state.resolvedMicrophoneUID,
              previousResolvedUID != currentResolvedUID
        else {
          return .none
        }
        return microphoneRouteChanged(&state)
      case let .microphoneSelected(selection):
        guard selection != state.microphone else {
          return .none
        }
        state.bindings.$settings.withLock { $0.microphone = selection }
        return microphoneRouteChanged(&state)
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
        case .microphone:
          state.microphoneActivation += 1
          return .none
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
      case .bindings,
           .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID { case deviceObservation, levelMonitoring }

  /// The route the selection leads to has moved. The prewarmed engine and the meter both point at
  /// a device, so they are rebound together or not at all.
  private func microphoneRouteChanged(_ state: inout State) -> Effect<Action> {
    state.inputLevel = nil
    return .merge(
      .send(.delegate(.microphoneChanged(state.microphone))),
      monitorLevels(selection: state.microphone),
    )
  }

  private func monitorLevels(selection: MicrophoneSelection) -> Effect<Action> {
    .run { send in
      for await level in audioInputLevels.levels(selection) {
        await send(.inputLevelUpdated(level))
      }
      // A stream that ended on its own means the monitor died and the meter should say so. Being
      // replaced is not that, and must not blank the meter the replacement is already painting.
      guard !Task.isCancelled else {
        return
      }
      await send(.inputLevelUpdated(nil))
    }.cancellable(id: CancelID.levelMonitoring, cancelInFlight: true)
  }

  private func moveTarget(_ state: inout State, to index: Int) {
    state.cursor.target = min(max(index, 0), state.targets.count - 1)
  }
}
