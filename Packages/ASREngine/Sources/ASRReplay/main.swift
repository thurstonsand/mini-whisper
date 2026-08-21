import ASREngine
import AVFoundation
import Foundation

// Offline replay of a recorded dictation corpus through the real engine. One WAV per stage entry
// in, one JSONL line of `{id, transcript, latencyMs}` out, so a scorer never has to know how the
// engine is loaded and a run stays comparable to the runs before it.

let usage = """
usage: asr-replay --stage <stage.jsonl> --recordings <dir> --output <out.jsonl>
                  [--model-root <dir>] [--boost-from-wants] [--vocabulary <terms.txt>]
                  [--minimum-similarity <0…1>]

  --stage           corpus stage JSONL; every entry needs an `id`
  --recordings      directory holding <id>.wav at 16 kHz mono
  --output          JSONL destination: {id, transcript, latencyMs, outcome}
  --model-root      pinned model artifact; defaults to the dev channel's
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
    modelRoot = values["--model-root"].map { URL(filePath: $0) } ?? Options.devChannelModelRoot
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

  /// The dev channel's artifact, resolved exactly the way `Channel.engineRoot` resolves it.
  static let devChannelModelRoot = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask,
  )[0].appending(path: "MiniWhisper Dev/Engine/pinned-v1", directoryHint: .isDirectory)

  let stage: URL
  let recordings: URL
  let output: URL
  let modelRoot: URL
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

func prepare(_ engine: LocalASREngine) async throws {
  for await readiness in engine.prepareInstalled() {
    switch readiness {
    case .ready:
      return
    case .modelMissing:
      throw ReplayError(description: "no pinned model artifact; run the app's setup first")
    case let .failed(message):
      throw ReplayError(description: "engine setup failed: \(message)")
    case .downloading,
         .compiling,
         .prewarming:
      continue
    }
  }
  throw ReplayError(description: "engine never reported readiness")
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
    modelRoot: options.modelRoot, boostThresholds: options.boostThresholds,
  )
  try await prepare(engine)

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
}

do {
  try await run()
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
