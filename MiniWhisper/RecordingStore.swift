import AudioCapture
import ComposableArchitecture

@Reducer struct RecordingFeature {
  @ObservableState struct State: Equatable {
    var micStatus: MicPermissionStatus = .undetermined
    var status: RecordingStatus = .idle
    var audioLevel: Float = 0
    var currentTranscription: String?
    var lastError: String?
  }

  enum Action: Equatable {
    case task
    case micStatusUpdated(MicPermissionStatus)
    case requestMicAccess
    case startRecording
    case stopRecording
    case reset
  }

  @Dependency(MicrophonePermissionClient.self) var microphonePermission

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .run { send in await send(.micStatusUpdated(await microphonePermission.status())) }

      case .micStatusUpdated(let status):
        state.micStatus = status
        return .none

      case .requestMicAccess:
        return .run { send in await send(.micStatusUpdated(await microphonePermission.request())) }

      case .startRecording:
        guard state.micStatus == .granted else { return .none }
        state.status = .recording
        return .none

      case .stopRecording:
        guard state.status == .recording else { return .none }
        state.status = .processing
        return .none

      case .reset:
        state.status = .idle
        state.audioLevel = 0
        state.currentTranscription = nil
        state.lastError = nil
        return .none
      }
    }
  }
}

enum RecordingStatus: Equatable {
  case idle
  case recording
  case processing
}
