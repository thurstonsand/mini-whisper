import Foundation
@testable import History
import Testing

// MARK: - RetentionTests

struct RetentionTests {
  @Test func `the transcript TTL removes whole entries and releases their audio`() {
    let old = entry(age: 2 * 86400, audio: true)
    let new = entry()
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .oneDay, audio: .forever), to: HistoryLog(entries: [new, old]),
    )

    #expect(outcome.log.entries == [new])
    #expect(outcome.audioToDelete == [old.id])
  }

  @Test func `the audio TTL prunes bytes but keeps the transcript`() {
    let aged = entry(age: 2 * 86400, audio: true)
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .forever, audio: .oneDay), to: HistoryLog(entries: [aged]),
    )

    let kept = outcome.log.entries[0]
    #expect(kept.audio == nil)
    #expect(kept.currentText == aged.currentText)
    #expect(outcome.audioToDelete == [aged.id])
  }

  @Test func `never is the shortest TTL, not a special case`() {
    let fresh = entry(audio: true)
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .forever, audio: .never), to: HistoryLog(entries: [fresh]),
    )
    #expect(outcome.log.entries[0].audio == nil)
    #expect(outcome.audioToDelete == [fresh.id])
  }

  @Test func `a pinned entry survives both automated passes`() {
    var pinned = entry(age: 400 * 86400, audio: true)
    pinned.pinned = true
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .never, audio: .never), to: HistoryLog(entries: [pinned]),
    )

    #expect(outcome.log.entries == [pinned])
    #expect(outcome.audioToDelete.isEmpty)
  }

  @Test func `forever prunes nothing`() {
    let log = HistoryLog(entries: [entry(age: 3650 * 86400, audio: true)])
    let outcome = Retention.apply(RetentionPolicy(transcripts: .forever, audio: .forever), to: log)
    #expect(outcome.log == log)
    #expect(outcome.audioToDelete.isEmpty)
  }

  @Test func `an entry without audio ages out without demanding a deletion`() {
    let outcome = Retention.apply(
      RetentionPolicy(transcripts: .never, audio: .never),
      to: HistoryLog(entries: [entry(age: 60)]),
    )
    #expect(outcome.log.entries.isEmpty)
    #expect(outcome.audioToDelete.isEmpty)
  }
}

func entry(text: String = "hello world", age: TimeInterval = 0, audio: Bool = false)
  -> HistoryEntry
{
  let createdAt = Date().addingTimeInterval(-age)
  return HistoryEntry(
    id: UUID(),
    createdAt: createdAt,
    targetApp: TargetApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
    original: Transcription(text: text, engine: "parakeet-tdt-0.6b-v2", transcribedAt: createdAt),
    delivery: Delivery(text: text, method: .pasted, detail: nil),
    audio: audio ? AudioMetadata(durationSeconds: 1, byteCount: 64044) : nil,
  )
}
