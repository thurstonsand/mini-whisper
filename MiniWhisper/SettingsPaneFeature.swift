import AppSettings
import AudioCapture
import ComposableArchitecture
import HotkeyListener
import OSLog

private let launchAtLoginLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "launch-at-login",
)

// MARK: - SettingsPaneFeature

/// The settings pane's keyboard cursor and pointer highlight. Editing the bindings themselves is
/// `HotkeyBindingsFeature`'s job; this decides only which control the cursor is standing on.
@Reducer struct SettingsPaneFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  enum Row: Hashable {
    case repair(Degradation)
    case shortcut(HotkeyCommand)
    case microphone
    case sound(SoundCue)
    case launchAtLogin
  }

  /// One target is exactly one control the ring can sit on, so no two of these are ever the same
  /// widget: `set` is the empty state's button, `recording` the chip a new binding is captured in.
  enum Target: Equatable {
    case binding(HotkeyCommand, Int)
    case set(HotkeyCommand)
    case recording(HotkeyCommand)
    case microphone
    case soundPreview(SoundCue)
    case soundPicker(SoundCue)
    case repair(Degradation)
    case launchAtLogin
  }

  struct Cursor: Equatable {
    /// Unset until something moves it, which is not the same as standing on the first row: a
    /// repair row appearing above everything should receive the cursor, not be skipped past
    /// because the pane decided where to stand before the failure existed.
    var row: Row?
    var target = 0
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>, health: Shared<AppHealth>) {
      let recordingCommand = Shared<HotkeyCommand?>(value: nil)
      bindingEditors = IdentifiedArray(
        uniqueElements: HotkeyCommand.allCases.map {
          HotkeyBindingsFeature.State(
            settings: settings, command: $0, recordingCommand: recordingCommand,
          )
        },
      )
      _settings = settings
      _health = health
    }

    // MARK: Internal

    @Shared var settings: MiniWhisperSettings
    @Shared var health: AppHealth
    var bindingEditors: IdentifiedArrayOf<HotkeyBindingsFeature.State>
    var cursor = Cursor()
    var inputDevices = AudioInputDeviceSnapshot.empty
    var inputLevel: AudioLevel?
    /// Return on this row has to reach an AppKit pop-up button that only opens when it is clicked,
    /// and a view cannot be told to do something twice by a value that stays the same. The count
    /// is the message; nothing reads it but the button.
    var microphoneActivation = 0
    var soundNames: [String] = []
    /// Same message-by-count trick as `microphoneActivation`, one counter per pop-up button.
    var soundActivations: [SoundCue: Int] = [:]
    var lastPlayedSound: String?
    var launchAtLoginRegistered = false

    var recordingCommand: HotkeyCommand? {
      bindingEditors.first?.recordingCommand
    }

    var rows: [Row] {
      health.degradations.map(Row.repair)
        + HotkeyCommand.allCases.map(Row.shortcut)
        + [.microphone]
        + SoundCue.allCases.map(Row.sound)
        + [.launchAtLogin]
    }

    /// Resolved on read for the same reason `cursorTarget` is: a repair row vanishes the instant
    /// the failure is fixed, and the cursor must never be left standing on a row that is no
    /// longer there.
    var cursorRow: Row {
      guard let row = cursor.row, rows.contains(row) else {
        return rows[0]
      }
      return row
    }

    var microphone: MicrophoneSelection {
      settings.microphone
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

    var sounds: SoundSettings {
      settings.sounds
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
      switch cursorRow {
      case let .repair(degradation):
        [.repair(degradation)]
      case let .shortcut(command):
        bindingTargets(for: bindingEditor(command))
      case .microphone:
        [.microphone]
      case let .sound(cue):
        [.soundPicker(cue), .soundPreview(cue)]
      case .launchAtLogin:
        [.launchAtLogin]
      }
    }

    /// Clamped on read as well as on move: the settings file can be edited underneath a live
    /// window, and a shorter binding list must not index off the end of the pane.
    var cursorTarget: Target {
      targets[min(cursor.target, targets.count - 1)]
    }

    func bindingEditor(_ command: HotkeyCommand) -> HotkeyBindingsFeature.State {
      guard let editor = bindingEditors[id: command] else {
        preconditionFailure("Every hotkey command must have an editor")
      }
      return editor
    }

    // MARK: Private

    private func bindingTargets(for bindings: HotkeyBindingsFeature.State) -> [Target] {
      let command = bindings.command
      let indices = bindings.hotkeys.indices.map { Target.binding(command, $0) }
      if bindings.target == .new {
        return indices + [.recording(command)]
      }
      return indices.isEmpty ? [.set(command)] : indices
    }
  }

  enum Action: Equatable {
    case bindingEditors(IdentifiedActionOf<HotkeyBindingsFeature>)
    case delegate(Delegate)
    case task
    case paneClosed
    case inputDevicesUpdated(AudioInputDeviceSnapshot)
    case inputLevelUpdated(AudioLevel?)
    case microphoneSelected(MicrophoneSelection)
    case soundNamesLoaded([String])
    case soundSelected(SoundCue, String?)
    case soundReplayRequested(SoundCue)
    case soundPlaybackCompleted(String)
    case launchAtLoginToggled(Bool)
    case launchAtLoginUpdated(Bool)
    case launchAtLoginFailed(String)
    case repairTapped(Degradation)
    case rowMoved(CursorMovement)
    case leftPressed
    case rightPressed
    case pressRequested
    case cursorHovered(Row)
  }

  enum Delegate: Equatable {
    case microphoneChanged(MicrophoneSelection)
    case repair(Degradation)
  }

  @Dependency(\.audioInputDevices) var audioInputDevices
  @Dependency(\.audioInputLevels) var audioInputLevels
  @Dependency(\.launchAtLogin) var launchAtLogin
  @Dependency(\.sounds) var sounds

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      // Both listeners run for exactly as long as the pane is on screen, and both cost a live
      // CoreAudio client, so neither may outlive it.
      case .task:
        state.inputLevel = nil
        // The login item can be changed from System Settings, so the pane reads it rather than
        // trusting what it last wrote.
        state.launchAtLoginRegistered = launchAtLogin.isRegistered()
        return .merge(
          .run { send in
            for await snapshot in audioInputDevices.snapshots() {
              await send(.inputDevicesUpdated(snapshot))
            }
          }.cancellable(id: CancelID.deviceObservation, cancelInFlight: true),
          monitorLevels(selection: state.microphone),
          .run { send in
            await send(.soundNamesLoaded(sounds.availableNames()))
          },
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
          state.$settings.withLock {
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
        state.$settings.withLock { $0.microphone = selection }
        return microphoneRouteChanged(&state)
      case let .soundNamesLoaded(names):
        state.soundNames = names
        return .none
      case let .soundSelected(cue, name):
        state.$settings.withLock { $0.sounds[cue] = name }
        return play(name)
      case let .soundReplayRequested(cue):
        return play(state.sounds[cue])
      case let .soundPlaybackCompleted(name):
        state.lastPlayedSound = name
        return .none
      case let .launchAtLoginToggled(registered):
        return .run { send in
          do { try launchAtLogin.setRegistered(registered) } catch {
            await send(.launchAtLoginFailed(error.localizedDescription))
          }
          await send(.launchAtLoginUpdated(launchAtLogin.isRegistered()))
        }
      case let .launchAtLoginUpdated(registered):
        state.launchAtLoginRegistered = registered
        return .none
      case let .launchAtLoginFailed(message):
        launchAtLoginLogger.error(
          "Launch at login change failed: \(message, privacy: .public)",
        )
        return .none
      case let .repairTapped(degradation):
        return .send(.delegate(.repair(degradation)))
      case let .rowMoved(movement):
        let rows = state.rows
        guard let current = rows.firstIndex(of: state.cursorRow) else {
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
        case let .repair(degradation):
          return .send(.repairTapped(degradation))
        case let .binding(command, index):
          return send(.bindingTapped(index), to: command)
        case let .recording(command),
             let .set(command):
          return send(.addTapped, to: command)
        case .microphone:
          state.microphoneActivation += 1
          return .none
        case let .soundPreview(cue):
          return .send(.soundReplayRequested(cue))
        case let .soundPicker(cue):
          state.soundActivations[cue, default: 0] += 1
          return .none
        case .launchAtLogin:
          return .send(.launchAtLoginToggled(!state.launchAtLoginRegistered))
        }
      case let .cursorHovered(row):
        state.cursor.row = row
        moveTarget(&state, to: 0)
        return .none
      case .bindingEditors(
        .element(id: _, action: .delegate(.recordingStopped)),
      ),
      .bindingEditors(.element(id: _, action: .delegate(.bindingsChanged))):
        // The target list shrinks when a recording chip disappears or a binding is removed, so the
        // cursor is re-clamped against the list it now has.
        moveTarget(&state, to: state.cursor.target)
        return .none
      case .bindingEditors,
           .delegate:
        return .none
      }
    }
    .forEach(\.bindingEditors, action: \.bindingEditors) {
      HotkeyBindingsFeature()
    }
  }

  // MARK: Private

  private enum CancelID { case deviceObservation, levelMonitoring }

  private func send(
    _ action: HotkeyBindingsFeature.Action, to command: HotkeyCommand,
  ) -> Effect<Action> {
    .send(.bindingEditors(.element(id: command, action: action)))
  }

  private func play(_ name: String?) -> Effect<Action> {
    guard let name else {
      return .none
    }
    return .run { send in
      await sounds.play(name)
      await send(.soundPlaybackCompleted(name))
    }
  }

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
