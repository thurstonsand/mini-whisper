import AudioCapture
import ComposableArchitecture

@Reducer struct RecordingFeature {
  @ObservableState struct State: Equatable { var micStatus: MicPermissionStatus = .undetermined }

  enum Action: Equatable {
    case task
    case micStatusUpdated(MicPermissionStatus)
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
      }
    }
  }
}
