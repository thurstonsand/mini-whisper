import AudioCapture
import ComposableArchitecture
import HotkeyListener
import OSLog

private let gestureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "gesture")

@Reducer struct AppFeature {
  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()
    var pill = PillFeature.State()

    var menuBar: MenuBarViewState { MenuBarViewState(micStatus: recording.micStatus) }
  }

  enum Action: Equatable {
    case task
    case recording(RecordingFeature.Action)
    case pill(PillFeature.Action)
    case hotkeyListenerEvent(HotkeyListenerEvent)
    case hotkeyListenerFailed(String)
  }

  @Dependency(\.hotkeyListener) var hotkeyListener

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }
    Scope(state: \.pill, action: \.pill) { PillFeature() }

    Reduce { state, action in
      switch action {
      case .task:
        return .merge(
          .send(.recording(.task)),
          .run { send in
            do {
              let events = try await hotkeyListener.events()
              for await event in events { await send(.hotkeyListenerEvent(event)) }
            } catch { await send(.hotkeyListenerFailed(String(describing: error))) }
          })
      case .hotkeyListenerEvent(.inputMonitoringPermissionMissing):
        gestureLogger.error(
          "Input Monitoring permission missing — grant in System Settings and relaunch")
        return .none
      case .hotkeyListenerEvent(.monitoringStarted):
        gestureLogger.notice("Hotkey event tap installed")
        return .none
      case .hotkeyListenerEvent(.monitoringInterrupted(let reason)):
        gestureLogger.error("Hotkey event tap interrupted: \(reason.rawValue, privacy: .public)")
        return .none
      case .hotkeyListenerEvent(.gesture(let event)):
        gestureLogger.notice("\(event.rawValue, privacy: .public)")
        switch event {
        case .startRecording: return .send(.recording(.startRecording))
        case .stopAndTranscribe: return .send(.recording(.stopAndRetain))
        case .latchEngaged: return .send(.pill(.latchEngaged))
        case .cancel: return .send(.recording(.cancelRecording))
        }
      case .hotkeyListenerFailed(let error):
        gestureLogger.error("Hotkey listener failed: \(error, privacy: .public)")
        return .none
      case .recording(.delegate(.recordingStarted(let inputDeviceName))):
        return .send(.pill(.recordingStarted(inputDeviceName: inputDeviceName)))
      case .recording(.delegate(.levelChanged(let level))):
        return .send(.pill(.levelUpdated(level)))
      case .recording(.delegate(.stopped)): return .send(.pill(.dismiss))
      case .recording(.delegate(.discarded)): return .send(.pill(.cancel))
      case .recording: return .none
      case .pill: return .none
      }
    }
  }
}

struct MenuBarViewState: Equatable {
  var iconSymbolName: String
  var statusText: String

  init(micStatus: MicPermissionStatus) {
    switch micStatus {
    case .granted:
      self.iconSymbolName = "mic"
      self.statusText = "Ready"
    case .denied:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone permission required"
    case .restricted:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone access restricted"
    case .undetermined:
      self.iconSymbolName = "mic"
      self.statusText = "Microphone permission not yet requested"
    case .unknown:
      self.iconSymbolName = "mic.slash"
      self.statusText = "Microphone permission unavailable"
    }
  }
}
