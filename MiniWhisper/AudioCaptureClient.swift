import AudioCapture
import ComposableArchitecture
import Foundation

// MARK: - AudioCaptureClient

@DependencyClient struct AudioCaptureClient {
  var prepare: @Sendable () async throws -> Void = {}
  var currentInputDeviceName: @Sendable () -> String? = { nil }
  var start: @Sendable () async throws -> AudioCaptureSession
  var stop: @Sendable (UUID) async throws -> CanonicalRecording
  var cancel: @Sendable (UUID) async -> Void
}

// MARK: DependencyKey

extension AudioCaptureClient: DependencyKey {
  static let liveValue = Self(
    prepare: { try await AudioCapture.shared.prepare() },
    currentInputDeviceName: { AudioCapture.defaultInputDeviceName },
    start: { try await AudioCapture.shared.start() },
    stop: { try await AudioCapture.shared.stop(sessionID: $0) },
    cancel: { await AudioCapture.shared.cancel(sessionID: $0) },
  )
}

extension DependencyValues {
  var audioCapture: AudioCaptureClient {
    get { self[AudioCaptureClient.self] }
    set { self[AudioCaptureClient.self] = newValue }
  }
}
