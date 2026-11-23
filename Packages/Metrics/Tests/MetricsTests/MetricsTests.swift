import Foundation
import Metrics
import Testing

// MARK: - TextShapeTests

struct TextShapeTests {
  @Test(arguments: [
    ("So i think it's fine", TextShape.FirstLetter.upper, TextShape.Ending.none),
    ("“Wait, really?” ", .upper, .question),
    ("(lowercase opener) then more.", .lower, .period),
    ("42 apples...", .none, .ellipsis),
    ("ship it!", .lower, .exclamation),
    ("Zorvek: nalphra:", .upper, .other),
    ("  ", .none, .none),
  ])
  func `reads the first letter and the final mark past quotes and brackets`(
    text: String, first: TextShape.FirstLetter, end: TextShape.Ending,
  ) {
    let shape = TextShape(text)
    #expect(shape.first == first)
    #expect(shape.end == end)
  }

  @Test func `counts characters, words, and capitals`() {
    let shape = TextShape("Run the OK tests")
    #expect(shape.chars == 16)
    #expect(shape.words == 4)
    #expect(shape.upper == 3)
  }

  @Test func `edit distance is Levenshtein, and same words ignore case and punctuation`() {
    #expect(TextChange(from: "kitten", to: "sitting").edit == 3)
    #expect(TextChange(from: "", to: "abc").edit == 3)
    #expect(TextChange(from: "so i think, ok", to: "So I think ok.").wordsSame)
    #expect(!TextChange(from: "um run it", to: "Run it.").wordsSame)
  }
}

// MARK: - MetricsLogTests

struct MetricsLogTests {
  @Test func `a line carries the shape of the text, never the text`() throws {
    let sentinel = "zqxjSENTINELzqxj"
    let line = try String(
      decoding: MetricsLog.line(record(text: .init(
        raw: "um \(sentinel) here", cleaned: "\(sentinel) here", delivered: " \(sentinel) here",
      ))),
      as: UTF8.self,
    )
    #expect(!line.contains(sentinel))
    #expect(line.hasSuffix("}\n"))
    #expect(line.split(separator: "\n").count == 1)
    #expect(line.contains(#""audio_seconds":1.5"#))
    #expect(line.contains(#""cleanup_wait":40"#))
    #expect(line.contains(#""words_same":false"#))
    #expect(line.contains(#""at":"2027-01-15T08:00:00Z""#))
    #expect(!line.contains("delivery"))
  }

  @Test func `appends one line per record to a file only the user can read`() throws {
    let directory = FileManager.default
      .temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = MetricsLog(url: directory.appending(path: "metrics.jsonl"))
    try log.append(record(text: nil))
    try log.append(record(text: nil))

    #expect(try log.read().split(separator: 0x0A).count == 2)
    let permissions = try FileManager.default
      .attributesOfItem(atPath: log.url.path)[.posixPermissions]
    #expect(permissions as? Int == 0o600)
  }

  @Test func `anonymized export drops ids, bundle IDs, and hosts and keeps the rest`() throws {
    let exported = try String(
      decoding: MetricsLog.export(
        MetricsLog.line(record(text: nil)), detail: .anonymized, transcripts: [:],
      ),
      as: UTF8.self,
    )
    #expect(!exported.contains(entryID.uuidString))
    #expect(!exported.contains("com.mitchellh.ghostty"))
    #expect(!exported.contains("api.anthropic.com"))
    #expect(!exported.contains("asr.corp.invalid"))
    #expect(exported.contains(#""kind":"tmux""#))
    #expect(exported.contains(#""model":"claude-haiku-5-5""#))
  }

  @Test func `a transcripts export joins text to the line of its own pass only`() throws {
    var data = try MetricsLog.line(record(text: nil, pass: 0))
    try data.append(MetricsLog.line(record(text: nil, pass: 1)))
    let exported = try MetricsLog.export(
      data, detail: .withTranscripts,
      transcripts: [
        .init(id: entryID, pass: 1): .init(raw: "um retry", cleaned: "Retry.", delivered: nil),
      ],
    )
    let lines = exported.split(separator: 0x0A).map { String(decoding: $0, as: UTF8.self) }
    #expect(lines.count == 2)
    #expect(!lines[0].contains("debug_text"))
    #expect(lines[1].contains(#""debug_text":{"cleaned":"Retry.","raw":"um retry"}"#))
  }
}

private let entryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!

private func record(text: DictationMetrics.Text?, pass: Int = 0) -> DictationMetrics {
  DictationMetrics(
    at: Date(timeIntervalSince1970: 1_800_000_000), id: entryID, pass: pass, kind: .dictation,
    outcome: .delivered, profile: "custom", engine: "scribe_v2", engineHost: "asr.corp.invalid",
    audioSeconds: 1.5,
    gesture: .init(mode: .hold, submit: false, detached: false),
    ms: .init(transcribe: 120, cleanupWait: 40, cleanup: 900),
    target: .init(kind: .tmux, bundle: "com.mitchellh.ghostty"),
    field: .init(outcome: "gridSemantics", chars: nil),
    screen: .init(
      mode: "screenshot",
      captured: .screenshot,
      source: nil,
      textChars: nil,
      jpegBytes: 81920,
    ),
    cleanup: .init(
      model: "claude-haiku-5-5", host: "api.anthropic.com", effort: "off", disposition: .cleaned,
      failure: nil, httpStatus: nil, stripped: [], instructionsChars: 120, vocabulary: 3,
    ),
    text: text, delivery: nil,
  )
}
