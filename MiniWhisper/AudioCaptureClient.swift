import AudioCapture
import ComposableArchitecture
import Foundation

// MARK: - AudioCaptureClient

@DependencyClient struct AudioCaptureClient {
  var prepare: @Sendable (MicrophoneSelection) async throws -> Void = { _ in }
  var currentInputDeviceName: @Sendable (MicrophoneSelection) -> String? = { _ in nil }
  var start: @Sendable (MicrophoneSelection) async throws -> AudioCaptureSession
  var stop: @Sendable (UUID) async throws -> CanonicalRecording
  var cancel: @Sendable (UUID) async -> Void
}

// MARK: DependencyKey

extension AudioCaptureClient: DependencyKey {
  static let liveValue = Self(
    prepare: { try await AudioCapture.shared.prepare(selection: $0) },
    currentInputDeviceName: { AudioCapture.inputDeviceName(for: $0) },
    start: { try await AudioCapture.shared.start(selection: $0) },
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
