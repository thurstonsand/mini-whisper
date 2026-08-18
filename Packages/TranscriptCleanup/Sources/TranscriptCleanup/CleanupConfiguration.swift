import Foundation

// MARK: - CleanupConfiguration

/// Everything the user configures about the cleanup pass except the key, which travels separately
/// because it lives in the Keychain rather than in settings.
///
/// `endpoint` is the OpenAI-compatible API base — the URL a gateway documents as its root for
/// `chat/completions` and `models`, typically ending in `/v1`. The client appends the paths; a
/// trailing slash on the base is tolerated and nothing else is guessed.
public struct CleanupConfiguration: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    endpoint: URL, model: String, timeout: TimeInterval = Self.defaultTimeout,
    additionalInstructions: String,
  ) {
    precondition(timeout > 0)
    self.endpoint = endpoint
    self.model = model
    self.timeout = timeout
    self.additionalInstructions = additionalInstructions
  }

  // MARK: Public

  public static let defaultTimeout: TimeInterval = 10

  /// The verify round-trip answers a person waiting on a Save button, so it gets its own short
  /// budget instead of the dictation timeout the user may have stretched to a minute.
  public static let verificationTimeout: TimeInterval = 5

  public let endpoint: URL
  public let model: String
  public let timeout: TimeInterval

  /// Appended to the built-in prompt, never substituted for it. Empty means the built-in prompt
  /// stands alone.
  public let additionalInstructions: String

  // MARK: Internal

  var chatCompletionsURL: URL {
    endpoint.appending(path: "chat/completions")
  }

  var modelsURL: URL {
    endpoint.appending(path: "models")
  }
}
