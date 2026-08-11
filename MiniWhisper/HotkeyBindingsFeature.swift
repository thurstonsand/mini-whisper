import AppSettings
import ComposableArchitecture
import HotkeyListener
import OSLog

private let shortcutLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "shortcuts",
)

// MARK: - HotkeyBindingsFeature

/// The activation bindings and the act of recording into them. Onboarding drives one hero keycap
/// and the settings pane drives a row of chips, but both edit the same list through this one
/// reducer, so "which binding a recording replaces" is decided in exactly one place.
@Reducer struct HotkeyBindingsFeature {
  // MARK: Internal

  enum Target: Equatable {
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
    var target: Target?
    var liveChord: HotkeyRecordingChord?
    var validationMessage: String?

    var hotkeys: [Hotkey] {
      settings.bindings.activate
    }

    var isRecording: Bool {
      target != nil
    }

    func isRecording(_ index: Int) -> Bool {
      target == .existing(index)
    }
  }

  enum Action: Equatable {
    case bindingTapped(Int)
    case primaryBindingTapped
    case addTapped
    case removeTapped(Int)
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
      case let .bindingTapped(index):
        guard state.settings.bindings.activate.indices.contains(index) else {
          return .none
        }
        return beginRecording(.existing(index), state: &state)
      case .primaryBindingTapped:
        // Onboarding's keycap is both the trigger and the recording surface, so pressing it again
        // mid-capture must not restart the recorder underneath the user.
        guard !state.isRecording else {
          return .none
        }
        return beginRecording(
          state.settings.bindings.activate.isEmpty ? .new : .existing(0),
          state: &state,
        )
      case .addTapped:
        return beginRecording(.new, state: &state)
      case let .removeTapped(index):
        guard state.settings.bindings.activate.indices.contains(index) else {
          return .none
        }
        state.$settings.withLock { settings in
          _ = settings.bindings.activate.remove(at: index)
        }
        return .send(.delegate(.bindingsChanged))
      case .recorderReady:
        guard state.isRecording else {
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
        guard let target = state.target else {
          return .none
        }
        commit(hotkey, to: target, state: &state)
        clearRecording(&state)
        return .send(.delegate(.recordingStopped))
      case .recorderEvent(.cancelled),
           .cancelRecording:
        guard state.isRecording else {
          return .none
        }
        clearRecording(&state)
        return .merge(.cancel(id: CancelID.recorder), .send(.delegate(.recordingStopped)))
      case let .recorderFailed(message):
        guard state.isRecording else {
          return .none
        }
        shortcutLogger.error("Hotkey recording failed: \(message, privacy: .public)")
        clearRecording(&state)
        return .send(.delegate(.recordingStopped))
      case .recorderFinished:
        guard state.isRecording else {
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

  /// A hotkey appears in the list at most once, which is the whole of the commit policy: a chord
  /// already bound anywhere — including to the binding being re-recorded — is silently dropped.
  private func commit(_ hotkey: Hotkey, to target: Target, state: inout State) {
    switch target {
    case let .existing(index):
      guard state.settings.bindings.activate.indices.contains(index) else {
        shortcutLogger.error(
          "Dropping a recorded hotkey because binding index \(index) no longer exists",
        )
        return
      }
      guard !state.settings.bindings.activate.contains(hotkey) else {
        return
      }
      state.$settings.withLock { $0.bindings.activate[index] = hotkey }
    case .new:
      guard !state.settings.bindings.activate.contains(hotkey) else {
        return
      }
      state.$settings.withLock { $0.bindings.activate.append(hotkey) }
    }
  }

  private func beginRecording(_ target: Target, state: inout State) -> Effect<Action> {
    state.target = target
    state.liveChord = nil
    state.validationMessage = nil
    return .send(.delegate(.recordingStarted))
  }

  private func clearRecording(_ state: inout State) {
    state.target = nil
    state.liveChord = nil
    state.validationMessage = nil
  }
}
