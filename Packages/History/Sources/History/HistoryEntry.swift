import FieldContext
import Foundation

// MARK: - HistoryLog

/// The whole history, persisted as one JSON file via `@Shared(.fileStorage)`.
public struct HistoryLog: Equatable, Sendable {
  // MARK: Lifecycle

  public init(entries: [HistoryEntry] = []) {
    self.entries = entries
  }

  // MARK: Public

  /// Newest first — new dictations are inserted at the front.
  public var entries: [HistoryEntry]
}

// MARK: Codable

extension HistoryLog: Codable {
  private enum CodingKeys: String, CodingKey {
    case version
    case entries
  }

  /// Bumped when `HistoryEntry`'s persisted shape changes incompatibly; decoding rejects files
  /// from a version it does not know rather than misreading them. Version 2 moved the cleanup
  /// record from the entry onto the transcription it polished, so every transcription — the
  /// original and every re-transcription — carries its own.
  public static let version = 2

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == Self.version else {
      throw DecodingError.dataCorruptedError(
        forKey: .version, in: container,
        debugDescription: "Unsupported history log version \(version); this build reads \(Self.version)",
      )
    }
    entries = try container.decode([HistoryEntry].self, forKey: .entries)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.version, forKey: .version)
    try container.encode(entries, forKey: .entries)
  }
}

// MARK: - HistoryEntry

/// One dictation's lifecycle. The entry is created when a dictation produces anything durable,
/// and each stage is optional because a dictation can die between stages: `original` is nil when
/// transcription never completed, `delivery` is nil when delivery was never reached. Absence
/// means "not reached", never "unknown".
public struct HistoryEntry: Equatable, Codable, Sendable, Identifiable {
  // MARK: Lifecycle

  public init(
    id: UUID,
    createdAt: Date,
    targetApp: TargetApp?,
    original: Transcription?,
    retranscriptions: [Transcription] = [],
    reference: String? = nil,
    fieldContext: FocusedTextContext? = nil,
    delivery: Delivery?,
    audio: AudioMetadata?,
  ) {
    self.id = id
    self.createdAt = createdAt
    self.targetApp = targetApp
    self.original = original
    self.retranscriptions = retranscriptions
    self.reference = reference
    self.fieldContext = fieldContext
    self.delivery = delivery
    self.audio = audio
  }

  // MARK: Public

  public let id: UUID
  public let createdAt: Date
  public let targetApp: TargetApp?
  /// What the engine said at dictation time. Never rewritten — later attempts append to
  /// `retranscriptions`, so the corpus can always tell the original from a second opinion.
  public let original: Transcription?
  public private(set) var retranscriptions: [Transcription]
  /// Human-verified ground truth: what was actually said, supplied by a person who listened.
  /// Nil until then — engine output is never promoted to reference.
  public var reference: String?
  /// The field context that conditioned this dictation, captured once before cleanup and reused
  /// by delivery's join. Persisted so the benchmark harness can replay the real prompt — and so a
  /// re-transcription's cleanup pass can be conditioned exactly as the dictation's was; nil when
  /// the capture failed or delivery was never reached.
  public var fieldContext: FocusedTextContext?
  public var delivery: Delivery?
  public var audio: AudioMetadata?

  /// The newest opinion on the audio, original included. Every question the pane asks of an
  /// entry's text is a question about this one transcription.
  public var currentTranscription: Transcription? {
    retranscriptions.last ?? original
  }

  /// What the engine said, without its polish.
  public var currentText: String? {
    currentTranscription?.text
  }

  /// The text the pane shows.
  public var displayText: String? {
    currentTranscription.map { $0.cleanup?.cleanedText ?? $0.text }
  }

  /// The transcript underneath the displayed text, or nil when the row already shows it — which
  /// is also what says whether there is anything to reveal.
  public var revealedText: String? {
    guard let current = currentTranscription, current.cleanup?.cleanedText != nil else {
      return nil
    }
    return current.text
  }

  public mutating func addRetranscription(_ transcription: Transcription) {
    retranscriptions.append(transcription)
  }
}

// MARK: - Transcription

/// One pass of the engine over a recording, and whatever the cleanup pass made of it. The two
/// travel together because they are one processing run: a transcription's polish is a fact about
/// that transcription, not about the entry, so a re-transcription answers for its own.
public struct Transcription: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(text: String, engine: String, transcribedAt: Date, cleanup: CleanupRecord? = nil) {
    self.text = text
    self.engine = engine
    self.transcribedAt = transcribedAt
    self.cleanup = cleanup
  }

  // MARK: Public

  public let text: String
  /// Fixed model identity, e.g. the Hugging Face repository the engine loaded.
  public let engine: String
  public let transcribedAt: Date
  public var cleanup: CleanupRecord?
}

// MARK: - TargetApp

public struct TargetApp: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(bundleID: String, name: String?) {
    self.bundleID = bundleID
    self.name = name
  }

  // MARK: Public

  public let bundleID: String
  public let name: String?
}

// MARK: - Delivery

public struct Delivery: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(text: String, method: Method, detail: String?) {
    self.text = text
    self.method = method
    self.detail = detail
  }

  // MARK: Public

  public enum Method: String, Codable, Sendable {
    case pasted
    case copied
    case noReceiver
    case failed
  }

  /// The text delivery attempted, after any cleanup pass and the field-context join rules.
  /// Not necessarily what the engine said, and — for `copied` and `failed` — not necessarily
  /// what reached the target.
  public let text: String
  public let method: Method
  /// Why delivery took this path — a fallback reason or an error description.
  public let detail: String?
}

// MARK: - AudioMetadata

/// Facts about the entry's stored audio that vary per recording. Location is derived from the
/// entry id, and format is canonical by construction, so neither is repeated here.
public struct AudioMetadata: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(durationSeconds: Double, byteCount: Int) {
    self.durationSeconds = durationSeconds
    self.byteCount = byteCount
  }

  // MARK: Public

  public let durationSeconds: Double
  public let byteCount: Int
}
