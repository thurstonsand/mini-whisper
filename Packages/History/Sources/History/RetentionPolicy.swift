import Foundation

// MARK: - RetentionTTL

/// One preset scale for both keys. `never` is the shortest limit rather than a separate off
/// switch, so storage and retention stay one control that cannot contradict itself.
public enum RetentionTTL: String, Codable, CaseIterable, Comparable, Sendable {
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

  /// `allCases` is declared from shortest to longest and defines the retention ordering.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
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

  /// The two things history keeps, each with its own limit.
  public enum Key: String, CaseIterable, Equatable, Sendable {
    case transcripts
    case audio
  }

  public static let defaults = RetentionPolicy(transcripts: .forever, audio: .sevenDays)

  public var transcripts: RetentionTTL
  public var audio: RetentionTTL

  public subscript(key: Key) -> RetentionTTL {
    get {
      switch key {
      case .transcripts:
        transcripts
      case .audio:
        audio
      }
    }
    set {
      switch key {
      case .transcripts:
        transcripts = newValue
      case .audio:
        audio = newValue
      }
    }
  }
}
