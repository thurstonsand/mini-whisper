import ASREngine
import AudioCapture
import ComposableArchitecture

// MARK: - ASREngineClient

@DependencyClient struct ASREngineClient {
  var prepareInstalled: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }

  var installAndPrepare: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }

  var prepareForActivation: @Sendable () -> AsyncStream<EngineReadiness> = {
    AsyncStream { $0.finish() }
  }

  var identity: @Sendable () -> String = { LocalASREngine.identity }
  var submit: @Sendable (CanonicalRecording) async throws -> TranscriptionOutcome
}

// MARK: DependencyKey

extension ASREngineClient: DependencyKey {
  static let liveValue: Self = {
    let engine = LocalASREngine(modelRoot: Channel.engineRoot)
    return Self(
      prepareInstalled: { engine.prepareInstalled() },
      installAndPrepare: { engine.installAndPrepare() },
      prepareForActivation: { engine.prepareInstalled() },
      identity: { LocalASREngine.identity },
      submit: { recording in
        try await engine.submit(recording.samples, sampleRate: CanonicalRecording.sampleRate)
      },
    )
  }()
}

extension DependencyValues {
  var asrEngine: ASREngineClient {
    get { self[ASREngineClient.self] }
    set { self[ASREngineClient.self] = newValue }
  }
}
