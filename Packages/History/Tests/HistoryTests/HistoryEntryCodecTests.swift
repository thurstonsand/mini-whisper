import FieldContext
import Foundation
@testable import History
import Testing

// MARK: - HistoryEntryCodecTests

struct HistoryEntryCodecTests {
  @Test func `a cleaned entry survives a round trip with its context and record`() throws {
    let log = HistoryLog(entries: [cleanedEntry()])
    let decoded = try JSONDecoder().decode(HistoryLog.self, from: JSONEncoder().encode(log))
    #expect(decoded == log)
  }

  @Test func `every disposition survives a round trip`() throws {
    let dispositions: [CleanupDisposition] = [
      .cleaned("Use --help."), .skipped, .failed("timedOut"),
    ]
    for disposition in dispositions {
      let record = try CleanupRecord(
        disposition: disposition, model: "gpt-oss-120b",
        endpoint: #require(URL(string: "https://gateway.example/v1")), durationSeconds: 1.5,
      )
      let decoded = try JSONDecoder().decode(
        CleanupRecord.self, from: JSONEncoder().encode(record),
      )
      #expect(decoded == record)
    }
  }

  @Test func `a skip is not a failure`() throws {
    let skipped = try CleanupRecord(
      disposition: .skipped, model: "gpt-oss-120b",
      endpoint: #require(URL(string: "https://gateway.example/v1")), durationSeconds: 3.2,
    )
    #expect(skipped.cleanedText == nil)
    #expect(skipped.disposition != .failed("cancelled"))
  }

  @Test func `an entry written before cleanup existed still decodes`() throws {
    let json = Data(
      """
      {
        "version": 2,
        "entries": [
          {
            "id": "5B7B1C1E-6F2E-4C0E-9A2E-1B7D2C3E4F50",
            "createdAt": 760000000,
            "targetApp": { "bundleID": "com.mitchellh.ghostty", "name": "Ghostty" },
            "original": {
              "text": "dash dash help",
              "engine": "parakeet-tdt-0.6b-v2",
              "transcribedAt": 760000001
            },
            "retranscriptions": [],
            "delivery": { "text": "dash dash help", "method": "pasted" }
          }
        ]
      }
      """.utf8,
    )
    let decoded = try JSONDecoder().decode(HistoryLog.self, from: json)
    let entry = try #require(decoded.entries.first)
    #expect(entry.original?.cleanup == nil)
    #expect(entry.fieldContext == nil)
    #expect(entry.currentText == "dash dash help")
  }

  /// The benchmark harness reads the log by hand: it rejects a version it does not know, selects
  /// `original.text`, and picks up field context from an entry key it already looks for.
  @Test func `the harness's contract on the persisted shape holds`() throws {
    let data = try JSONEncoder().encode(HistoryLog(entries: [cleanedEntry()]))
    let object = try #require(
      try JSONSerialization.jsonObject(with: data) as? [String: Any],
    )
    #expect(object["version"] as? Int == 2)
    let entries = try #require(object["entries"] as? [[String: Any]])
    let entry = try #require(entries.first)
    let original = try #require(entry["original"] as? [String: Any])
    #expect(original["text"] as? String == "dash dash help me")
    let context = try #require(entry["fieldContext"] as? [String: Any])
    #expect(context["before"] as? String == "$ ")
  }

  @Test func `retention keeps the cleanup record and the context it was conditioned on`() {
    let entry = cleanedEntry()
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .forever, audio: .never), to: HistoryLog(entries: [entry]),
    )
    let kept = outcome.log.entries[0]
    #expect(kept.original?.cleanup == entry.original?.cleanup)
    #expect(kept.fieldContext == entry.fieldContext)
  }
}

private func cleanedEntry() -> HistoryEntry {
  let createdAt = Date(timeIntervalSinceReferenceDate: 760_000_000)
  return HistoryEntry(
    id: UUID(uuidString: "5B7B1C1E-6F2E-4C0E-9A2E-1B7D2C3E4F50")!,
    createdAt: createdAt,
    targetApp: TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
    original: Transcription(
      text: "dash dash help me", engine: "parakeet-tdt-0.6b-v2", transcribedAt: createdAt,
      cleanup: CleanupRecord(
        disposition: .cleaned("--help me"), model: "gpt-oss-120b",
        endpoint: URL(string: "https://gateway.example/v1")!, durationSeconds: 2.1,
      ),
    ),
    fieldContext: FocusedTextContext(
      role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
      beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
    ),
    delivery: Delivery(text: "--help me", method: .pasted, detail: nil),
    audio: AudioMetadata(durationSeconds: 1, byteCount: 64044),
  )
}
