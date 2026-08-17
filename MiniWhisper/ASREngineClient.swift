import ASREngine
import AudioCapture
import ComposableArchitecture
import SpeechDictionary

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
  var submit: @Sendable (
    CanonicalRecording, TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome
}

// MARK: - DictionaryContents transcription mapping

extension DictionaryContents {
  /// The one place the stored dictionary becomes an engine request. Boosting is named here rather
  /// than carried alongside as a loose flag, so no call site has to explain a bare `Bool`.
  func transcriptionDictionary(boostsVocabulary: Bool) -> TranscriptionDictionary {
    TranscriptionDictionary(
      vocabulary: vocabulary.map(\.text),
      corrections: corrections.map {
        TranscriptionCorrection(misspelling: $0.misspelling, text: $0.text)
      },
      boostsVocabulary: boostsVocabulary,
    )
  }
}

// MARK: - ASREngineClient + DependencyKey

extension ASREngineClient: DependencyKey {
  static let liveValue: Self = {
    let engine = LocalASREngine(modelRoot: Channel.engineRoot)
    return Self(
      prepareInstalled: { engine.prepareInstalled() },
      installAndPrepare: { engine.installAndPrepare() },
      prepareForActivation: { engine.prepareInstalled() },
      identity: { LocalASREngine.identity },
      submit: { recording, dictionary in
        try await engine.submit(
          recording.samples, sampleRate: CanonicalRecording.sampleRate, dictionary: dictionary,
        )
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
