import FluidAudio

// MARK: - SpeechModel

/// One pinned Core ML transcription model FluidAudio can run. The app ships exactly one; the rest
/// exist so `asr-replay` can install and measure a candidate without an engine code change.
public struct SpeechModel: Hashable, Sendable {
  // MARK: Lifecycle

  init(
    id: String, repository: String, revision: String, localFolder: String, artifactName: String,
    family: AsrModelVersion, directories: [String], renamedDirectories: [String: String],
  ) {
    self.id = id
    self.repository = repository
    self.revision = revision
    self.localFolder = localFolder
    self.artifactName = artifactName
    self.family = family
    self.directories = directories
    self.renamedDirectories = renamedDirectories
  }

  // MARK: Public

  public static let parakeetV2 = SpeechModel(
    id: "parakeet-v2", repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
    revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39", localFolder: "parakeet-tdt-0.6b-v2",
    artifactName: "pinned-v1", family: .v2,
    directories: [
      "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/",
    ],
    renamedDirectories: [:],
  )

  /// Evaluated and rejected; kept as the worked example of a v3-family community model. Its
  /// repository publishes the joint as `JointDecision.mlmodelc`, the name FluidAudio reserves
  /// for v2, so it is installed under the `JointDecisionv3.mlmodelc` every v3 family loads.
  public static let fluidSpeechMini = SpeechModel(
    id: "fluid-speech-mini", repository: "FluidVoice-Labs/fluid-speech-mini-coreml",
    revision: "d81c3160dfe5a5e1f8f7267164a07d30617a3a1a", localFolder: "fluid-speech-mini",
    artifactName: "pinned-fluid-speech-mini", family: .ultra,
    directories: [
      "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/",
    ],
    renamedDirectories: ["JointDecision.mlmodelc/": "JointDecisionv3.mlmodelc/"],
  )

  public static let catalogue: [SpeechModel] = [.parakeetV2, .fluidSpeechMini]

  public let id: String
  public let repository: String
  /// The engine root's directory name, beside its siblings under a channel's `Engine/`.
  public let artifactName: String

  /// What history records as the engine behind a transcript.
  public var identity: String {
    "\(repository)@\(revision)"
  }

  // MARK: Internal

  let revision: String
  let localFolder: String
  let family: AsrModelVersion
  /// Remote directory roots, as the repository names them.
  let directories: [String]
  let renamedDirectories: [String: String]

  func localPath(of remotePath: String) -> String {
    for (remote, local) in renamedDirectories where remotePath.hasPrefix(remote) {
      return local + remotePath.dropFirst(remote.count)
    }
    return remotePath
  }
}
