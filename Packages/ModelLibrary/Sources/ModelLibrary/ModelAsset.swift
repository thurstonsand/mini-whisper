import Foundation

// MARK: - PinnedRepository

/// One Hugging Face repository at an immutable revision, and the slice of it the app runs.
public struct PinnedRepository: Hashable, Sendable {
  // MARK: Lifecycle

  /// `renamedDirectories` maps a remote directory root to the name it is installed under, for a
  /// repository that publishes a directory under a name its runtime does not load.
  public init(
    repository: String, revision: String, folder: String, expectedDirectoryRoots: [String],
    expectedFiles: [String], renamedDirectories: [String: String] = [:],
  ) {
    self.repository = repository
    self.revision = revision
    self.folder = folder
    self.expectedDirectoryRoots = expectedDirectoryRoots
    self.expectedFiles = expectedFiles
    self.renamedDirectories = renamedDirectories
  }

  // MARK: Public

  public static let parakeetTDT = PinnedRepository(
    repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
    revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39", folder: "parakeet-tdt-0.6b-v2",
    expectedDirectoryRoots: [
      "Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/",
    ],
    expectedFiles: ["parakeet_vocab.json"],
  )

  public static let parakeetCTC = PinnedRepository(
    repository: "FluidInference/parakeet-ctc-110m-coreml",
    revision: "accdafd8cf8a2ff1cabe3c11e54416b405d409aa", folder: "parakeet-ctc-110m",
    expectedDirectoryRoots: ["MelSpectrogram.mlmodelc/", "AudioEncoder.mlmodelc/"],
    expectedFiles: ["tokenizer.json", "vocab.json"],
  )

  public static let sileroVAD = PinnedRepository(
    repository: "FluidInference/silero-vad-coreml",
    revision: "b419383c55c110e2c9271fa6ee0ea83d03c70d96", folder: "silero-vad",
    expectedDirectoryRoots: ["silero-vad-unified-256ms-v6.2.1.mlmodelc/"], expectedFiles: [],
  )

  /// "S1-mini" by "Superwhisper", the Q4_K_M quantization, with the license and notice that
  /// require it be named exactly so.
  public static let s1Mini = PinnedRepository(
    repository: "superwhisper/s1-mini-GGUF",
    revision: "34add00a48a2e5d24e5a4ee5405a99620a3a240c", folder: "s1-mini",
    expectedDirectoryRoots: [], expectedFiles: ["s1-mini-q4_k_m.gguf", "LICENSE", "NOTICE"],
  )

  public let repository: String
  public let revision: String
  /// The directory under `Models/`. These are the single-artifact layout's names, so an install
  /// made before assets existed validates in place.
  public let folder: String

  public var identity: String {
    "\(repository)@\(revision)"
  }

  // MARK: Internal

  let expectedDirectoryRoots: [String]
  let expectedFiles: [String]
  let renamedDirectories: [String: String]

  /// Where a file the repository lists lives under the repository's folder.
  func localPath(of remotePath: String) -> String {
    for (remote, local) in renamedDirectories where remotePath.hasPrefix(remote) {
      return local + remotePath.dropFirst(remote.count)
    }
    return remotePath
  }
}

// MARK: - ModelAsset

/// A unit of the library: downloaded, verified, and deleted as one, independently of every other.
public enum ModelAsset: String, CaseIterable, Hashable, Sendable {
  case gate
  case parakeet
  case s1Mini = "s1-mini"

  // MARK: Public

  public var name: String {
    switch self {
    case .gate:
      "Speech gate"
    case .parakeet:
      "Parakeet TDT v2"
    case .s1Mini:
      "S1-mini"
    }
  }

  public var purpose: String {
    switch self {
    case .gate:
      "Silence rejection, run before any engine"
    case .parakeet:
      "The local speech engine and its recognition helper"
    case .s1Mini:
      "The local cleanup model"
    }
  }

  public var repositories: [PinnedRepository] {
    switch self {
    case .gate:
      [.sileroVAD]
    case .parakeet:
      [.parakeetTDT, .parakeetCTC]
    case .s1Mini:
      [.s1Mini]
    }
  }

  /// What the pins weigh. A revision never changes, so neither does its size, which is what lets
  /// one bar weigh several assets before any of them has been listed.
  public var pinnedBytes: Int {
    switch self {
    case .gate:
      1_063_425
    case .parakeet:
      567_215_702
    case .s1Mini:
      484_232_348
    }
  }
}

// MARK: - AssetState

public enum AssetState: Equatable, Sendable {
  case missing
  case downloading(Double)
  case installed(bytes: Int)
  case failed(String)

  // MARK: Public

  public var isInstalled: Bool {
    if case .installed = self {
      return true
    }
    return false
  }

  /// Missing or failed: a press asks for it the ordinary way.
  public var isDownloadable: Bool {
    switch self {
    case .missing,
         .failed:
      true
    case .installed,
         .downloading:
      false
    }
  }
}

// MARK: - ModelLibraryError

public enum ModelLibraryError: Error, Equatable, LocalizedError, Sendable {
  case missing(ModelAsset)
  /// A repository installed outside any asset, such as a speech model under evaluation.
  case missingRepository(String)
  case invalidArtifact(String)
  case invalidDownload(String)
  case downloading(ModelAsset)

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case let .missing(asset):
      "\(asset.name) is not installed"
    case let .missingRepository(repository):
      "\(repository) is not installed"
    case let .invalidArtifact(message):
      "Invalid pinned model artifact: \(message)"
    case let .invalidDownload(message):
      "Pinned model download failed: \(message)"
    case let .downloading(asset):
      "\(asset.name) is still downloading"
    }
  }
}
