import Foundation
@testable import History
import Testing

// MARK: - HistoryEntryTextTests

/// Presentation inverts storage: the pane's text is the cleanup pass's rewrite, and the transcript
/// it replaced is what the row can reveal.
struct HistoryEntryTextTests {
  @Test func `a cleaned entry shows the rewrite and hides the transcript`() {
    let entry = makeEntry(disposition: .cleaned("Use --help."))
    #expect(entry.displayText == "Use --help.")
    #expect(entry.revealedText == "dash dash help")
    #expect(entry.currentText == "dash dash help")
  }

  @Test func `a skipped or failed pass leaves the transcript as the entry's text`() {
    for disposition in [CleanupDisposition.skipped, .failed("timedOut")] {
      let entry = makeEntry(disposition: disposition)
      #expect(entry.displayText == "dash dash help")
      #expect(entry.revealedText == nil)
    }
  }

  @Test func `an entry no pass ever ran on has nothing to reveal`() {
    let entry = makeEntry(disposition: nil)
    #expect(entry.displayText == "dash dash help")
    #expect(entry.revealedText == nil)
  }

  /// A re-transcription is a newer opinion on the same audio, and it answers with its own
  /// polish or with nothing — never with the original's.
  @Test func `a re-transcription speaks for the entry, and so does its own rewrite`() throws {
    var entry = makeEntry(disposition: .cleaned("Use --help."))
    entry.addRetranscription(
      Transcription(
        text: "dash dash help me", engine: "second-engine",
        transcribedAt: Date(timeIntervalSinceReferenceDate: 760_000_100),
      ),
    )
    #expect(entry.displayText == "dash dash help me")
    #expect(entry.revealedText == nil)

    try entry.addRetranscription(
      Transcription(
        text: "dash dash help me now", engine: "second-engine",
        transcribedAt: Date(timeIntervalSinceReferenceDate: 760_000_200),
        cleanup: CleanupRecord(
          disposition: .cleaned("--help me now"), model: "gpt-oss-120b",
          endpoint: #require(URL(string: "https://gateway.example/v1")), durationSeconds: 1.4,
        ),
      ),
    )
    #expect(entry.displayText == "--help me now")
    #expect(entry.revealedText == "dash dash help me now")
    #expect(entry.original?.cleanup?.cleanedText == "Use --help.")
  }

  @Test func `an entry transcription never reached shows nothing`() throws {
    let entry = try HistoryEntry(
      id: #require(UUID(uuidString: "5B7B1C1E-6F2E-4C0E-9A2E-1B7D2C3E4F50")),
      createdAt: Date(timeIntervalSinceReferenceDate: 760_000_000), targetApp: nil, original: nil,
      delivery: nil, audio: AudioMetadata(durationSeconds: 1, byteCount: 64044),
    )
    #expect(entry.displayText == nil)
    #expect(entry.revealedText == nil)
  }
}

private func makeEntry(disposition: CleanupDisposition?) -> HistoryEntry {
  let createdAt = Date(timeIntervalSinceReferenceDate: 760_000_000)
  return HistoryEntry(
    id: UUID(uuidString: "5B7B1C1E-6F2E-4C0E-9A2E-1B7D2C3E4F50")!,
    createdAt: createdAt,
    targetApp: TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
    original: Transcription(
      text: "dash dash help", engine: "parakeet-tdt-0.6b-v2", transcribedAt: createdAt,
      cleanup: disposition.map {
        CleanupRecord(
          disposition: $0, model: "gpt-oss-120b",
          endpoint: URL(string: "https://gateway.example/v1")!, durationSeconds: 2.1,
        )
      },
    ),
    delivery: nil,
    audio: AudioMetadata(durationSeconds: 1, byteCount: 64044),
  )
}
