import Foundation
import ModelLibrary
import OSLog

private let hostedLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

// MARK: - HostedASREngine

/// ElevenLabs Scribe v2 behind the same gate the local engine runs. Only audio the gate admits
/// leaves the Mac, as one canonical WAV per dictation, with the dictionary's terms as `keyterms`.
public actor HostedASREngine {
  // MARK: Lifecycle

  /// `apiKey` is read at the moment it is needed, so a key stored or deleted in the pane takes
  /// effect on the next dictation without the engine hearing about it.
  public init(
    library: ModelLibrary, apiKey: @escaping @Sendable () throws -> String?,
    endpoint: URL = HostedASREngine.endpoint, session: URLSession = .shared,
    gateConfiguration: GateConfiguration = .calibrated,
  ) {
    self.library = library
    self.apiKey = apiKey
    self.endpoint = endpoint
    self.session = session
    gate = SpeechGate(library: library, configuration: gateConfiguration)
  }

  // MARK: Public

  public static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
  public nonisolated static let identity = "elevenlabs/scribe_v2"
  public nonisolated static let assets: [ModelAsset] = [.gate]

  /// Proves a key without sending audio. Scribe checks the key, then `model_id`, and only then
  /// asks for a file, so a request without one is refused on `file` exactly when the key and
  /// model would transcribe.
  public static func verify(
    apiKey: String, endpoint: URL = HostedASREngine.endpoint, session: URLSession = .shared,
  ) async throws {
    let request = request(endpoint: endpoint, apiKey: apiKey, wav: nil, dictionary: .empty)
    let (data, response) = try await session.data(for: request)
    try verification(status: (response as? HTTPURLResponse)?.statusCode ?? -1, data: data)
  }

  public nonisolated func prepareInstalled() -> AsyncStream<EngineReadiness> {
    AsyncStream { continuation in
      let task = Task { await self.prepare(installing: false, continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public nonisolated func installAndPrepare() -> AsyncStream<EngineReadiness> {
    AsyncStream { continuation in
      let task = Task { await self.prepare(installing: true, continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func unload() {
    guard !readiness.isSetupInProgress else {
      return
    }
    gate.unload()
    readiness = .modelMissing
  }

  public func submit(
    _ samples: [Float], sampleRate: Double, dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    if let refusal = try await gate.refusal(of: samples, sampleRate: sampleRate) {
      return refusal
    }
    guard let key = try apiKey() else {
      readiness = .credentialMissing
      throw ASREngineError.credentialMissing
    }
    let request = Self.request(
      endpoint: endpoint, apiKey: key,
      wav: WAVEncoder.pcm16(samples, sampleRate: sampleRate), dictionary: dictionary,
    )
    let started = ContinuousClock.now
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    hostedLogger.notice(
      "Scribe answered HTTP \(status, privacy: .public) in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)",
    )
    return try Self.outcome(status: status, data: data, dictionary: dictionary)
  }

  // MARK: Internal

  /// Scribe's own limits on a biasing list.
  static let maximumKeyterms = 1000
  static let maximumKeytermLength = 50

  /// The corpus harness's request, field for field: `model_id`, `language_code`, then one
  /// `keyterms` part per term. A JSON array in a single part is rejected as one over-long term.
  /// Without `wav` it is the key check: the same request, short of the one part Scribe needs.
  static func request(
    endpoint: URL, apiKey: String, wav: Data?, dictionary: TranscriptionDictionary,
  ) -> URLRequest {
    var fields = [("model_id", "scribe_v2"), ("language_code", "eng")]
    fields += keyterms(dictionary).map { ("keyterms", $0) }
    let boundary = UUID().uuidString
    var body = Data()
    for (name, value) in fields {
      body
        .append(
          Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            .utf8),
        )
    }
    if let wav {
      body.append(
        Data(
          "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
            .utf8,
        ),
      )
      body.append(wav)
      body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    var request = URLRequest(url: endpoint, timeoutInterval: 30)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue(
      "multipart/form-data; boundary=\(boundary)",
      forHTTPHeaderField: "Content-Type",
    )
    request.httpBody = body
    return request
  }

  static func outcome(
    status: Int, data: Data, dictionary: TranscriptionDictionary,
  ) throws -> TranscriptionOutcome {
    guard status == 200 else {
      throw failure(status: status, data: data)
    }
    guard let text = try? JSONDecoder().decode(ScribeResponse.self, from: data).text else {
      throw ASREngineError.hostedFailure(status, "unreadable response")
    }
    return TranscriptionOutcomeFinisher.finish(transcript: text, dictionary: dictionary)
  }

  static func verification(status: Int, data: Data) throws {
    let refusal = try? JSONDecoder().decode(ScribeRefusal.self, from: data)
    guard status == 400, refusal?.detail.param == "file" else {
      throw failure(status: status, data: data)
    }
  }

  /// Every vocabulary term Scribe will accept. Unlike the local sidecar, keyterms are not a
  /// matter of the user's choice: they are this engine's way of hearing the dictionary at all.
  static func keyterms(_ dictionary: TranscriptionDictionary) -> [String] {
    Array(
      dictionary.vocabulary
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && $0.count <= maximumKeytermLength }
        .prefix(maximumKeyterms),
    )
  }

  // MARK: Private

  private struct ScribeResponse: Decodable {
    let text: String
  }

  private struct ScribeRefusal: Decodable {
    struct Detail: Decodable {
      let status: String?
      let param: String?
    }

    let detail: Detail
  }

  private let library: ModelLibrary
  private let apiKey: @Sendable () throws -> String?
  private let endpoint: URL
  private let session: URLSession
  private let gate: SpeechGate
  private var readiness: EngineReadiness = .modelMissing

  /// A well-formed key Scribe does not know is a 400, not a 401, so the refusal's own status
  /// decides as much as the HTTP one.
  private static func failure(status: Int, data: Data) -> ASREngineError {
    let refusal = try? JSONDecoder().decode(ScribeRefusal.self, from: data)
    guard status != 401, status != 403, refusal?.detail.status != "invalid_api_key" else {
      return .credentialRejected
    }
    return .hostedFailure(status, String(data: data.prefix(300), encoding: .utf8) ?? "")
  }

  private func prepare(
    installing: Bool, continuation: AsyncStream<EngineReadiness>.Continuation,
  ) async {
    defer { continuation.finish() }
    guard !readiness.isSetupInProgress else {
      continuation.yield(
        installing ? .failed(ASREngineError.setupInProgress.localizedDescription) : readiness,
      )
      return
    }
    let publish = { (readiness: EngineReadiness) in
      self.readiness = readiness
      continuation.yield(readiness)
    }
    do {
      if readiness != .ready || installing {
        if installing {
          publish(.downloading(0))
          try await library.install(Self.assets) { continuation.yield(.downloading($0)) }
        } else {
          for asset in Self.assets {
            _ = try library.validate(asset)
          }
        }
        publish(.prewarming)
        try await gate.load()
      }
      try publish(apiKey() == nil ? .credentialMissing : .ready)
    } catch ModelLibraryError.missing {
      publish(.modelMissing)
    } catch {
      publish(.failed(error.localizedDescription))
    }
  }
}

// MARK: - WAVEncoder

/// 16-bit PCM is what the corpus uploaded and a third the size of the float the app keeps.
enum WAVEncoder {
  static func pcm16(_ samples: [Float], sampleRate: Double) -> Data {
    let rate = UInt32(sampleRate)
    let dataBytes = UInt32(samples.count * 2)
    var data = Data(capacity: 44 + Int(dataBytes))
    func append(_ value: some FixedWidthInteger) {
      withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(Data("RIFF".utf8))
    append(36 + dataBytes)
    data.append(Data("WAVEfmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(rate)
    append(rate * 2)
    append(UInt16(2))
    append(UInt16(16))
    data.append(Data("data".utf8))
    append(dataBytes)
    for sample in samples {
      append(Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded()))
    }
    return data
  }
}
