import Foundation
import Testing
@testable import TranscriptCleanup

// MARK: - OpenAICompatibleCleanupTests

struct OpenAICompatibleCleanupTests {
  // MARK: Internal

  @Test func `a completion delivers its shaped content`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion("```\nRun the tests.\n```"),
    ))
    #expect(await client(session: session).clean(request) == .cleaned("Run the tests."))
  }

  @Test func `the request carries the assembled prompt, the model, and the key`() async throws {
    let (session, log) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion("Run the tests."),
    ))
    _ = await client(session: session).clean(request)

    let entry = try #require(log.entries.first)
    #expect(entry.url.absoluteString == "https://gateway.example/v1/chat/completions")
    #expect(entry.method == "POST")
    #expect(entry.headers["Authorization"] == "Bearer sk-test")
    #expect(entry.headers["Content-Type"] == "application/json")

    let body = try #require(JSONSerialization.jsonObject(with: entry.body) as? [String: Any])
    #expect(body["model"] as? String == "gateway-small")
    #expect(body["stream"] as? Bool == false)
    #expect(entry.messages.map(\.role) == ["system", "user"])
    #expect(entry.messages[0].content.hasPrefix(CleanupPrompt.builtIn))
    #expect(entry.messages[1].content == CleanupPrompt.userMessage(request))
  }

  @Test func `a non 2xx status surfaces its code and the gateway's message`() async {
    let body = #"{"error": {"message": "model not found"}}"#
    let (session, _) = StubURLProtocol.session(reply: .response(status: 404, body: body))
    #expect(
      await client(session: session).clean(request)
        == .failed(.httpStatus(code: 404, message: "model not found")),
    )
  }

  @Test func `a status without a parseable body still reports its code`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 502,
      body: "<html>bad gateway</html>",
    ))
    #expect(
      await client(session: session).clean(request)
        == .failed(.httpStatus(code: 502, message: nil)),
    )
  }

  @Test func `an unreachable endpoint is not a timeout`() async {
    let (session, _) = StubURLProtocol.session(reply: .failure(.cannotConnectToHost))
    guard case let .failed(failure) = await client(session: session).clean(request) else {
      Issue.record("expected a failure")
      return
    }
    guard case .unreachable = failure else {
      Issue.record("expected unreachable, got \(failure)")
      return
    }
  }

  @Test func `a timeout reports the budget it exceeded`() async {
    let (session, _) = StubURLProtocol.session(reply: .failure(.timedOut))
    #expect(
      await client(session: session, timeout: 3).clean(request) == .failed(.timedOut(3)),
    )
  }

  @Test func `a body that is not a completion is malformed`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: "not json at all",
    ))
    guard case let .failed(.malformedResponse(message)) = await client(session: session)
      .clean(request)
    else {
      Issue.record("expected a malformed response")
      return
    }
    #expect(!message.isEmpty)
  }

  @Test func `a completion with no choices is malformed, never a fallback`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: #"{"choices": []}"#,
    ))
    #expect(
      await client(session: session).clean(request)
        == .failed(.malformedResponse("completion carried no message content")),
    )
  }

  @Test func `empty content is degenerate`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion("   "),
    ))
    #expect(
      await client(session: session).clean(request) == .failed(.degenerateResponse(.empty)),
    )
  }

  @Test func `an answer instead of an edit is degenerate`() async {
    let answer = String(repeating: "Here is why that happens, in detail. ", count: 30)
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion(answer),
    ))
    guard case let .failed(.degenerateResponse(reason)) = await client(session: session)
      .clean(request)
    else {
      Issue.record("expected a degenerate response")
      return
    }
    guard case .runaway = reason else {
      Issue.record("expected runaway, got \(reason)")
      return
    }
  }

  /// The design's open question: a skip cancels the effect's task, and the client must call that
  /// a cancellation rather than dress it up as a network error the pill would report as a failure.
  @Test func `cancelling the task is a cancellation, not an error`() async {
    let (session, _) = StubURLProtocol.session(reply: .hang)
    let client = client(session: session)
    let pending = Task { await client.clean(request) }

    // The stub answers nothing, so any completion here can only come from the cancellation.
    try? await Task.sleep(for: .milliseconds(50))
    pending.cancel()
    #expect(await pending.value == .cancelled)
  }

  @Test func `a cancelled transport is never mistaken for an unreachable endpoint`() async {
    let (session, _) = StubURLProtocol.session(reply: .failure(.cancelled))
    #expect(await client(session: session).clean(request) == .cancelled)
  }

  @Test func `verify proves the endpoint with a bounded completion`() async throws {
    let (session, log) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion("ready"),
    ))
    #expect(await client(session: session, timeout: 600).verify() == .verified)

    let entry = try #require(log.entries.first)
    #expect(entry.url.absoluteString == "https://gateway.example/v1/chat/completions")
    // A person is waiting on Save, so verify keeps its own short budget.
    #expect(entry.headers["Authorization"] == "Bearer sk-test")
  }

  @Test func `verify grades the round trip, not the model's answer`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(
      status: 200,
      body: completion("   "),
    ))
    #expect(await client(session: session).verify() == .verified)
  }

  @Test func `verify reports the specific failure the pane has to show`() async {
    let body = #"{"error": {"message": "invalid api key"}}"#
    let (session, _) = StubURLProtocol.session(reply: .response(status: 401, body: body))
    #expect(
      await client(session: session).verify()
        == .failed(.httpStatus(code: 401, message: "invalid api key")),
    )
  }

  @Test func `model listing reads the catalogue`() async throws {
    let body = #"{"data": [{"id": "gateway-small"}, {"id": "gateway-large"}]}"#
    let (session, log) = StubURLProtocol.session(reply: .response(status: 200, body: body))
    #expect(await client(session: session).listModels() == .models([
      "gateway-small",
      "gateway-large",
    ]))

    let entry = try #require(log.entries.first)
    #expect(entry.url.absoluteString == "https://gateway.example/v1/models")
    #expect(entry.method == "GET")
  }

  @Test func `a gateway that does not browse is unavailable, not broken`() async {
    let (session, _) = StubURLProtocol.session(reply: .response(status: 404, body: ""))
    #expect(
      await client(session: session).listModels()
        == .unavailable(.httpStatus(code: 404, message: nil)),
    )
  }

  @Test func `a trailing slash on the endpoint composes the same paths`() throws {
    let configuration = try CleanupConfiguration(
      endpoint: #require(URL(string: "https://gateway.example/v1/")), model: "m",
      additionalInstructions: "",
    )
    #expect(configuration.chatCompletionsURL
      .absoluteString == "https://gateway.example/v1/chat/completions")
    #expect(configuration.modelsURL.absoluteString == "https://gateway.example/v1/models")
  }

  @Test func `the timeout defaults to ten seconds`() throws {
    let configuration = try CleanupConfiguration(
      endpoint: #require(URL(string: "https://gateway.example/v1")), model: "m",
      additionalInstructions: "",
    )
    #expect(configuration.timeout == 10)
  }

  // MARK: Private

  private let request = CleanupRequest(
    transcript: "run the tests", focusedTextContext: nil, vocabulary: [], targetBundleID: nil,
  )

  private func client(session: URLSession, timeout: TimeInterval = 10) -> OpenAICompatibleCleanup {
    OpenAICompatibleCleanup(
      configuration: CleanupConfiguration(
        endpoint: URL(string: "https://gateway.example/v1")!, model: "gateway-small",
        timeout: timeout, additionalInstructions: "",
      ), apiKey: "sk-test", session: session,
    )
  }

  private func completion(_ content: String) -> String {
    let payload = ["choices": [["message": ["role": "assistant", "content": content]]]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
  }
}
