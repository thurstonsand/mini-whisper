import Foundation

// MARK: - CleanupOutcome

/// What one cleanup pass produced. Cancellation is not a failure: any activation press resolves a
/// pending cleanup as a skip, so it is the most ordinary non-success there is.
public enum CleanupOutcome: Equatable, Sendable {
  case cleaned(String)
  case cancelled
  case failed(CleanupFailure)
}

// MARK: - VerificationOutcome

/// What the Profiles pane's Save learns from `verify`: endpoint, key, and model proven together,
/// with nothing carried back on success.
public enum VerificationOutcome: Equatable, Sendable {
  case verified
  case cancelled
  case failed(CleanupFailure)
}

// MARK: - ModelListing

/// `GET /v1/models` is a convenience for the pane's picker; a gateway that does not serve it is
/// not broken, it is just not browsable.
public enum ModelListing: Equatable, Sendable {
  case models([String])
  case cancelled
  case unavailable(CleanupFailure)
}

// MARK: - CleanupFailure

/// Why a cleanup could not produce text. Every case falls back to the raw transcript at the app
/// layer; this package never invents that fallback itself.
public enum CleanupFailure: Error, Equatable, LocalizedError, Sendable {
  /// The request never reached a responding endpoint.
  case unreachable(String)
  case httpStatus(code: Int, message: String?)
  case timedOut(TimeInterval)
  /// A 2xx body that is not an OpenAI-compatible completion.
  case malformedResponse(String)
  /// A well-formed completion whose content cannot be what the speaker meant to type.
  case degenerateResponse(DegenerateResponse)
  /// The model on this Mac could not run.
  case localModel(String)

  // MARK: Public

  /// Google refuses a bad key with a 400 that only its message tells apart.
  public var rejectsKey: Bool {
    switch self {
    case .httpStatus(401, _),
         .httpStatus(403, _):
      true
    case let .httpStatus(400, message):
      message?.localizedCaseInsensitiveContains("API key") == true
    default:
      false
    }
  }

  public var errorDescription: String? {
    switch self {
    case let .unreachable(message):
      "Cleanup endpoint unreachable: \(message)"
    case let .httpStatus(code, message):
      message.map { "Cleanup endpoint returned HTTP \(code): \($0)" }
        ?? "Cleanup endpoint returned HTTP \(code)"
    case let .timedOut(timeout):
      "Cleanup timed out after \(Int(timeout.rounded()))s"
    case let .malformedResponse(message):
      "Cleanup response was malformed: \(message)"
    case let .degenerateResponse(reason):
      "Cleanup response was unusable: \(reason.description)"
    case let .localModel(message):
      "Local cleanup failed: \(message)"
    }
  }
}

// MARK: - DegenerateResponse

/// Deliberately two rules, both cheap and both provable. Phrase-matching an assistant's apology
/// would also reject a speaker who dictated one, and the corpus spike has not yet earned that
/// risk; a model that answers instead of editing overwhelmingly announces itself by length.
public enum DegenerateResponse: Error, Equatable, Sendable {
  /// Nothing survived response shaping.
  case empty
  /// Far more text came back than went in, so the model wrote rather than edited.
  case runaway(cleanedLength: Int, transcriptLength: Int)

  // MARK: Public

  public var description: String {
    switch self {
    case .empty:
      "the model returned no text"
    case let .runaway(cleanedLength, transcriptLength):
      "the model returned \(cleanedLength) characters for a \(transcriptLength)-character transcript"
    }
  }
}
