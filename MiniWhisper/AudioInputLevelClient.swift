import AudioCapture
import ComposableArchitecture

// MARK: - AudioInputLevelClient

@DependencyClient struct AudioInputLevelClient {
  var levels: @Sendable (MicrophoneSelection) -> AsyncStream<AudioLevel> = { _ in
    AsyncStream { $0.finish() }
  }
}

// MARK: DependencyKey

extension AudioInputLevelClient: DependencyKey {
  static let testValue = Self(levels: { _ in AsyncStream { $0.finish() } })
  static let liveValue = Self(levels: { AudioInputLevelMonitor.levels(selection: $0) })
}

extension DependencyValues {
  var audioInputLevels: AudioInputLevelClient {
    get { self[AudioInputLevelClient.self] }
    set { self[AudioInputLevelClient.self] = newValue }
  }
}
