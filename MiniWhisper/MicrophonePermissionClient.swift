import AudioCapture
import ComposableArchitecture

// MARK: - MicrophonePermissionClient

@DependencyClient struct MicrophonePermissionClient {
  /// Synchronous, because `AVCaptureDevice.authorizationStatus` is. The menu is rebuilt in the
  /// same breath as the read that refreshes it, so a status arriving one hop later arrives after
  /// the menu the user is already looking at.
  var status: @Sendable () -> MicPermissionStatus = { .undetermined }
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
