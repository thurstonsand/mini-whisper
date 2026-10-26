import Foundation

// MARK: - OpenAICompatibleCleanup

/// The cleanup pass as one seam: prompt in, conformed text or a typed failure out. It never falls
/// back to the raw transcript — the caller owns that decision, and a client that quietly returned
/// the input would make a failed cleanup indistinguishable from a cleanup that changed nothing.
public struct OpenAICompatibleCleanup: Sendable {
  // MARK: Lifecycle

  /// A nil key sends no `Authorization` header: a local server such as Ollama asks for none.
  public init(configuration: CleanupConfiguration, apiKey: String?, session: URLSession = .shared) {
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

  /// Proves endpoint, key, and model together, for free when the model list can: it names the
  /// model, and the endpoint refuses to list without the key. Anything less — no list, a name
  /// missing from it that may still be an alias, a list anyone can read — falls back to the
  /// smallest completion, which spends tokens only when it succeeds.
  public func verify() async -> VerificationOutcome {
    switch await listModels() {
    case .cancelled:
      return .cancelled
    case let .unavailable(failure):
      switch failure {
      case .unreachable,
           .timedOut:
        return .failed(failure)
      default:
        break
      }
    case let .models(models):
      guard models.contains(configuration.model) else {
        break
      }
      guard apiKey != nil else {
        return .verified
      }
      let anonymous = OpenAICompatibleCleanup(
        configuration: configuration, apiKey: nil, session: session,
      )
      switch await anonymous.listModels() {
      case .cancelled:
        return .cancelled
      case .unavailable(.httpStatus):
        return .verified
      case .models,
           .unavailable:
        break
      }
    }
    return await verifyByCompletion()
  }

  public func listModels() async -> ModelListing {
    var request = URLRequest(url: configuration.modelsURL)
    request.httpMethod = "GET"
    request.timeoutInterval = CleanupConfiguration.verificationTimeout
    if let apiKey {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    // Anthropic answers this path from its own API, which refuses a request without a version.
    // Every other endpoint ignores a header it does not know.
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    switch await send(request, timeout: CleanupConfiguration.verificationTimeout) {
    case let .succeeded(data):
      do {
        let listing = try JSONDecoder().decode(ModelsResponse.self, from: data)
        // Google lists `models/gemini-…` but answers to the bare name, the one people type.
        return .models(listing.data.map {
          $0.id.hasPrefix("models/") ? String($0.id.dropFirst("models/".count)) : $0.id
        })
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
  private let apiKey: String?
  private let session: URLSession

  /// Google wraps its OpenAI-compatible errors in a one-element array.
  private static func errorMessage(in data: Data) -> String? {
    let decoder = JSONDecoder()
    guard let response = (try? decoder.decode(ErrorResponse.self, from: data))
      ?? (try? decoder.decode([ErrorResponse].self, from: data))?.first,
      let message = response.error.message, !message.isEmpty
    else {
      return nil
    }
    return message
  }

  /// The smallest completion that can fail for endpoint, key, and model separately. What comes
  /// back is irrelevant — that it came back is the point, and grading a micro-completion's text
  /// would invent a failure the pane could not explain.
  private func verifyByCompletion() async -> VerificationOutcome {
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

  private func completion(
    messages: [ChatMessage], timeout: TimeInterval,
  ) async -> Transport<String> {
    var request = URLRequest(url: configuration.chatCompletionsURL)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
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
