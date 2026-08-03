@testable import ASREngine
import CryptoKit
import Foundation
import Testing

// MARK: - EngineLifecycleTests

struct EngineLifecycleTests {
  @Test func `only active setup phases reject A second setup`() {
    #expect(EngineReadiness.downloading(0).isSetupInProgress)
    #expect(EngineReadiness.compiling.isSetupInProgress)
    #expect(EngineReadiness.prewarming.isSetupInProgress)
    #expect(!EngineReadiness.modelMissing.isSetupInProgress)
    #expect(!EngineReadiness.ready.isSetupInProgress)
    #expect(!EngineReadiness.failed("failure").isSetupInProgress)
  }

  @Test func `model revisions are immutable code pins`() {
    #expect(PinnedModelStore.asrRevision.count == 40)
    #expect(PinnedModelStore.vadRevision.count == 40)
    #expect(!PinnedModelStore.asrRevision.contains("main"))
    #expect(!PinnedModelStore.vadRevision.contains("main"))
  }

  @Test func `missing and corrupt provenance remain distinct`() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root)

    #expect(throws: ASREngineError.modelMissing) { try store.validateInstalledArtifact() }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: root.appending(path: "provenance.json"))
    #expect(throws: ASREngineError.self) { try store.validateInstalledArtifact() }
  }

  @Test func `missing install emits model missing before finishing`() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    let engine = LocalASREngine(
      gateConfiguration: .calibrated, modelStore: PinnedModelStore(root: root),
    )
    var readiness: [EngineReadiness] = []

    for await update in engine.prepareInstalled() {
      readiness.append(update)
    }

    #expect(readiness == [.modelMissing])
  }

  @Test func `range responses append only when the offset and pinned size match`() {
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 206,
        contentRange: "bytes 1048576-9999999/10000000", contentLength: 8_951_424,
      ) == .append,
    )
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 206,
        contentRange: "bytes 0-9999999/10000000", contentLength: 10_000_000,
      ) == .restart,
    )
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 206,
        contentRange: "bytes 1048576-9999999/9999999", contentLength: 8_951_423,
      ) == .restart,
    )
  }

  @Test func `ignored or rejected ranges restart safely`() {
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 200, contentRange: nil,
        contentLength: 10_000_000,
      ) == .overwrite,
    )
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 416, contentRange: nil,
        contentLength: 0,
      ) == .restart,
    )
    #expect(
      ResumeDecision.decide(
        resumeOffset: 1_048_576, expectedBytes: 10_000_000, statusCode: 403, contentRange: nil,
        contentLength: 0,
      ) == .restart,
    )
  }

  @Test func `malformed content ranges are rejected`() {
    let range = HTTPContentRange("bytes 10-19/20")
    #expect(range?.start == 10)
    #expect(range?.end == 19)
    #expect(range?.total == 20)
    #expect(HTTPContentRange("bytes 20-10/30") == nil)
    #expect(HTTPContentRange("bytes */30") == nil)
    #expect(HTTPContentRange("garbage") == nil)
  }

  @Test func `staging root is stable across store instances`() {
    let root = URL(fileURLWithPath: "/tmp/MiniWhisper-test-pinned-v1")
    #expect(PinnedModelStore(root: root).stagingRoot == root.appendingPathExtension("partial"))
  }

  @Test func `concurrent setup emits failure before finishing`() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    let engine = LocalASREngine(
      gateConfiguration: .calibrated, modelStore: PinnedModelStore(root: root),
    )
    let (setupStarted, setupStartedContinuation) = AsyncStream<Void>.makeStream()
    let firstSetup = Task {
      for await update in engine.installAndPrepare() {
        guard update == .downloading(0) else {
          continue
        }
        setupStartedContinuation.yield()
        setupStartedContinuation.finish()
      }
    }

    for await _ in setupStarted {
      break
    }
    var duplicateReadiness: [EngineReadiness] = []
    for await update in engine.installAndPrepare() {
      duplicateReadiness.append(update)
    }

    #expect(duplicateReadiness == [.failed(ASREngineError.setupInProgress.localizedDescription)])
    firstSetup.cancel()
    await firstSetup.value
  }
}

// MARK: - StagingReuseTests

struct StagingReuseTests {
  // MARK: Internal

