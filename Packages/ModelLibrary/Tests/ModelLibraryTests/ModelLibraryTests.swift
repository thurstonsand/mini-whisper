import CryptoKit
import Foundation
@testable import ModelLibrary
import Testing

// MARK: - LibraryValidationTests

struct LibraryValidationTests {
  @Test func `revisions are immutable code pins`() {
    for repository in ModelAsset.allCases.flatMap(\.repositories) {
      #expect(repository.revision.count == 40)
      #expect(!repository.revision.contains("main"))
    }
  }

  /// The layout every install made before assets existed: one provenance file naming all three
  /// repositories. It is the shape the dev channel has on disk, so it must read as two installed
  /// assets with nothing to download.
  @Test func `a single-artifact install validates as every asset in place`() throws {
    let root = try LibraryFixture.install(sizes: [
      "silero-vad": 3,
      "parakeet-tdt-0.6b-v2": 5,
      "parakeet-ctc-110m": 7,
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ModelLibrary(root: root)

    #expect(try library.validate(.gate) == 3)
    #expect(try library.validate(.parakeet) == 12)
  }

  @Test func `missing and corrupt provenance remain distinct`() throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ModelLibrary(root: root)

    #expect(throws: ModelLibraryError.missing(.gate)) { try library.validate(.gate) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: root.appending(path: "provenance.json"))
    let error = #expect(throws: ModelLibraryError.self) { try library.validate(.gate) }
    #expect(error != .missing(.gate))
  }

  /// An asset is all of its repositories or none of them: Parakeet without its recognition helper
  /// is not a lesser Parakeet, it is one still to download.
  @Test func `an asset missing one of its repositories is not installed`() throws {
    let root = try LibraryFixture.install(sizes: ["silero-vad": 3, "parakeet-tdt-0.6b-v2": 5])
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: ModelLibraryError.missing(.parakeet)) {
      try ModelLibrary(root: root).validate(.parakeet)
    }
  }

  @Test func `a revision other than the pin is not installed`() throws {
    let root = try LibraryFixture.install(
      sizes: ["silero-vad": 3], revision: String(repeating: "b", count: 40),
    )
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: ModelLibraryError.missing(.gate)) {
      try ModelLibrary(root: root).validate(.gate)
    }
  }

  @Test func `a file of the wrong size is an invalid artifact`() throws {
    let root = try LibraryFixture.install(sizes: ["silero-vad": 3])
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("toolong".utf8).write(to: root.appending(path: "Models/silero-vad/weights.bin"))

    #expect(throws: ModelLibraryError.invalidArtifact("size mismatch for weights.bin")) {
      try ModelLibrary(root: root).validate(.gate)
    }
  }
}

// MARK: - LibraryDeletionTests

struct LibraryDeletionTests {
  @Test func `deleting one asset leaves the other installed`() async throws {
    let root = try LibraryFixture.install(sizes: [
      "silero-vad": 3,
      "parakeet-tdt-0.6b-v2": 5,
      "parakeet-ctc-110m": 7,
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ModelLibrary(root: root)

    try await library.delete(.parakeet)

    #expect(throws: ModelLibraryError.missing(.parakeet)) { try library.validate(.parakeet) }
    #expect(!FileManager.default
      .fileExists(atPath: root.appending(path: "Models/parakeet-tdt-0.6b-v2").path))
    #expect(!FileManager.default
      .fileExists(atPath: root.appending(path: "Models/parakeet-ctc-110m").path))
    #expect(try library.validate(.gate) == 3)
  }

  @Test func `observers hear a deletion`() async throws {
    let root = try LibraryFixture.install(sizes: [
      "silero-vad": 3,
      "parakeet-tdt-0.6b-v2": 5,
      "parakeet-ctc-110m": 7,
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let library = ModelLibrary(root: root)
    var states = library.states().makeAsyncIterator()

    #expect(await states.next() == [
      .gate: .installed(bytes: 3), .parakeet: .installed(bytes: 12), .s1Mini: .missing,
    ])
    try await library.delete(.gate)
    #expect(await states.next() == [
      .gate: .missing, .parakeet: .installed(bytes: 12), .s1Mini: .missing,
    ])
  }
}

// MARK: - LibraryInstallTests

