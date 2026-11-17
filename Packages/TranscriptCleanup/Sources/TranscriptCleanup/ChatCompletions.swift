import Foundation

// MARK: - ChatCompletionRequest

/// The OpenAI-compatible request body, spelled out rather than imported: the work allowlist has no
/// room for an SDK, and one bounded completion is not much of a protocol.
struct ChatCompletionRequest: Encodable {
  // MARK: Lifecycle

  init(configuration: CleanupConfiguration, messages: [ChatMessage]) {
    model = configuration.model
    self.messages = messages
    switch configuration.reasoningEffort {
    case .modelDecides:
      break
    case .off where ReasoningEffort.isAnthropic(configuration.endpoint):
      thinking = Thinking(type: "disabled")
    case .off,
         .low,
         .medium,
         .high:
      reasoningEffort = configuration.reasoningEffort.rawValue
    }
  }

  // MARK: Internal

  struct Thinking: Encodable {
    let type: String
  }

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case stream
    case reasoningEffort = "reasoning_effort"
    case thinking
  }

  let model: String
  let messages: [ChatMessage]
  /// Delivery is atomic, so a partial completion is useless; say so rather than rely on defaults.
  let stream = false
  private(set) var reasoningEffort: String?
  private(set) var thinking: Thinking?
}

// MARK: - ChatMessage

/// A message is plain text, except a user message that carries a screenshot, which the API takes
/// as content parts: the text, then the image as a data URL.
struct ChatMessage: Encodable {
  // MARK: Lifecycle

  init(role: String, content: String, image: Data? = nil) {
    self.role = role
    text = content
    self.image = image
  }

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case role
    case content
  }

  let role: String
  let text: String
  /// A JPEG.
  let image: Data?

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(role, forKey: .role)
    guard let image else {
      try container.encode(text, forKey: .content)
      return
    }
    try container.encode(
      [
        Part(type: "text", text: text, imageURL: nil),
        Part(
          type: "image_url", text: nil,
          imageURL: .init(url: "data:image/jpeg;base64,\(image.base64EncodedString())"),
        ),
      ],
      forKey: .content,
    )
  }

  // MARK: Private

  private struct Part: Encodable {
    struct ImageURL: Encodable {
      let url: String
    }

    enum CodingKeys: String, CodingKey {
      case type
      case text
      case imageURL = "image_url"
    }

    let type: String
    let text: String?
    let imageURL: ImageURL?
  }
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
