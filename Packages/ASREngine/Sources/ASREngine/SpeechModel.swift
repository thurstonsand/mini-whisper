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

  /// Evaluated and rejected. Fluid Speech Pro ships only as `.nemo`; this is VoiceiQ's unofficial
  /// fp16 Core ML conversion of upstream revision 53f490b, which already names its joint
  /// `JointDecisionv3.mlmodelc`.
  public static let fluidSpeechPro = SpeechModel(
    id: "fluid-speech-pro-coreml",
    repository: PinnedRepository(
      repository: "cyron/fluid-speech-pro-coreml",
      revision: "ec52e16204b3d2c4c8bf60e576728fc58a825689", folder: "fluid-speech-pro",
      expectedDirectoryRoots: [
        "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/",
        "JointDecisionv3.mlmodelc/",
      ],
      expectedFiles: ["parakeet_vocab.json"],
    ),
    family: .ultra, asset: nil,
  )

  public static let catalogue: [SpeechModel] = [.parakeetV2, .fluidSpeechMini, .fluidSpeechPro]

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