@Suite(.serialized) struct LibraryInstallTests {
  @Test func `two assets install concurrently into one provenance`() async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let hub = StubHub()
    let library = ModelLibrary(root: root, session: hub.session)
    let fractions = Fractions()

    try await library.install([.gate, .parakeet]) { fractions.append($0) }

    #expect(try library.validate(.gate) == hub.bytes(of: .gate))
    #expect(try library.validate(.parakeet) == hub.bytes(of: .parakeet))
    let provenance = try #require(try Provenance.read(root: root))
    #expect(Set(provenance.repositories.map(\.repository)) ==
      Set([ModelAsset.gate, .parakeet].flatMap(\.repositories).map(\.repository)))
    #expect(fractions.values.last == 1)
    #expect(fractions.values == fractions.values.sorted())
  }

  /// A repository may publish a directory under a name its runtime will not load; it is installed
  /// under the name that loads, and validated where the download put it.
  @Test func `a repository outside every asset installs under its renamed directories`(
  ) async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let candidate = PinnedRepository(
      repository: "Example/candidate-coreml", revision: String(repeating: "c", count: 40),
      folder: "candidate", expectedDirectoryRoots: ["JointDecision.mlmodelc/"],
      expectedFiles: [],
      renamedDirectories: ["JointDecision.mlmodelc/": "JointDecisionv3.mlmodelc/"],
    )
    let hub = StubHub(extraRepositories: [candidate])
    let library = ModelLibrary(root: root, session: hub.session)
    #expect(throws: ModelLibraryError.missingRepository("Example/candidate-coreml")) {
      try library.validate([candidate])
    }

    try await library.install([candidate], name: "candidate") { _ in }

    let folder = root.appending(path: "Models/candidate")
    #expect(FileManager.default.fileExists(
      atPath: folder.appending(path: "JointDecisionv3.mlmodelc/weights.bin").path,
    ))
    #expect(!FileManager.default.fileExists(
      atPath: folder.appending(path: "JointDecision.mlmodelc").path,
    ))
    #expect(try library.validate([
      candidate,
    ]) == "Example/candidate-coreml/JointDecision.mlmodelc/weights.bin"
      .utf8.count)
  }

  /// Switching profiles mid-download asks for the same asset again; that must be the same
  /// download, not a second one racing it into the same staging directory.
  @Test func `a second request for a running download joins it`() async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let hub = StubHub(holdsFiles: true)
    let library = ModelLibrary(root: root, session: hub.session)

    let first = Task { try await library.install(.gate) { _ in } }
    await hub.waitForHeldFile()
    let (joined, signal) = AsyncStream<Void>.makeStream()
    let second = Task { try await library.install(.gate) { _ in signal.yield() } }
    for await _ in joined {
      break
    }
    hub.release()

    try await first.value
    try await second.value
    #expect(hub.treeRequests(for: .sileroVAD) == 1)
  }

  /// The download belongs to the library: one waiter giving up leaves it running for the other.
  @Test func `a download outlives a waiter that leaves`() async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let hub = StubHub(holdsFiles: true)
    let library = ModelLibrary(root: root, session: hub.session)

    let leaving = Task { try await library.install(.gate) { _ in } }
    await hub.waitForHeldFile()
    let (joined, signal) = AsyncStream<Void>.makeStream()
    let staying = Task { try await library.install(.gate) { _ in signal.yield() } }
    for await _ in joined {
      break
    }
    leaving.cancel()
    await #expect(throws: CancellationError.self) { try await leaving.value }
    hub.release()

    try await staying.value
    #expect(try library.validate(.gate) == hub.bytes(of: .gate))
  }

  @Test func `a download nobody waits on stops and leaves nothing installed`() async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let hub = StubHub(holdsFiles: true)
    let library = ModelLibrary(root: root, session: hub.session)
    var states = library.states().makeAsyncIterator()
    #expect(await states.next()?[.gate] == .missing)

    let only = Task { try await library.install(.gate) { _ in } }
    await hub.waitForHeldFile()
    only.cancel()
    await #expect(throws: CancellationError.self) { try await only.value }
    hub.release()

    var last: AssetState?
    while let next = await states.next()?[.gate] {
      last = next
      if next == .missing {
        break
      }
    }
    #expect(last == .missing)
    #expect(throws: ModelLibraryError.missing(.gate)) { try library.validate(.gate) }
  }

  @Test func `deleting a downloading asset is refused`() async throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let hub = StubHub(holdsFiles: true)
    let library = ModelLibrary(root: root, session: hub.session)

    let install = Task { try await library.install(.gate) { _ in } }
    await hub.waitForHeldFile()

    await #expect(throws: ModelLibraryError.downloading(.gate)) { try await library.delete(.gate) }
    hub.release()
    try await install.value
  }
}

