import FluidAudio
import Foundation

struct HarnessError: Error, CustomStringConvertible { let description: String }

struct Fixture: Decodable {
  let id: String
  let file: String
}

struct TranscriptResult: Encodable {
  let id: String
  let transcript: String
  let milliseconds: Double
  let error: String?
}

@main struct SilenceBakeoffTranscriber {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3 else {
      throw HarnessError(
        description: "usage: SilenceBakeoffTranscriber MODEL_DIR MANIFEST.json OUTPUT.json")
    }

    let modelDirectory = URL(fileURLWithPath: arguments[0])
    let manifestURL = URL(fileURLWithPath: arguments[1])
    let outputURL = URL(fileURLWithPath: arguments[2])
    let root = manifestURL.deletingLastPathComponent()
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: manifestURL))
    let models = try await AsrModels.load(
      from: modelDirectory, version: .v2, encoderPrecision: .int8)
    let manager = AsrManager(
      config: ASRConfig(
        parallelChunkConcurrency: 4, streamingEnabled: false, melChunkContext: true,
        dualDecodeArbitration: false), models: models)

    var results: [TranscriptResult] = []
    for fixture in fixtures {
      let samples = try loadSamples(root.appending(path: fixture.file))
      let start = DispatchTime.now().uptimeNanoseconds
      do {
        var state = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &state)
        results.append(
          TranscriptResult(
            id: fixture.id, transcript: result.text, milliseconds: milliseconds(since: start),
            error: nil))
      } catch {
        results.append(
          TranscriptResult(
            id: fixture.id, transcript: "", milliseconds: milliseconds(since: start),
            error: String(describing: error)))
      }
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(results).write(to: outputURL, options: .atomic)
  }
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

func milliseconds(since start: UInt64) -> Double {
  Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}
