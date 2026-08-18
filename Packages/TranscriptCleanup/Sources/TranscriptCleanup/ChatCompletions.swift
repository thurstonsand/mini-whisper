import Foundation

// MARK: - ChatCompletionRequest

/// The OpenAI-compatible request body, spelled out rather than imported: the work allowlist has no
/// room for an SDK, and one bounded completion is not much of a protocol.
struct ChatCompletionRequest: Encodable {
  let model: String
  let messages: [ChatMessage]
  /// Delivery is atomic, so a partial completion is useless; say so rather than rely on defaults.
  let stream = false
}

// MARK: - ChatMessage

struct ChatMessage: Encodable {
  let role: String
  let content: String
}

// MARK: - ChatCompletionResponse

struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }

    let message: Message
  }

  let choices: [Choice]
}

// MARK: - ModelsResponse

struct ModelsResponse: Decodable {
  struct Model: Decodable {
    let id: String
  }

  let data: [Model]
}

// MARK: - ErrorResponse

/// The shape every OpenAI-compatible gateway uses for a non-2xx body. It is read only to give the
/// Cleanup pane something specific to show; its absence is not itself a failure.
struct ErrorResponse: Decodable {
  struct Payload: Decodable {
    let message: String?
  }

  let error: Payload
}
