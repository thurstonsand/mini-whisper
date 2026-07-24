import AudioCapture
import ComposableArchitecture

struct MicrophonePermissionClient: Sendable {
  var status: @Sendable () async -> MicPermissionStatus
}

extension MicrophonePermissionClient: DependencyKey {
  static let liveValue = Self(status: { MicPermission.shared.status })
}

extension DependencyValues {
  var microphonePermission: MicrophonePermissionClient {
    get { self[MicrophonePermissionClient.self] }
    set { self[MicrophonePermissionClient.self] = newValue }
  }
}
