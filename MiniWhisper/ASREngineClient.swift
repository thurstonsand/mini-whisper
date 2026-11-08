import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import ModelLibrary
import SpeechDictionary

// MARK: - ASREngineClient

/// Every engine a profile can name, addressed by which one. Each keeps its own readiness, so a
/// profile switch never has to tear one down for another to come up.
@DependencyClient struct ASREngineClient {
  var prepareInstalled: @Sendable (SpeechEngine) -> AsyncStream<EngineReadiness> = { _ in
    AsyncStream { $0.finish() }
  }

  var installAndPrepare: @Sendable (SpeechEngine) -> AsyncStream<EngineReadiness> = { _ in
    AsyncStream { $0.finish() }
  }

  var prepareForActivation: @Sendable (SpeechEngine) -> AsyncStream<EngineReadiness> = { _ in
    AsyncStream { $0.finish() }
  }

  /// The engine lets go of what it loaded, so the library can delete the files under it.
  var unload: @Sendable (SpeechEngine) async -> Void
  var identity: @Sendable (SpeechEngine) -> String = { $0.identity }
  var submit: @Sendable (
    SpeechEngine, CanonicalRecording, TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome
  /// Proves a key the engine has not been given yet, so nothing stores a key that cannot hear.
  var verifyHosted: @Sendable (HostedASREngine.Configuration, String) async throws -> Void
}

extension ProfileSettings {
  var scribeConfiguration: HostedASREngine.Configuration {
    let factory = HostedASREngine.Configuration.scribe
    return .init(endpoint: scribeOverride?.endpoint ?? factory.endpoint,
                 model: scribeOverride?.model ?? factory.model)
  }
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

extension SpeechEngine {
  /// What History records as having heard a dictation.
  var identity: String {
    switch self {
    case .parakeet:
      Channel.speechModel.identity
    case .scribe:
      HostedASREngine.identity
    }
  }
}

// MARK: - ASREngineClient + DependencyKey

extension ASREngineClient: DependencyKey {
  static let liveValue: Self = {
    @Shared(.settingsFile) var settings = MiniWhisperSettings.defaults
    let local = LocalASREngine(library: .live, speechModel: Channel.speechModel)
    // Only Most accurate hears through Scribe, so its slot is the only one the engine reads.
    let keychain = KeychainClient.liveValue
    let scribeKey = CredentialSlot(profile: .accurate, provider: .elevenlabs)
    let hosted = HostedASREngine(library: .live, apiKey: { try keychain.read(scribeKey) })
    return Self(
      prepareInstalled: { engine in
        switch engine {
        case .parakeet:
          local.prepareInstalled()
        case .scribe:
          hosted.prepareInstalled()
        }
      },
      installAndPrepare: { engine in
        switch engine {
        case .parakeet:
          local.installAndPrepare()
        case .scribe:
          hosted.installAndPrepare()
        }
      },
      prepareForActivation: { engine in
        switch engine {
        case .parakeet:
          local.prepareInstalled()
        case .scribe:
          hosted.prepareInstalled()
        }
      },
      unload: { engine in
        switch engine {
        case .parakeet:
          await local.unload()
        case .scribe:
          await hosted.unload()
        }
      },
      identity: { [$settings] engine in
        let configuration = $settings.wrappedValue.profiles.scribeConfiguration
        return engine == .scribe && configuration != .scribe
          ? "\(configuration.endpoint.host() ?? "hosted")/\(configuration.model)"
          : engine.identity
      },
      submit: { [$settings] engine, recording, dictionary in
        switch engine {
        case .parakeet:
          try await local.submit(
            recording.samples, sampleRate: CanonicalRecording.sampleRate, dictionary: dictionary,
          )
        case .scribe:
          try await hosted.submit(
            recording.samples, sampleRate: CanonicalRecording.sampleRate, dictionary: dictionary,
            configuration: $settings.wrappedValue.profiles.scribeConfiguration,
          )
        }
      },
      verifyHosted: { configuration, key in
        try await HostedASREngine.verify(apiKey: key, configuration: configuration)
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
