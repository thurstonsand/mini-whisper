import FluidAudio
import ModelLibrary

// MARK: - SpeechModel

/// One pinned Core ML transcription model FluidAudio can run. The app ships exactly one, as a
/// library asset; the rest exist so `asr-replay` can install and measure a candidate beside the
/// assets without an engine code change.
public struct SpeechModel: Hashable, Sendable {
  // MARK: Public

  public static let parakeetV2 = SpeechModel(
    id: "parakeet-v2", repository: .parakeetTDT, family: .v2, asset: .parakeet,
  )

  /// Evaluated and rejected; kept as the worked example of a v3-family community model. Its
  /// repository publishes the joint as `JointDecision.mlmodelc`, the name FluidAudio reserves
  /// for v2, so it is installed under the `JointDecisionv3.mlmodelc` every v3 family loads.
  public static let fluidSpeechMini = SpeechModel(
    id: "fluid-speech-mini",
    repository: PinnedRepository(
      repository: "FluidVoice-Labs/fluid-speech-mini-coreml",
      revision: "d81c3160dfe5a5e1f8f7267164a07d30617a3a1a", folder: "fluid-speech-mini",
      expectedDirectoryRoots: [
        "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/",
        "JointDecision.mlmodelc/",
      ],
      expectedFiles: ["parakeet_vocab.json"],
      renamedDirectories: ["JointDecision.mlmodelc/": "JointDecisionv3.mlmodelc/"],
    ),
    family: .ultra, asset: nil,
  )

  public static let catalogue: [SpeechModel] = [.parakeetV2, .fluidSpeechMini]

  public let id: String
  public let repository: PinnedRepository

  /// What history records as the engine behind a transcript.
  public var identity: String {
    repository.identity
  }

  // MARK: Internal

  let family: AsrModelVersion
  /// The library asset that carries the model when it ships; nil for a candidate, which is
  /// installed beside the assets and never offered in the app.
  let asset: ModelAsset?
}
