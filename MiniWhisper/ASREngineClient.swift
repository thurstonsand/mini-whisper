import ASREngine
import AudioCapture
import ComposableArchitecture

@DependencyClient struct ASREngineClient: Sendable {
  var prepareInstalled: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }
  var installAndPrepare: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }
  var prepareForActivation: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }
  var submit: @Sendable (CanonicalRecording) async throws -> TranscriptionOutcome
}

extension ASREngineClient: DependencyKey {
  static let liveValue = Self(
    prepareInstalled: { LocalASREngine.shared.prepareInstalled() },
    installAndPrepare: { LocalASREngine.shared.installAndPrepare() },
    prepareForActivation: { LocalASREngine.shared.prepareInstalled() },
    submit: { recording in try await LocalASREngine.shared.submit(recording.samples) })
}

extension DependencyValues {
  var asrEngine: ASREngineClient {
    get { self[ASREngineClient.self] }
    set { self[ASREngineClient.self] = newValue }
  }
}
