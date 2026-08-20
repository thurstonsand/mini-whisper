import AudioCapture
import Foundation
@testable import History
import Testing

// MARK: - AudioVaultTests

struct AudioVaultTests {
  // MARK: Internal

  @Test func `writing a recording yields metadata whose file exists at the id-derived URL`() throws {
    let vault = freshVault()
    let id = UUID()
    let audio = try vault.write(
      CanonicalRecording(samples: .init(repeating: 0.1, count: 16000)), id: id,
    )

    #expect(audio.durationSeconds == 1.0)
    #expect(audio.byteCount > 16000)
    #expect(FileManager.default.fileExists(atPath: vault.url(id: id).path))
  }

  @Test func `delete removes exactly the named entries' audio`() throws {
    let vault = freshVault()
    let keep = UUID()
    let drop = UUID()
    _ = try vault.write(CanonicalRecording(samples: .init(repeating: 0.1, count: 160)), id: keep)
    _ = try vault.write(CanonicalRecording(samples: .init(repeating: 0.1, count: 160)), id: drop)

    try vault.delete([drop])
    #expect(FileManager.default.fileExists(atPath: vault.url(id: keep).path))
    #expect(!FileManager.default.fileExists(atPath: vault.url(id: drop).path))
  }

  @Test func `deleting audio that is already gone is satisfied by absence`() throws {
    let vault = freshVault()
    try vault.delete([UUID()])
  }

  @Test func `deletion failures other than absence propagate`() throws {
    let vault = freshVault()
    let id = UUID()
    _ = try vault.write(CanonicalRecording(samples: .init(repeating: 0.1, count: 160)), id: id)
    // Removing write permission from the directory makes unlink fail with a permission error,
    // which must surface rather than being swallowed as success.
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: vault.directoryURL.path,
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: vault.directoryURL.path,
      )
    }
    #expect(throws: (any Error).self) { try vault.delete([id]) }
  }

  @Test func `reconcile clears metadata whose file is gone and deletes files nothing references`(
  ) throws {
    let vault = freshVault()

    var withMissingFile = entry(audio: true)
    var withPresentFile = entry(audio: true)
    withPresentFile.audio = try vault.write(
      CanonicalRecording(samples: .init(repeating: 0.1, count: 160)), id: withPresentFile.id,
    )
    let orphanID = UUID()
    _ = try vault.write(
      CanonicalRecording(samples: .init(repeating: 0.1, count: 160)),
      id: orphanID,
    )
    let strayURL = vault.directoryURL.appendingPathComponent("not-an-entry.wav")
    try Data([0x00]).write(to: strayURL)
    // A referenced entry's UUID under the wrong extension is still not the entry's audio.
    let impostorURL = vault.directoryURL
      .appendingPathComponent("\(withPresentFile.id.uuidString).txt")
    try Data([0x00]).write(to: impostorURL)

    let log = try vault.reconcile(HistoryLog(entries: [withPresentFile, withMissingFile]))

    #expect(log.entries[0].audio == withPresentFile.audio)
    #expect(log.entries[1].audio == nil)
    #expect(!FileManager.default.fileExists(atPath: vault.url(id: orphanID).path))
    #expect(!FileManager.default.fileExists(atPath: strayURL.path))
    #expect(!FileManager.default.fileExists(atPath: impostorURL.path))
    withMissingFile.audio = nil
    #expect(log.entries[1] == withMissingFile)
  }

  @Test func `reconcile of an audioless log against a missing directory is a no-op`() throws {
    let vault = freshVault(create: false)
    let log = HistoryLog(entries: [entry()])
    #expect(try vault.reconcile(log) == log)
  }

  // MARK: Private

  private func freshVault(create: Bool = true) -> AudioVault {
    let directory = FileManager.default
      .temporaryDirectory
      .appendingPathComponent("audio-vault-tests-\(UUID().uuidString)")
    if create {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return AudioVault(directoryURL: directory)
  }
}

// MARK: - HistoryLogCodingTests

struct HistoryLogCodingTests {
  @Test func `the log round-trips through Codable`() throws {
    let log = HistoryLog(entries: [entry(audio: true), entry()])
    let decoded = try JSONDecoder().decode(HistoryLog.self, from: JSONEncoder().encode(log))
    #expect(decoded == log)
  }

  @Test func `a lifecycle-truncated entry round-trips: audio kept, transcription never reached`(
  ) throws {
    let truncated = HistoryEntry(
      id: UUID(),
      createdAt: Date(timeIntervalSince1970: 1_754_000_000),
      targetApp: nil,
      original: nil,
      delivery: nil,
      audio: AudioMetadata(durationSeconds: 4.2, byteCount: 268_844),
    )
    let log = HistoryLog(entries: [truncated])
    let decoded = try JSONDecoder().decode(HistoryLog.self, from: JSONEncoder().encode(log))
    #expect(decoded.entries[0] == truncated)
    #expect(decoded.entries[0].currentText == nil)
  }

  @Test func `a log from an unknown version refuses to decode`() throws {
    let data = Data(#"{"version": 3, "entries": []}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(HistoryLog.self, from: data) }
  }

  @Test func `a re-transcription lands beside the original, never over it`() {
    var mutated = entry(text: "original")
    mutated.addRetranscription(
      Transcription(text: "second opinion", engine: "candidate", transcribedAt: Date()),
    )
    #expect(mutated.original?.text == "original")
    #expect(mutated.currentText == "second opinion")
  }

  /// A version-1 log carried its cleanup record on the entry; version 2 carries it on the
  /// transcription it polished, and the two cannot be told apart by shape alone.
  @Test func `a log from the version that kept cleanup on the entry refuses to decode`() throws {
    let data = Data(#"{"version": 1, "entries": []}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(HistoryLog.self, from: data) }
  }
}
