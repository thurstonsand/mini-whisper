import ASREngine
import CoreML
import FluidAudio
import Foundation

private let thresholds: [Float] = [0.35, 0.4, 0.45, 0.5, 0.55, 0.65, 0.75, 0.85, 0.9]
private let minimumSpeechDurations: [TimeInterval] = [0, 0.15, 0.25, 0.5]

struct HarnessError: Error, CustomStringConvertible { let description: String }

struct Fixture: Decodable {
  let id: String
  let file: String
}

struct Decision: Encodable {
  let threshold: Float
  let minimumSpeechMilliseconds: Int
  let accepts: Bool
}

struct FixtureResult: Encodable {
  let id: String
  let originalSampleCount: Int
  let paddedSampleCount: Int
  let modelMilliseconds: Double
  let wallMilliseconds: Double
  let probabilities: [Float]
  let decisions: [Decision]
}

@main struct SilenceBakeoffVad {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3 else {
      throw HarnessError(
        description: "usage: SilenceBakeoffVad MODEL_BASE_DIR MANIFEST.json OUTPUT.json")
    }

    let modelBaseDirectory = URL(fileURLWithPath: arguments[0])
    let manifestURL = URL(fileURLWithPath: arguments[1])
    let outputURL = URL(fileURLWithPath: arguments[2])
    let root = manifestURL.deletingLastPathComponent()
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifestURL))
    let manager = try await VadManager(
      config: VadConfig(
        defaultThreshold: GateConfiguration.calibrated.threshold, computeUnits: .cpuOnly),
      modelDirectory: modelBaseDirectory)

    var output: [FixtureResult] = []
    for fixture in fixtures {
      let samples = try loadSamples(root.appending(path: fixture.file))
      let paddedSamples = GateFraming.zeroPaddedCopy(of: samples)
      let start = ContinuousClock.now
      let results = try await manager.process(paddedSamples)
      let wallMilliseconds = milliseconds(start.duration(to: .now))
      let decisions = await decisions(
        manager: manager, results: results, sampleCount: samples.count)
      output.append(
        FixtureResult(
          id: fixture.id, originalSampleCount: samples.count,
          paddedSampleCount: paddedSamples.count,
          modelMilliseconds: results.reduce(0) { $0 + $1.processingTime * 1_000 },
          wallMilliseconds: wallMilliseconds, probabilities: results.map(\.probability),
          decisions: decisions))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(output).write(to: outputURL, options: .atomic)
  }
}

func decisions(manager: VadManager, results: [VadResult], sampleCount: Int) async -> [Decision] {
  var decisions: [Decision] = []
  for threshold in thresholds {
    for minimumSpeechDuration in minimumSpeechDurations {
      let gateConfiguration = GateConfiguration(
        threshold: threshold, minimumSpeechDuration: minimumSpeechDuration)
      let segments = await manager.segmentSpeech(
        from: results, totalSamples: sampleCount,
        config: gateConfiguration.segmentationConfiguration)
      decisions.append(
        Decision(
          threshold: threshold, minimumSpeechMilliseconds: Int(minimumSpeechDuration * 1_000),
          accepts: !segments.isEmpty))
    }
  }
  return decisions
}

func loadSamples(_ url: URL) throws -> [Float] {
  let data = try Data(contentsOf: url)
  guard data.count >= 44, String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
    String(bytes: data[8..<12], encoding: .ascii) == "WAVE"
  else { throw HarnessError(description: "\(url.lastPathComponent) is not RIFF WAVE") }

  var offset = 12
  var format: (audioFormat: UInt16, channels: UInt16, sampleRate: UInt32, bits: UInt16)?
  var sampleData: Range<Int>?
  while offset + 8 <= data.count {
    let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
    let size = Int(uint32(data, at: offset + 4))
    let start = offset + 8
    let end = min(start + size, data.count)
    if id == "fmt ", end - start >= 16 {
      format = (
        uint16(data, at: start), uint16(data, at: start + 2), uint32(data, at: start + 4),
        uint16(data, at: start + 14)
      )
    } else if id == "data" {
      sampleData = start..<end
    }
    offset = start + size + (size & 1)
  }
  guard let format, format == (1, 1, 16_000, 16), let sampleData else {
    throw HarnessError(description: "\(url.lastPathComponent) must be mono 16 kHz PCM16")
  }

  return stride(from: sampleData.lowerBound, to: sampleData.upperBound - 1, by: 2).map {
    Float(Int16(bitPattern: uint16(data, at: $0))) / 32_768
  }
}

func uint16(_ data: Data, at offset: Int) -> UInt16 {
  UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

func uint32(_ data: Data, at offset: Int) -> UInt32 {
  UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(
    data[offset + 3]) << 24
}

func milliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds)
    / 1_000_000_000_000_000
}
