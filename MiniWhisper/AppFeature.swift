import AudioCapture
import ComposableArchitecture

@Reducer struct AppFeature {
  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()

    var menuBar: MenuBarViewState { MenuBarViewState(micStatus: recording.micStatus) }
  }

  enum Action: Equatable {
    case task
    case recording(RecordingFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }

    Reduce { _, action in
      switch action {
      case .task: return .send(.recording(.task))
      case .recording: return .none
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
    case .undetermined:
      self.iconSymbolName = "mic"
      self.statusText = "Checking microphone permission"
    }
  }
}
