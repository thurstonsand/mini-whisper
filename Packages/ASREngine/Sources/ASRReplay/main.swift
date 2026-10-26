import ASREngine
import AVFoundation
import Foundation
import ModelLibrary

// Offline replay of a recorded dictation corpus through the real engine. One WAV per stage entry
// in, one JSONL line of `{id, transcript, latencyMs}` out, so a scorer never has to know how the
// engine is loaded and a run stays comparable to the runs before it.

let usage = """
usage: asr-replay --stage <stage.jsonl> --recordings <dir> --output <out.jsonl>
                  [--engine <id>] [--model-root <dir>] [--runtime <out.json>]
                  [--boost-from-wants] [--vocabulary <terms.txt>] [--minimum-similarity <0…1>]

  --stage           corpus stage JSONL; every entry needs an `id`
  --recordings      directory holding <id>.wav at 16 kHz mono
  --output          JSONL destination: {id, transcript, latencyMs, outcome}
  --engine          speech model: \(SpeechModel.catalogue.map(\.id).joined(separator: ", "));
                    defaults to \(SpeechModel.parakeetV2.id). A missing artifact is downloaded first.
  --model-root      pinned model library; defaults to the dev channel's
  --runtime         JSON destination: download and load seconds, peak resident memory
  --boost-from-wants  stage the union of the stage file's `wants` terms as the dictionary
  --vocabulary      stage a newline-separated term list as the dictionary
  --minimum-similarity  override the boost's similarity floor; defaults to the app's 0.65
"""

// MARK: - ReplayError

struct ReplayError: Error, CustomStringConvertible {
  let description: String
}

// MARK: - Options

struct Options {
  // MARK: Lifecycle

  init(arguments: [String]) throws {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      guard argument.hasPrefix("--") else {
        throw ReplayError(description: "unexpected argument '\(argument)'\n\n\(usage)")
      }
      if argument == "--boost-from-wants" {
        flags.insert(argument)
        index += 1
        continue
      }
      guard index + 1 < arguments.count else {
        throw ReplayError(description: "\(argument) needs a value\n\n\(usage)")
      }
      values[argument] = arguments[index + 1]
      index += 2
    }

    func required(_ name: String) throws -> URL {
      guard let value = values[name] else {
        throw ReplayError(description: "missing \(name)\n\n\(usage)")
      }
      return URL(filePath: value)
    }

    stage = try required("--stage")
    recordings = try required("--recordings")
    output = try required("--output")
    let engineID = values["--engine"] ?? SpeechModel.parakeetV2.id
    guard let speechModel = SpeechModel.catalogue.first(where: { $0.id == engineID }) else {
      throw ReplayError(description: "unknown --engine '\(engineID)'\n\n\(usage)")
    }
    self.speechModel = speechModel
    modelRoot = values["--model-root"].map { URL(filePath: $0) } ?? Options.devChannelModelRoot
    runtimeOutput = values["--runtime"].map { URL(filePath: $0) }
    boostsFromWants = flags.contains("--boost-from-wants")
    vocabularyFile = values["--vocabulary"].map { URL(filePath: $0) }
    if let raw = values["--minimum-similarity"] {
      guard let similarity = Float(raw) else {
        throw ReplayError(description: "--minimum-similarity needs a number, got '\(raw)'")
      }
      boostThresholds = RecognitionBoostThresholds(minimumSimilarity: similarity)
    } else {
      boostThresholds = .default
    }
  }

  // MARK: Internal

  /// The dev channel's library, resolved exactly the way `Channel.engineRoot` resolves it. A
  /// candidate installs beside the app's assets there, and the app never offers it.
  static let devChannelModelRoot = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask,
  )[0].appending(path: "MiniWhisper Dev/Engine/pinned-v1", directoryHint: .isDirectory)

  let stage: URL
  let recordings: URL
  let output: URL
  let speechModel: SpeechModel
  let modelRoot: URL
  let runtimeOutput: URL?
  let boostsFromWants: Bool
  let vocabularyFile: URL?
  let boostThresholds: RecognitionBoostThresholds
}

