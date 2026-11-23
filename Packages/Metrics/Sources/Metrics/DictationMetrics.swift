import Foundation

// MARK: - DictationMetrics

/// One engine pass, as one line of `metrics.jsonl`: a dictation from press to delivery, a
/// recording the gate refused, or a re-transcription of an entry's audio.
///
/// The file is meant to be handed to someone else, so a line carries no dictated, cleaned, field,
/// or screen text, and no window title. Text enters only through `TextShape` and `TextChange`,
/// which keep counts. The strings that remain are identities and fixed vocabularies: a profile, a
/// model, a bundle ID, a host, a reason. Export strips the identifying ones on request.
///
/// A missing key means that stage was never reached.
public struct DictationMetrics: Encodable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    at: Date, id: UUID?, pass: Int?, kind: Kind, outcome: Outcome, profile: String,
    engine: String, engineHost: String?, audioSeconds: Double?, gesture: Gesture?, ms: Timings,
    target: Target?,
    field: Field?, screen: Screen?, cleanup: Cleanup?, text: Text?, delivery: Delivery?,
  ) {
    self.at = at
    self.id = id
    self.pass = pass
    self.kind = kind
    self.outcome = outcome
    self.profile = profile
    self.engine = engine
    self.engineHost = engineHost
    self.audioSeconds = audioSeconds
    self.gesture = gesture
    self.ms = ms
    self.target = target
    self.field = field
    self.screen = screen
    self.cleanup = cleanup
    self.text = text
    self.delivery = delivery
  }

  // MARK: Public

  public enum Kind: String, Encodable, Sendable {
    case dictation
    case retranscription
  }

  public enum Outcome: String, Encodable, Sendable {
    case delivered
    case deliveryFailed = "delivery_failed"
    case cancelled
    case transcriptionFailed = "transcription_failed"
    case tooShort = "too_short"
    case noSpeech = "no_speech"
    case engineEmpty = "engine_empty"
    /// A re-transcription, which delivers nowhere.
    case transcribed
  }

  public struct Gesture: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(mode: Mode, submit: Bool, detached: Bool) {
      self.mode = mode
      self.submit = submit
      self.detached = detached
    }

    // MARK: Public

    public enum Mode: String, Encodable, Sendable {
      case hold
      case latch
    }

    public let mode: Mode
    public let submit: Bool
    /// A later press moved it to the background before it finished.
    public let detached: Bool
  }

  /// Stage durations in whole milliseconds, each between two moments the app already marks.
  public struct Timings: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
      stop: Int? = nil, transcribe: Int? = nil, context: Int? = nil, cleanupWait: Int? = nil,
      cleanup: Int? = nil, deliver: Int? = nil, total: Int? = nil,
    ) {
      self.stop = stop
      self.transcribe = transcribe
      self.context = context
      self.cleanupWait = cleanupWait
      self.cleanup = cleanup
      self.deliver = deliver
      self.total = total
    }

    // MARK: Public

    /// Release to the recording being closed and handed over.
    public let stop: Int?
    public let transcribe: Int?
    /// Transcript to the field having been read.
    public let context: Int?
    /// Field read to the cleanup request leaving: the wait on the screen read.
    public let cleanupWait: Int?
    public let cleanup: Int?
    /// Delivery starting to delivery finishing, which on a paste route includes the wait to put
    /// the clipboard back.
    public let deliver: Int?
    /// Release to the dictation finishing, however it ended.
    public let total: Int?

    public static func milliseconds(_ seconds: Double?) -> Int? {
      seconds.map { Int(($0 * 1000).rounded()) }
    }

    public static func milliseconds(from start: Date?, to end: Date?) -> Int? {
      guard let start, let end else {
        return nil
      }
      return milliseconds(end.timeIntervalSince(start))
    }
  }

  public struct Target: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(kind: Kind, bundle: String?) {
      self.kind = kind
      self.bundle = bundle
    }

    // MARK: Public

    public enum Kind: String, Encodable, Sendable {
      case tmux
      case ghostty
      case gui
      case none
    }

    public let kind: Kind
    public let bundle: String?
  }

  public struct Field: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(outcome: String, chars: Int?) {
      self.outcome = outcome
      self.chars = chars
    }

    // MARK: Public

    /// `available`, or why the field could not be read, such as `gridSemantics`.
    public let outcome: String
    public let chars: Int?
  }

  public struct Screen: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
      mode: String?, captured: Captured, source: String?, textChars: Int?, jpegBytes: Int?,
    ) {
      self.mode = mode
      self.captured = captured
      self.source = source
      self.textChars = textChars
      self.jpegBytes = jpegBytes
    }

    // MARK: Public

    public enum Captured: String, Encodable, Sendable {
      case none
      case text
      case screenshot
    }

    /// The Expanded context setting; absent on a re-transcription, which reuses what was kept.
    public let mode: String?
    /// What was read and handed to cleanup.
    public let captured: Captured
    /// Where the text came from: `tmux`, `accessibility`, or `ocr`.
    public let source: String?
    public let textChars: Int?
    public let jpegBytes: Int?
  }

  public struct Cleanup: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
      model: String, host: String?, effort: String, disposition: Disposition, failure: String?,
      httpStatus: Int?, stripped: [String]?, instructionsChars: Int, vocabulary: Int,
    ) {
      self.model = model
      self.host = host
      self.effort = effort
      self.disposition = disposition
      self.failure = failure
      self.httpStatus = httpStatus
      self.stripped = stripped
      self.instructionsChars = instructionsChars
      self.vocabulary = vocabulary
    }

    // MARK: Public

    public enum Disposition: String, Encodable, Sendable {
      case cleaned
      case skipped
      case failed
    }

    public let model: String
    public let host: String?
    public let effort: String
    public let disposition: Disposition
    public let failure: String?
    public let httpStatus: Int?
    /// The wrappers response shaping peeled off the reply, in order; absent when no reply
    /// reached shaping.
    public let stripped: [String]?
    /// Additional Instructions, trimmed; 0 when there are none.
    public let instructionsChars: Int
    public let vocabulary: Int
  }

  /// The text at each point it can change: as heard, as cleaned, as delivered after the join.
  public struct Text: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(raw: String, cleaned: String?, delivered: String?) {
      self.raw = TextShape(raw)
      self.cleaned = cleaned.map(TextShape.init)
      self.delivered = delivered.map(TextShape.init)
      change = cleaned.map { TextChange(from: raw, to: $0) }
    }

    // MARK: Public

    public let raw: TextShape
    public let cleaned: TextShape?
    public let delivered: TextShape?
    public let change: TextChange?
  }

  public struct Delivery: Encodable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(method: String, detail: String?) {
      self.method = method
      self.detail = detail
    }

    // MARK: Public

    public let method: String
    public let detail: String?
  }

  /// Bumped for a rename, a removal, or a change of unit; a new field does not bump it.
  public static let version = 1

  public let v = Self.version
  public let at: Date
  /// The History entry, so a line can be joined to its text on a debugging export; absent when
  /// nothing was written to History.
  public let id: UUID?
  /// 0 for the dictation itself, n for the entry's nth re-transcription; absent for a
  /// re-transcription that failed, which History never kept.
  public let pass: Int?
  public let kind: Kind
  public let outcome: Outcome
  public let profile: String
  /// The engine's model identity.
  public let engine: String
  /// An overridden hosted engine's endpoint host, kept apart from `engine` so export can drop it.
  public let engineHost: String?
  public let audioSeconds: Double?
  public let gesture: Gesture?
  public let ms: Timings
  public let target: Target?
  public let field: Field?
  public let screen: Screen?
  public let cleanup: Cleanup?
  public let text: Text?
  public let delivery: Delivery?
}
