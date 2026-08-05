import Foundation

// MARK: - RetentionTTL

/// One preset scale for both keys. `never` is the shortest limit rather than a separate off
/// switch, so storage and retention stay one control that cannot contradict itself.
public enum RetentionTTL: String, Codable, CaseIterable, Sendable {
  case never
  case oneDay = "1d"
  case sevenDays = "7d"
  case thirtyDays = "30d"
  case ninetyDays = "90d"
  case oneYear = "1y"
  case forever

  // MARK: Public

  /// Seconds an item may age before the retention pass removes it; nil means it never expires.
  public var maxAge: TimeInterval? {
    switch self {
    case .never:
      0
    case .oneDay:
      86400
    case .sevenDays:
      7 * 86400
    case .thirtyDays:
      30 * 86400
    case .ninetyDays:
      90 * 86400
    case .oneYear:
      365 * 86400
    case .forever:
      nil
    }
  }
}

// MARK: - RetentionPolicy

public struct RetentionPolicy: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(transcripts: RetentionTTL, audio: RetentionTTL) {
    self.transcripts = transcripts
    self.audio = audio
  }

  // MARK: Public

  public static let defaults = RetentionPolicy(transcripts: .forever, audio: .sevenDays)

  public var transcripts: RetentionTTL
  public var audio: RetentionTTL
}
