import Foundation

// MARK: - ReasoningEffort

/// How hard a reasoning model thinks before it answers. Each level is sent as OpenAI's
/// `reasoning_effort`, the one field most compatible endpoints read, and which levels a model
/// accepts is the endpoint's business: one that refuses a level fails the request and says why.
/// Anthropic's is the exception, with only an off switch to read. There is no Minimal: no model a
/// profile ships accepts it.
public enum ReasoningEffort: String, CaseIterable, Codable, Sendable {
  /// Send nothing, and let the model decide.
  case modelDecides
  case off = "none"
  case low
  case medium
  case high

  // MARK: Public

  public var title: String {
    switch self {
    case .modelDecides:
      "Model decides"
    case .off:
      "Off"
    case .low:
      "Low"
    case .medium:
      "Medium"
    case .high:
      "High"
    }
  }

  public static func levels(for endpoint: URL?) -> [ReasoningEffort] {
    isAnthropic(endpoint) ? [.modelDecides, .off] : allCases
  }

  // MARK: Internal

  /// Anthropic's compatibility layer ignores `reasoning_effort`; turning Claude's thinking off
  /// takes its own `thinking` field, which other endpoints reject as unknown.
  static func isAnthropic(_ endpoint: URL?) -> Bool {
    endpoint?.host() == "api.anthropic.com"
  }
}
