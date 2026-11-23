import Foundation

// MARK: - MetricsLog

/// `metrics.jsonl`: one line per record, appended and never rewritten, so a record is never lost
/// to another being written beside it and the user may delete the file at any time.
public struct MetricsLog: Sendable {
  // MARK: Lifecycle

  public init(url: URL) {
    self.url = url
  }

  // MARK: Public

  public enum ExportDetail: String, CaseIterable, Sendable {
    /// No entry ids, bundle IDs, or endpoint hosts: safe to hand to anyone.
    case anonymized
    /// Every field as it was written.
    case identified
    /// Every field, plus the text of the History entry each line came from, while History
    /// still has it. For debugging only.
    case withTranscripts = "with-transcripts"
  }

  /// The text one History transcription went through, keyed by entry and pass.
  public struct Transcripts: Equatable, Sendable {
    // MARK: Lifecycle

    public init(raw: String, cleaned: String?, delivered: String?) {
      self.raw = raw
      self.cleaned = cleaned
      self.delivered = delivered
    }

    // MARK: Public

    public let raw: String
    public let cleaned: String?
    public let delivered: String?
  }

  public struct PassKey: Hashable, Sendable {
    // MARK: Lifecycle

    public init(id: UUID, pass: Int) {
      self.id = id
      self.pass = pass
    }

    // MARK: Public

    public let id: UUID
    public let pass: Int
  }

  public let url: URL

  public static func line(_ record: DictationMetrics) throws -> Data {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
  }

  /// Every line rewritten for `detail`. Lines are handled as JSON objects rather than decoded,
  /// so a file that spans schema versions exports whole.
  public static func export(
    _ data: Data, detail: ExportDetail, transcripts: [PassKey: Transcripts],
  ) throws -> Data {
    var output = Data()
    for line in data.split(separator: 0x0A) where !line.isEmpty {
      guard var object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        throw ExportError.notAnObject
      }
      switch detail {
      case .anonymized:
        object["id"] = nil
        object["engine_host"] = nil
        object["target"] = (object["target"] as? [String: Any])
          .map { $0.filter { $0.key != "bundle" } }
        object["cleanup"] = (object["cleanup"] as? [String: Any])
          .map { $0.filter { $0.key != "host" } }
      case .identified:
        break
      case .withTranscripts:
        if let id = (object["id"] as? String).flatMap(UUID.init(uuidString:)),
           let pass = object["pass"] as? Int,
           let text = transcripts[PassKey(id: id, pass: pass)]
        {
          var debug: [String: Any] = ["raw": text.raw]
          debug["cleaned"] = text.cleaned
          debug["delivered"] = text.delivered
          object["debug_text"] = debug
        }
      }
      try output.append(
        JSONSerialization.data(
          withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes],
        ),
      )
      output.append(0x0A)
    }
    return output
  }

  /// One whole line in one `write` to a descriptor opened for appending, so concurrent records
  /// cannot interleave.
  public func append(_ record: DictationMetrics) throws {
    let line = try Self.line(record)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }
    let written = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    guard written == line.count else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  public func read() throws -> Data {
    try Data(contentsOf: url)
  }

  // MARK: Private

  private enum ExportError: Error {
    case notAnObject
  }
}
