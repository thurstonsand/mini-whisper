import AudioCapture
import ComposableArchitecture
import Foundation

@DependencyClient struct AudioCaptureClient: Sendable {
  var start: @Sendable () async throws -> AudioCaptureSession
  var stop: @Sendable (UUID) async throws -> CanonicalRecording
  var cancel: @Sendable (UUID) async -> Void
  var writeDebugWAV: @Sendable (CanonicalRecording) async throws -> URL
}

extension AudioCaptureClient: DependencyKey {
  static let liveValue = Self(
    start: { try await AudioCapture.shared.start() },
    stop: { try await AudioCapture.shared.stop(sessionID: $0) },
    cancel: { await AudioCapture.shared.cancel(sessionID: $0) },
    writeDebugWAV: { recording in
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MiniWhisper-\(UUID().uuidString)"
      ).appendingPathExtension("wav")
      try CanonicalWAVWriter.write(recording, to: url)
      return url
    })
}

extension DependencyValues {
  var audioCapture: AudioCaptureClient {
    get { self[AudioCaptureClient.self] }
    set { self[AudioCaptureClient.self] = newValue }
  }
}