// MARK: - StageEntry

struct StageEntry {
  let id: String
  let wants: [String]
}

func loadStage(_ url: URL) throws -> [StageEntry] {
  let text = try String(contentsOf: url, encoding: .utf8)
  return try text.split(separator: "\n").map { line in
    guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let id = object["id"] as? String
    else {
      throw ReplayError(description: "stage entry without an id: \(line)")
    }
    return StageEntry(id: id, wants: object["wants"] as? [String] ?? [])
  }
}

/// The engine's canonical format is the recorder's too, so a mismatch is a corpus defect rather
/// than something to resample around.
func loadSamples(_ url: URL) throws -> [Float] {
  let file = try AVAudioFile(forReading: url)
  guard file.fileFormat.sampleRate == 16000, file.fileFormat.channelCount == 1 else {
    throw ReplayError(
      description:
      "\(url.lastPathComponent) is \(file.fileFormat.sampleRate) Hz × \(file.fileFormat.channelCount)ch, expected 16 kHz mono",
    )
  }
  let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false,
  )!
  guard let buffer = AVAudioPCMBuffer(
    pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length),
  ) else {
    throw ReplayError(description: "cannot allocate a buffer for \(url.lastPathComponent)")
  }
  try file.read(into: buffer)
  guard let channel = buffer.floatChannelData?[0] else {
    throw ReplayError(description: "\(url.lastPathComponent) decoded without float samples")
  }
  return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

func dictionary(for options: Options, entries: [StageEntry]) throws -> TranscriptionDictionary {
  var terms: [String] = []
  if options.boostsFromWants {
    for entry in entries where !entry.wants.isEmpty {
      for term in entry.wants where !terms.contains(term) {
        terms.append(term)
      }
    }
  }
  if let vocabularyFile = options.vocabularyFile {
    for line in try String(contentsOf: vocabularyFile, encoding: .utf8).split(separator: "\n") {
      let term = line.trimmingCharacters(in: .whitespaces)
      if !term.isEmpty, !terms.contains(term) {
        terms.append(term)
      }
    }
  }
  guard !terms.isEmpty else {
    return .empty
  }
  return TranscriptionDictionary(vocabulary: terms, corrections: [], boostsVocabulary: true)
}

// MARK: - EngineSetup

struct EngineSetup {
  let downloadSeconds: Double?
  let loadSeconds: Double
}

func prepare(_ engine: LocalASREngine, options: Options) async throws -> EngineSetup {
  if let setup = try await follow(engine.prepareInstalled()) {
    return setup
  }
  FileHandle.standardError.write(
    Data("downloading \(options.speechModel.identity) to \(options.modelRoot.path)\n".utf8),
  )
  guard let setup = try await follow(engine.installAndPrepare()) else {
    throw ReplayError(description: "engine setup finished without a model")
  }
  return setup
}

/// Load runs from the first compile to ready, so a download ahead of it is reported apart rather
/// than counted as load. Nil means there is no installed model to load.
func follow(_ updates: AsyncStream<EngineReadiness>) async throws -> EngineSetup? {
  let started = ContinuousClock.now
  var downloaded = false
  var compileStarted: ContinuousClock.Instant?
  for await readiness in updates {
    switch readiness {
    case .modelMissing:
      return nil
    case .downloading:
      downloaded = true
    case .compiling:
      compileStarted = compileStarted ?? .now
    case .prewarming:
      continue
    case .credentialMissing:
      preconditionFailure("the local engine has no key to miss")
    case .ready:
      let loadStarted = compileStarted ?? started
      return EngineSetup(
        downloadSeconds: downloaded ? seconds(loadStarted - started) : nil,
        loadSeconds: seconds(.now - loadStarted),
      )
    case let .failed(message):
      throw ReplayError(description: "engine setup failed: \(message)")
    }
  }
  throw ReplayError(description: "engine never reported readiness")
}

func seconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

/// The speech model's pinned files, as the library's provenance records them.
func installedModelBytes(_ options: Options) throws -> Int {
  try ModelLibrary(root: options.modelRoot).validate([options.speechModel.repository])
}

/// `ru_maxrss` is bytes on Darwin.
func peakResidentBytes() -> Int {
  var usage = rusage()
  getrusage(RUSAGE_SELF, &usage)
  return usage.ru_maxrss
}

func text(of outcome: TranscriptionOutcome) -> (transcript: String, label: String) {
  switch outcome {
  case let .transcript(text):
    (text, "transcript")
  case .tooShort:
    ("", "tooShort")
  case .noSpeech:
    ("", "noSpeech")
  case .engineEmpty:
    ("", "engineEmpty")
  }
}

func run() async throws {
  let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
  let entries = try loadStage(options.stage)
  let staged = try dictionary(for: options, entries: entries)
  FileHandle.standardError.write(
    Data(
      "stage: \(options.stage.lastPathComponent) (\(entries.count) entries); vocabulary: \(staged.vocabulary.count) terms; minSimilarity: \(options.boostThresholds.minimumSimilarity)\n"
        .utf8,
    ),
  )

  let engine = LocalASREngine(
    library: ModelLibrary(root: options.modelRoot), speechModel: options.speechModel,
    boostThresholds: options.boostThresholds,
  )
  let setup = try await prepare(engine, options: options)
  FileHandle.standardError.write(
    Data("\(options.speechModel.id) ready in \(setup.loadSeconds.formatted()) s\n".utf8),
  )

  var lines: [String] = []
  for (index, entry) in entries.enumerated() {
    let recording = options.recordings.appending(path: "\(entry.id).wav")
    let samples = try loadSamples(recording)
    let started = ContinuousClock.now
    let outcome = try await engine.transcribeIgnoringGate(
      samples, sampleRate: 16000, dictionary: staged,
    )
    let elapsed = ContinuousClock.now - started
    let (transcript, label) = text(of: outcome)
    let latencyMilliseconds =
      Double(elapsed.components.seconds) * 1000
        + Double(elapsed.components.attoseconds) / 1e15
    let record: [String: Any] = [
      "id": entry.id, "transcript": transcript,
      "latencyMs": (latencyMilliseconds * 10).rounded() / 10,
      "outcome": label, "audioSeconds": (Double(samples.count) / 16000 * 1000).rounded() / 1000,
    ]
    try lines.append(
      String(
        decoding: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
        as: UTF8.self,
      ),
    )
    FileHandle.standardError.write(
      Data(
        "[\(index + 1)/\(entries.count)] \(entry.id) \(Int(latencyMilliseconds)) ms  \(transcript)\n"
          .utf8,
      ),
    )
  }

  try FileManager.default.createDirectory(
    at: options.output.deletingLastPathComponent(), withIntermediateDirectories: true,
  )
  try (lines.joined(separator: "\n") + "\n").write(
    to: options.output, atomically: true, encoding: .utf8,
  )
  FileHandle.standardError.write(Data("wrote \(options.output.path)\n".utf8))

  if let runtimeOutput = options.runtimeOutput {
    var runtime: [String: Any] = try [
      "engine": options.speechModel.id, "identity": options.speechModel.identity,
      "modelBytes": installedModelBytes(options),
      "stage": options.stage.lastPathComponent, "entries": entries.count,
      "loadSeconds": setup.loadSeconds, "peakResidentBytes": peakResidentBytes(),
    ]
    runtime["downloadSeconds"] = setup.downloadSeconds
    try JSONSerialization.data(withJSONObject: runtime, options: [.prettyPrinted, .sortedKeys])
      .write(to: runtimeOutput, options: .atomic)
  }
}

do {
  try await run()
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
