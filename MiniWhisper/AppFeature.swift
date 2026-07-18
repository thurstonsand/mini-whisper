import AudioCapture
import ComposableArchitecture

@Reducer struct AppFeature {
  @ObservableState struct State: Equatable {
    var recording = RecordingFeature.State()
    var settings = SettingsFeature.State()

    var menuBar: MenuBarViewState { MenuBarViewState(recording: recording) }
  }

  enum Action: Equatable {
    case task
    case menuBar(MenuBarAction)
    case recording(RecordingFeature.Action)
    case settings(SettingsFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.recording, action: \.recording) { RecordingFeature() }

    Scope(state: \.settings, action: \.settings) { SettingsFeature() }

    Reduce { _, action in
      switch action {
      case .task: return .send(.recording(.task))

      case .menuBar(.requestMicAccessTapped): return .send(.recording(.requestMicAccess))

      case .menuBar(.settingsTapped), .menuBar(.dictationTapped), .recording, .settings:
        return .none
      }
    }
  }
}

enum MenuBarAction: Equatable {
  case dictationTapped
  case requestMicAccessTapped
  case settingsTapped
}

struct MenuBarViewState: Equatable {
  var iconSymbolName: String
  var statusText: String
  var isMicGranted: Bool

  init(recording: RecordingFeature.State) {
    self.iconSymbolName = Self.iconSymbolName(
      status: recording.status, micStatus: recording.micStatus)
    self.isMicGranted = recording.micStatus == .granted

    switch recording.micStatus {
    case .granted:
      switch recording.status {
      case .idle: self.statusText = "✓ Ready"
      case .recording: self.statusText = "🔴 Recording..."
      case .processing: self.statusText = "⏳ Processing..."
      }
    case .denied, .undetermined: self.statusText = "⚠ Needs Mic Access"
    }
  }

  static func iconSymbolName(status: RecordingStatus, micStatus: MicPermissionStatus) -> String {
    switch status {
    case .recording: return "record.circle.fill"
    case .processing: return "ellipsis.circle"
    case .idle:
      if micStatus == .granted {
        return "waveform"
      } else {
        return "waveform.badge.exclamationmark"
      }
    }
  }
}