// MARK: - StagingReuseTests

struct StagingReuseTests {
  // MARK: Internal

  @Test func `staged file survives only when it hashes to its pinned manifest OID`() throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let installer = AssetInstaller(
      asset: .parakeet,
      root: root.appending(path: "pinned-v1"),
      session: .shared,
    )
    let contents = Data("pinned weights".utf8)

    let matching = try plannedFile(contents, oid: sha256(contents), in: root.appending(path: "a"))
    #expect(try installer.reusableHash(for: matching) == sha256(contents))
    #expect(FileManager.default.fileExists(atPath: matching.destination.path))
  }

  @Test func `unprovable staged files are discarded rather than reused`() throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let installer = AssetInstaller(
      asset: .parakeet,
      root: root.appending(path: "pinned-v1"),
      session: .shared,
    )
    let contents = Data("pinned weights".utf8)

    let splicedRevision = try plannedFile(
      contents, oid: String(repeating: "a", count: 64), in: root.appending(path: "a"),
    )
    let wrongSize = try plannedFile(
      contents, oid: sha256(contents), size: contents.count + 1, in: root.appending(path: "b"),
    )
    let withoutManifestHash = try plannedFile(contents, oid: nil, in: root.appending(path: "c"))

    for planned in [splicedRevision, wrongSize, withoutManifestHash] {
      #expect(try installer.reusableHash(for: planned) == nil)
      #expect(!FileManager.default.fileExists(atPath: planned.destination.path))
    }
  }

  @Test func `each asset stages beside the library under its own name`() {
    let root = URL(fileURLWithPath: "/tmp/Engine/pinned-v1")
    #expect(
      AssetInstaller(asset: .gate, root: root, session: .shared).stagingRoot.path
        == "/tmp/Engine/pinned-v1-gate.partial",
    )
    #expect(
      AssetInstaller(asset: .parakeet, root: root, session: .shared).stagingRoot.path
        == "/tmp/Engine/pinned-v1-parakeet.partial",
    )
  }

  @Test func `matching pins preserve staging contents`() throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let installer = AssetInstaller(
      asset: .parakeet,
      root: root.appending(path: "pinned-v1"),
      session: .shared,
    )
    try installer.prepareStagingRoot()
    let partial = installer.stagingRoot.appending(path: "weights.bin.partial")
    try Data("half".utf8).write(to: partial)

    try installer.prepareStagingRoot()

    #expect(FileManager.default.fileExists(atPath: partial.path))
  }

  @Test func `missing or mismatched pins discard staging contents`() throws {
    let root = LibraryFixture.temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let installer = AssetInstaller(
      asset: .parakeet,
      root: root.appending(path: "pinned-v1"),
      session: .shared,
    )
    let stale = installer.stagingRoot.appending(path: "old.mlmodelc/coremldata.bin")
    try FileManager.default.createDirectory(
      at: stale.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data("stale".utf8).write(to: stale)

    try installer.prepareStagingRoot()

    #expect(!FileManager.default.fileExists(atPath: stale.path))
    try Data("wrong pins".utf8).write(to: installer.stagingPinsURL, options: .atomic)
    try FileManager.default.createDirectory(
      at: stale.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    try Data("stale again".utf8).write(to: stale)
    try installer.prepareStagingRoot()
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: installer.stagingPinsURL.path))
  }

  // MARK: Private

  private func plannedFile(
    _ contents: Data, oid: String?, size: Int? = nil, in root: URL,
  ) throws -> PlannedFile {
    let destination = root.appending(path: "weights.bin")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try contents.write(to: destination)
    return PlannedFile(
      repository: .parakeetTDT,
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

// MARK: - ResumeDecisionTests

struct ResumeDecisionTests {
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
}