  @Test func `staged file survives only when it hashes to its pinned manifest OID`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root.appending(path: "pinned-v1"))
    let contents = Data("pinned weights".utf8)

    let matching = try plannedFile(contents, oid: sha256(contents), in: root.appending(path: "a"))
    #expect(try store.reusableHash(for: matching) == sha256(contents))
    #expect(FileManager.default.fileExists(atPath: matching.destination.path))
  }

  @Test func `unprovable staged files are discarded rather than reused`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root.appending(path: "pinned-v1"))
    let contents = Data("pinned weights".utf8)

    let splicedRevision = try plannedFile(
      contents, oid: String(repeating: "a", count: 64), in: root.appending(path: "a"),
    )
    let wrongSize = try plannedFile(
      contents, oid: sha256(contents), size: contents.count + 1, in: root.appending(path: "b"),
    )
    let withoutManifestHash = try plannedFile(contents, oid: nil, in: root.appending(path: "c"))

    for planned in [splicedRevision, wrongSize, withoutManifestHash] {
      #expect(try store.reusableHash(for: planned) == nil)
      #expect(!FileManager.default.fileExists(atPath: planned.destination.path))
    }
  }

  @Test func `matching pins preserve staging contents`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root.appending(path: "pinned-v1"))
    try store.prepareStagingRoot()
    let partial = store.stagingRoot.appending(path: "weights.bin.partial")
    try Data("half".utf8).write(to: partial)

    try store.prepareStagingRoot()

    #expect(FileManager.default.fileExists(atPath: partial.path))
  }

  @Test func `missing or mismatched pins discard staging contents`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root.appending(path: "pinned-v1"))
    let stale = store.stagingRoot.appending(path: "Models/old.mlmodelc/coremldata.bin")
    try FileManager.default.createDirectory(
      at: stale.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data("stale".utf8).write(to: stale)

    try store.prepareStagingRoot()

    #expect(!FileManager.default.fileExists(atPath: stale.path))
    try Data("wrong pins".utf8).write(to: store.stagingPinsURL, options: .atomic)
    try FileManager.default.createDirectory(
      at: stale.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data("stale again".utf8).write(to: stale)
    try store.prepareStagingRoot()
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: store.stagingPinsURL.path))
  }

  // MARK: Private

  private let specification = RepositorySpecification(
    repository: PinnedModelStore.asrRepository, revision: PinnedModelStore.asrRevision,
    localFolder: "parakeet-tdt-0.6b-v2", expectedDirectoryRoots: [], expectedFiles: [],
  )

  private func plannedFile(
    _ contents: Data, oid: String?, size: Int? = nil, in root: URL,
  ) throws -> PlannedFile {
    let destination = root.appending(path: "weights.bin")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try contents.write(to: destination)
    return PlannedFile(
      specification: specification,
      file: RemoteFile(
        path: "weights.bin", type: "file", size: size ?? contents.count,
        lfs: oid.map(RemoteFile.LFS.init),
      ), destination: destination,
    )
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - InstalledArtifactValidationTests

struct InstalledArtifactValidationTests {
  // MARK: Internal

  @Test func `launch validation accepts correct sizes without rehashing the corpus`() throws {
    let store = try install(size: 5, contents: "other")
    defer { try? FileManager.default.removeItem(at: store.root) }
    try FileManager.default.createDirectory(
      at: store.stagingRoot, withIntermediateDirectories: true,
    )

    try store.validateInstalledArtifact()

    #expect(!FileManager.default.fileExists(atPath: store.stagingRoot.path))
  }

  @Test func `launch validation rejects size mismatches`() throws {
    let store = try install(size: 6, contents: "five!")
    defer { try? FileManager.default.removeItem(at: store.root) }

    #expect(throws: ASREngineError.self) { try store.validateInstalledArtifact() }
  }

  // MARK: Private

  private func install(size: Int, contents: String) throws -> PinnedModelStore {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let file = root.appending(path: "Models/parakeet-tdt-0.6b-v2/Encoder.mlmodelc/coremldata.bin")
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data(contents.utf8).write(to: file)
    let provenance = """
    {"repositories":[
      {"repository":"\(PinnedModelStore.asrRepository)",
       "revision":"\(PinnedModelStore.asrRevision)",
       "files":[{"path":"Encoder.mlmodelc/coremldata.bin","size":\(size),
                 "sha256":"\(String(repeating: "a", count: 64))"}]},
      {"repository":"\(PinnedModelStore.vadRepository)",
       "revision":"\(PinnedModelStore.vadRevision)","files":[]}]}
    """
    try Data(provenance.utf8).write(to: root.appending(path: "provenance.json"))
    return PinnedModelStore(root: root)
  }
}

// MARK: - GateFramingTests

struct GateFramingTests {
  @Test(
    arguments: [
      (count: 1, padded: 4096), (count: 4095, padded: 4096), (count: 4096, padded: 4096),
      (count: 4097, padded: 8192),
    ],
  ) func `Zero padding produces exact FluidAudio frames`(count: Int, padded: Int) {
    let samples = (0 ..< count).map(Float.init)
    let result = GateFraming.zeroPaddedCopy(of: samples)

    #expect(result.count == padded)
    #expect(Array(result.prefix(count)) == samples)
    #expect(result.dropFirst(count).allSatisfy { $0 == 0 })
    #expect(result.count.isMultiple(of: GateFraming.frameSampleCount))
  }

  @Test func `empty audio does not manufacture A frame`() {
    #expect(GateFraming.zeroPaddedCopy(of: []).isEmpty)
  }
}

// MARK: - GateConfigurationTests

struct GateConfigurationTests {
  @Test func `calibrated settings match the published bakeoff`() {
    let configuration = GateConfiguration.calibrated
    let segmentation = configuration.segmentationConfiguration

    #expect(configuration.threshold == 0.9)
    #expect(configuration.minimumSpeechDuration == 0.15)
    #expect(segmentation.minSpeechDuration == 0.15)
    #expect(segmentation.minSilenceDuration == 0.75)
    #expect(segmentation.maxSpeechDuration == .infinity)
    #expect(segmentation.speechPadding == 0)
    #expect(segmentation.silenceThresholdForSplit == 0.3)
    #expect(segmentation.negativeThreshold == 0.75)
    #expect(segmentation.negativeThresholdOffset == 0.15)
    #expect(segmentation.minSilenceAtMaxSpeech == 0.098)
    #expect(segmentation.useMaxPossibleSilenceAtMaxSpeech)
    #expect(GateFraming.frameSampleCount == 4096)
  }

  @Test func `negative threshold never reaches zero`() {
    let segmentation = GateConfiguration(threshold: 0.1, minimumSpeechDuration: 0.15)
      .segmentationConfiguration

    #expect(segmentation.negativeThreshold == 0.01)
  }
}

// MARK: - TranscriptionOutcomeMapperTests

struct TranscriptionOutcomeMapperTests {
  @Test func `accepted empty transcript remains distinct`() {
    #expect(TranscriptionOutcomeMapper.map(transcript: "  \n") == .engineEmpty)
  }

  @Test func `accepted text is trimmed and returned`() {
    #expect(TranscriptionOutcomeMapper.map(transcript: " hello \n") == .transcript("hello"))
  }
}
