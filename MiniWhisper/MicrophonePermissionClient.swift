import AudioCapture
import ComposableArchitecture

// MARK: - MicrophonePermissionClient

@DependencyClient struct MicrophonePermissionClient {
  var status: @Sendable () async -> MicPermissionStatus = { .undetermined }
  var requestIfNeeded: @Sendable () async -> MicPermissionStatus = { .undetermined }
}

// MARK: DependencyKey

extension MicrophonePermissionClient: DependencyKey {
  static let liveValue = Self(
    status: { MicPermission.shared.status },
    requestIfNeeded: { await MicPermission.shared.requestIfNeeded() },
  )
}

extension DependencyValues {
  var microphonePermission: MicrophonePermissionClient {
    get { self[MicrophonePermissionClient.self] }
    set { self[MicrophonePermissionClient.self] = newValue }
  }
}
