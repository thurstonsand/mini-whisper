import Foundation

// MARK: - OpenAICompatibleCleanup

/// The cleanup pass as one seam: prompt in, conformed text or a typed failure out. It never falls
/// back to the raw transcript — the caller owns that decision, and a client that quietly returned
/// the input would make a failed cleanup indistinguishable from a cleanup that changed nothing.
public struct OpenAICompatibleCleanup: Sendable {
  // MARK: Lifecycle

  public init(configuration: CleanupConfiguration, apiKey: String, session: URLSession = .shared) {
    self.configuration = configuration
    self.apiKey = apiKey
    self.session = session
  }

  // MARK: Public

  public func clean(_ request: CleanupRequest) async -> CleanupOutcome {
    let messages = [
      ChatMessage(
        role: "system",
        content: CleanupPrompt.systemMessage(
          additionalInstructions: configuration.additionalInstructions,
        ),
      ),
      ChatMessage(role: "user", content: CleanupPrompt.userMessage(request)),
    ]
    switch await completion(messages: messages, timeout: configuration.timeout) {
    case let .succeeded(content):
      switch CleanupResponseShaping.conform(content, transcript: request.transcript) {
      case let .success(cleaned):
        return .cleaned(cleaned)
      case let .failure(reason):
        return .failed(.degenerateResponse(reason))
      }
    case .cancelled:
      return .cancelled
    case let .failed(failure):
      return .failed(failure)
    }
  }

  /// Proves endpoint, key, and model together with the smallest completion that can fail for each
  /// of those reasons separately. What comes back is irrelevant — that it came back is the point,
  /// and grading a micro-completion's text would invent a failure the pane could not explain.
  public func verify() async -> VerificationOutcome {
    let messages = [
      ChatMessage(role: "system", content: "Reply with the single word: ready."),
      ChatMessage(role: "user", content: "ready"),
    ]
    switch await completion(
      messages: messages, timeout: CleanupConfiguration.verificationTimeout,
    ) {
    case .succeeded:
      return .verified
    case .cancelled:
      return .cancelled
    case let .failed(failure):
      return .failed(failure)
    }
  }

  public func listModels() async -> ModelListing {
    var request = URLRequest(url: configuration.modelsURL)
    request.httpMethod = "GET"
    request.timeoutInterval = CleanupConfiguration.verificationTimeout
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    switch await send(request, timeout: CleanupConfiguration.verificationTimeout) {
    case let .succeeded(data):
      do {
        let listing = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return .models(listing.data.map(\.id))
      } catch {
        return .unavailable(.malformedResponse("model list: \(error.localizedDescription)"))
      }
    case .cancelled:
      return .cancelled
    case let .failed(failure):
      return .unavailable(failure)
    }
  }

  // MARK: Private

  private enum Transport<Value: Sendable> {
    case succeeded(Value)
    case cancelled
    case failed(CleanupFailure)
  }

  private let configuration: CleanupConfiguration
  private let apiKey: String
  private let session: URLSession

  private static func errorMessage(in data: Data) -> String? {
    guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
          let message = response.error.message, !message.isEmpty
    else {
      return nil
    }
    return message
  }

  private func completion(
    messages: [ChatMessage], timeout: TimeInterval,
  ) async -> Transport<String> {
    var request = URLRequest(url: configuration.chatCompletionsURL)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    do {
      request.httpBody = try JSONEncoder().encode(
        ChatCompletionRequest(model: configuration.model, messages: messages),
      )
    } catch {
      // Two strings and a bool; an encoder that cannot manage that is a broken runtime.
      preconditionFailure("Chat completion request failed to encode: \(error)")
    }

    switch await send(request, timeout: timeout) {
    case let .succeeded(data):
      do {
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
          return .failed(.malformedResponse("completion carried no message content"))
        }
        return .succeeded(content)
      } catch {
        return .failed(.malformedResponse(error.localizedDescription))
      }
    case .cancelled:
      return .cancelled
    case let .failed(failure):
      return .failed(failure)
    }
  }

  private func send(_ request: URLRequest, timeout: TimeInterval) async -> Transport<Data> {
    do {
      let (data, response) = try await session.data(for: request)
      guard let response = response as? HTTPURLResponse else {
        return .failed(.malformedResponse("response was not HTTP"))
      }
      guard (200 ..< 300).contains(response.statusCode) else {
        return .failed(
          .httpStatus(code: response.statusCode, message: Self.errorMessage(in: data)),
        )
      }
      return .succeeded(data)
    } catch is CancellationError {
      return .cancelled
    } catch let error as URLError {
      switch error.code {
      case .cancelled:
        return .cancelled
      case .timedOut:
        return .failed(.timedOut(timeout))
      default:
        return .failed(.unreachable(error.localizedDescription))
      }
    } catch {
      return .failed(.unreachable(error.localizedDescription))
    }
  }
}
