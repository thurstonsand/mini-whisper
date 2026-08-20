import CleanupTestSupport
import FieldContext
import Foundation
import TranscriptCleanup

// An end-to-end pass with the real client, the real prompt, the real request on the wire, and
// the real shaping. Against the local mock gateway by default; against a live one when asked.
//
//   swift run cleanup-smoke                          # local mock endpoint
//   swift run cleanup-smoke <base-url> <model>       # a real gateway; key from CLEANUP_APIKEY

let request = CleanupRequest(
  transcript: "um so run swift test dash dash filter cleanup comma then uh report back",
  focusedTextContext: FocusedTextContext(
    role: "AXTextArea", before: "$ ", selected: "", after: "", selectedRange: 2 ..< 2,
    beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
  ),
  vocabulary: ["MiniWhisper", "swift test"], targetBundleID: "com.apple.Terminal",
)

if CommandLine.arguments.count == 3 {
  guard let base = URL(string: CommandLine.arguments[1]) else {
    fatalError("not a URL: \(CommandLine.arguments[1])")
  }
  guard let key = ProcessInfo.processInfo.environment["CLEANUP_APIKEY"] else {
    fatalError("set CLEANUP_APIKEY for a live gateway run")
  }
  let client = OpenAICompatibleCleanup(
    configuration: CleanupConfiguration(
      endpoint: base, model: CommandLine.arguments[2], additionalInstructions: "",
    ),
    apiKey: key, session: URLSession(configuration: .ephemeral),
  )

  let samples: [(label: String, request: CleanupRequest)] = [
    ("disfluent command with spoken symbols", request),
    (
      "a question that must stay a question",
      CleanupRequest(
        transcript: "why does the uh the silence gate reject clips under five hundred milliseconds",
        focusedTextContext: nil, vocabulary: ["Silero"],
        targetBundleID: "com.tinyspeck.slackmacgap",
      ),
    ),
    (
      "self-correction keeps the final wording",
      CleanupRequest(
        transcript: "the timeout defaults to five seconds actually no ten seconds comma configurable in settings",
        focusedTextContext: nil, vocabulary: [], targetBundleID: nil,
      ),
    ),
    (
      "dictionary near-miss must not be forced",
      CleanupRequest(
        transcript: "we should whisper the announcement quietly before mini whisper ships",
        focusedTextContext: nil, vocabulary: ["MiniWhisper"], targetBundleID: nil,
      ),
    ),
  ]

  let clock = ContinuousClock()
  for sample in samples {
    print("=== \(sample.label) ===")
    print("raw:     \(sample.request.transcript)")
    var outcome: CleanupOutcome = .cancelled
    let elapsed = await clock.measure { outcome = await client.clean(sample.request) }
    switch outcome {
    case let .cleaned(text):
      print("cleaned: \(text)")
    case .cancelled:
      print("cancelled")
    case let .failed(failure):
      print("failed:  \(failure.localizedDescription)")
    }
    print("took:    \(elapsed)\n")
  }
  exit(0)
}

let endpoint = MockEndpoint.start()
defer { endpoint.stop() }

let configuration = CleanupConfiguration(
  endpoint: endpoint.baseURL, model: "mock-small", timeout: 10,
  additionalInstructions: "Prefer American spelling.",
)
let client = OpenAICompatibleCleanup(
  configuration: configuration, apiKey: "sk-smoke", session: URLSession(configuration: .ephemeral),
)

print("=== SYSTEM MESSAGE ===")
print(CleanupPrompt.systemMessage(additionalInstructions: configuration.additionalInstructions))
print("\n=== USER MESSAGE ===")
print(CleanupPrompt.userMessage(request))

print("\n=== MOCK GATEWAY REPLY ===")
print(MockEndpoint.wrappedReply)

print("\n=== OUTCOME ===")
switch await client.clean(request) {
case let .cleaned(text):
  print("cleaned: \(text)")
case .cancelled:
  print("cancelled")
case let .failed(failure):
  print("failed: \(failure.localizedDescription)")
}

print("\n=== VERIFY ===")
await print(client.verify())

print("\n=== MODELS ===")
await print(client.listModels())

print("\n=== SKIP (task cancelled mid-flight) ===")
let slowClient = OpenAICompatibleCleanup(
  configuration: CleanupConfiguration(
    endpoint: endpoint.slowBaseURL, model: "mock-small", timeout: 10, additionalInstructions: "",
  ), apiKey: "sk-smoke", session: URLSession(configuration: .ephemeral),
)
let pending = Task { await slowClient.clean(request) }
try await Task.sleep(for: .milliseconds(100))
pending.cancel()
await print(pending.value)
