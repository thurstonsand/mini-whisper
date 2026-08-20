import Foundation

// MARK: - CleanupRecord

/// What the cleanup pass did to one dictation. It sits beside the original transcription rather
/// than replacing it: the corpus has to be able to tell a recognition error from a cleanup
/// rewrite, and the benchmark harness replays raw→cleaned pairs.
///
/// A record exists only when a pass was actually attempted, so `model`, `endpoint`, and
/// `durationSeconds` are always answerable — even for a skip, which measures how long the user
/// was willing to wait.
public struct CleanupRecord: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(
    disposition: CleanupDisposition, model: String, endpoint: URL, durationSeconds: Double,
  ) {
    self.disposition = disposition
    self.model = model
    self.endpoint = endpoint
    self.durationSeconds = durationSeconds
  }

  // MARK: Public

  public let disposition: CleanupDisposition
  public let model: String
  /// The endpoint's identity, not a credential: the configured API base, as configured.
  public let endpoint: URL
  /// Wall clock from the request leaving to the outcome arriving, however it ended.
  public let durationSeconds: Double

  public var cleanedText: String? {
    guard case let .cleaned(text) = disposition else {
      return nil
    }
    return text
  }
}

// MARK: - CleanupDisposition

/// How a cleanup pass ended. A skip is the user resolving the wait with an activation press; it is
/// deliberately not a failure, because nothing went wrong.
public enum CleanupDisposition: Equatable, Sendable {
  case cleaned(String)
  case skipped
  case failed(String)
}

// MARK: Codable

extension CleanupDisposition: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case text
    case reason
  }

  private enum Kind: String, Codable {
    case cleaned
    case skipped
    case failed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .cleaned:
      self = try .cleaned(container.decode(String.self, forKey: .text))
    case .skipped:
      self = .skipped
    case .failed:
      self = try .failed(container.decode(String.self, forKey: .reason))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .cleaned(text):
      try container.encode(Kind.cleaned, forKey: .kind)
      try container.encode(text, forKey: .text)
    case .skipped:
      try container.encode(Kind.skipped, forKey: .kind)
    case let .failed(reason):
      try container.encode(Kind.failed, forKey: .kind)
      try container.encode(reason, forKey: .reason)
    }
  }
}
