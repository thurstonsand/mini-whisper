@testable import ASREngine
import Foundation
import ModelLibrary
import Testing

// MARK: - HostedRequestTests

struct HostedRequestTests {
  // MARK: Internal

  @Test func `the request carries the corpus fields and one keyterms part per term`() throws {
    let dictionary = TranscriptionDictionary(
      vocabulary: ["MiniWhisper", "  TCA ", "", String(repeating: "x", count: 51)],
      corrections: [], boostsVocabulary: false,
    )
    let request = HostedASREngine.request(
      endpoint: HostedASREngine.endpoint, apiKey: "xi-key", wav: Data("RIFF".utf8),
      dictionary: dictionary,
    )
    let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "xi-api-key") == "xi-key")
    #expect(parts(named: "model_id", in: body) == ["scribe_v2"])
    #expect(parts(named: "language_code", in: body) == ["eng"])
    // The sidecar's switch has no say here: keyterms are how this engine hears the dictionary.
    #expect(parts(named: "keyterms", in: body) == ["MiniWhisper", "TCA"])
    #expect(body.contains("filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"))
  }

  @Test func `a key check is the same request without the audio`() throws {
    let request = HostedASREngine.request(
      endpoint: HostedASREngine.endpoint, apiKey: "xi-key", wav: nil, dictionary: .empty,
    )
    let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

    #expect(request.value(forHTTPHeaderField: "xi-api-key") == "xi-key")
    #expect(parts(named: "model_id", in: body) == ["scribe_v2"])
    #expect(!body.contains("name=\"file\""))
    #expect(body.hasSuffix("--\r\n"))
  }

  @Test func `a list longer than Scribe allows is cut at its limit`() {
    let vocabulary = (0 ..< 1200).map { "term\($0)" }
    let terms = HostedASREngine.keyterms(
      TranscriptionDictionary(vocabulary: vocabulary, corrections: []),
    )
    #expect(terms.count == 1000)
    #expect(terms.last == "term999")
  }

  @Test func `samples become 16-bit mono PCM at the canonical rate`() {
    let wav = WAVEncoder.pcm16([0, 1, -1, 2], sampleRate: 16000)

    #expect(wav.count == 44 + 8)
    #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
    #expect(wav[24 ..< 28].elementsEqual([0x80, 0x3E, 0x00, 0x00]))
    #expect(wav.suffix(8).elementsEqual([0x00, 0x00, 0xFF, 0x7F, 0x01, 0x80, 0xFF, 0x7F]))
  }

  // MARK: Private

  private func parts(named name: String, in body: String) -> [String] {
    body.components(separatedBy: "name=\"\(name)\"\r\n\r\n").dropFirst().map {
      String($0.prefix { $0 != "\r\n" })
    }
  }
}

// MARK: - HostedResponseTests

struct HostedResponseTests {
  @Test func `a transcript is corrected like any engine's`() throws {
    let dictionary = TranscriptionDictionary(
      vocabulary: [], corrections: [TranscriptionCorrection(
        misspelling: "mini whisper",
        text: "MiniWhisper",
      )],
    )
    let outcome = try HostedASREngine.outcome(
      status: 200, data: Data(#"{"text":" mini whisper works ","language_code":"eng"}"#.utf8),
      dictionary: dictionary,
    )
    #expect(outcome == .transcript("MiniWhisper works"))
  }

  @Test(arguments: [401, 403]) func `a refused key is named as such`(status: Int) {
    #expect(throws: ASREngineError.credentialRejected) {
      try HostedASREngine.outcome(status: status, data: Data(), dictionary: .empty)
    }
  }

  @Test func `Scribe asking for the audio means the key and model would transcribe`() throws {
    let body = #"{"detail":{"status":"invalid_parameters","param":"file","message":"Must provide either file or a URL parameter."}}"#
    try HostedASREngine.verification(status: 400, data: Data(body.utf8))
  }

  @Test func `a refused model is not mistaken for a working key`() {
    let body = #"{"detail":{"status":"invalid_model_id","param":"model_id","message":"'scribe_v2' is not a valid model_id."}}"#
    #expect(throws: ASREngineError.hostedFailure(400, body)) {
      try HostedASREngine.verification(status: 400, data: Data(body.utf8))
    }
  }

  @Test(arguments: [400, 401, 403]) func `a key check names a refused key`(status: Int) {
    let body = #"{"detail":{"status":"invalid_api_key","param":"api_key"}}"#
    #expect(throws: ASREngineError.credentialRejected) {
      try HostedASREngine.verification(status: status, data: Data(body.utf8))
    }
  }

  /// Opt-in by a real key, because the check rests on the order Scribe validates in.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["ELEVENLABS_APIKEY"] != nil))
  func `Scribe proves a real key and refuses a made-up one`() async throws {
    let key = try #require(ProcessInfo.processInfo.environment["ELEVENLABS_APIKEY"])
    try await HostedASREngine.verify(apiKey: key)
    await #expect(throws: ASREngineError.credentialRejected) {
      try await HostedASREngine.verify(apiKey: "sk_" + String(repeating: "0", count: 48))
    }
  }

  @Test func `any other failure keeps the service's own words`() {
    #expect(throws: ASREngineError.hostedFailure(500, "overloaded")) {
      try HostedASREngine.outcome(status: 500, data: Data("overloaded".utf8), dictionary: .empty)
    }
  }
}

// MARK: - HostedReadinessTests

struct HostedReadinessTests {
  @Test func `without the gate installed the engine reads missing`() async {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = HostedASREngine(library: ModelLibrary(root: root), apiKey: { "key" })
    var readiness: [EngineReadiness] = []
    for await update in engine.prepareInstalled() {
      readiness.append(update)
    }
    #expect(readiness == [.modelMissing])
  }

  @Test(.enabled(if: RealAssetFixture.isAvailable))
  func `an installed gate without a key reads credential missing`() async throws {
    let fixture = try #require(RealAssetFixture.resolve())
    let engine = HostedASREngine(library: ModelLibrary(root: fixture.modelRoot), apiKey: { nil })
    var last: EngineReadiness?
    for await update in engine.prepareInstalled() {
      last = update
    }
    #expect(last == .credentialMissing)
  }

  /// The one test that reaches ElevenLabs, opt-in by a real key. It proves the request the app
  /// builds is one Scribe answers, and that the gate admits a real recording on the way.
  @Test(.enabled(if: RealAssetFixture.isAvailable && ProcessInfo.processInfo
      .environment["ELEVENLABS_APIKEY"] != nil))
  func `a real recording is transcribed by Scribe`() async throws {
    let fixture = try #require(RealAssetFixture.resolve())
    let key = try #require(ProcessInfo.processInfo.environment["ELEVENLABS_APIKEY"])
    let engine = HostedASREngine(library: ModelLibrary(root: fixture.modelRoot), apiKey: { key })
    var last: EngineReadiness?
    for await update in engine.prepareInstalled() {
      last = update
    }
    #expect(last == .ready)

    let samples = try pcm16Samples(from: fixture.audio)
    let started = ContinuousClock.now
    let outcome = try await engine.submit(
      samples, sampleRate: 16000,
      dictionary: TranscriptionDictionary(vocabulary: ["MiniWhisper"], corrections: []),
    )
    let elapsed = ContinuousClock.now - started
    guard case let .transcript(text) = outcome else {
      Issue.record("Scribe returned \(outcome)")
      return
    }
    print("SCRIBE \(elapsed): \(text)")
    #expect(!text.isEmpty)
  }
}
