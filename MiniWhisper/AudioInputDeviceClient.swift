import AudioCapture
import ComposableArchitecture

// MARK: - AudioInputDeviceClient

@DependencyClient struct AudioInputDeviceClient {
  var snapshots: @Sendable () -> AsyncStream<AudioInputDeviceSnapshot> = {
    AsyncStream { $0.finish() }
  }
}

// MARK: DependencyKey

extension AudioInputDeviceClient: DependencyKey {
  static let liveValue = Self(snapshots: { AudioInputDeviceMonitor.snapshots() })
}

extension DependencyValues {
  var audioInputDevices: AudioInputDeviceClient {
    get { self[AudioInputDeviceClient.self] }
    set { self[AudioInputDeviceClient.self] = newValue }
  }
}
