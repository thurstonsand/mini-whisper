import AppSettings
import AudioCapture
import FieldContext
import Foundation
import History
import Metrics
@testable import MiniWhisper
import Testing

struct DictationMetricsTests {
  /// Two strings reach a line from outside the app's own vocabulary: the role a target app
  /// reports for a non-text element, and a custom speech endpoint's host. Neither may leak.
  @Test func `an app's own role name stays out, and a custom engine host stays separable`() throws {
    var dictation = AppFeature.PendingDictation(
      generation: 1, recording: CanonicalRecording(samples: [0.25]),
      createdAt: Date(timeIntervalSince1970: 100), releasedAt: Date(timeIntervalSince1970: 99),
      latched: true, profile: .accurate, screenMode: .off,
      engine: "asr.corp.invalid/scribe_v2", engineHost: "asr.corp.invalid",
      original: History.Transcription(
        text: "zqxjSENTINEL", engine: "asr.corp.invalid/scribe_v2",
        transcribedAt: Date(timeIntervalSince1970: 101),
      ),
    )
    dictation.capture = .unavailable(.nonTextElement(role: "AXzqxjROLE"))
    let delivery = DeliveryOutcome.noReceiver(.nonTextElement(role: "AXzqxjROLE"))
      .delivery(of: "zqxjSENTINEL")
    #expect(delivery.detail?.contains("AXzqxjROLE") == true)

    let record = DictationMetrics.dictation(
      dictation, id: nil, outcome: .delivered, finishedAt: Date(timeIntervalSince1970: 103),
      detached: false, delivery: delivery, vocabulary: 0,
    )
    let line = try String(decoding: MetricsLog.line(record), as: UTF8.self)
    #expect(!line.contains("zqxj"))
    #expect(record.delivery?.detail == "nonTextElement")
    #expect(record.engine == "scribe_v2")
    #expect(record.ms.total == 4000)
    #expect(record.ms.stop == 1000)
    #expect(record.gesture?.mode == .latch)

    let anonymized = try String(
      decoding: MetricsLog.export(
        MetricsLog.line(record), detail: .anonymized, transcripts: [:],
      ),
      as: UTF8.self,
    )
    #expect(!anonymized.contains("asr.corp.invalid"))
  }
}
