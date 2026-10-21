import AVFoundation
import Darwin
import FluidAudio
import Foundation

struct ReplayError: Error, CustomStringConvertible {
    let description: String
}

struct Entry: Decodable {
    let id: String
}

struct Stage {
    let name: String
    let recordings: String
    let output: String
}

struct Record: Encodable {
    let id: String
    let transcript: String
    let latencyMs: Double
    let outcome: String
    let audioSeconds: Double
}

func millisecondsSince(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func peakResidentBytes() throws -> Int64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw ReplayError(description: "getrusage failed: \(errno)")
    }
    return Int64(usage.ru_maxrss)
}

func loadSamples(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    guard file.fileFormat.sampleRate == 16000, file.fileFormat.channelCount == 1 else {
        throw ReplayError(description: "\(url.path): expected 16 kHz mono")
    }
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw ReplayError(description: "cannot allocate audio buffer: \(url.path)")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw ReplayError(description: "no float samples: \(url.path)")
    }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        .write(to: url, options: .atomic)
}

@main
struct FluidReplay {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4, ["replay", "load-only"].contains(arguments[0]) else {
            throw ReplayError(description: "usage: FluidReplay replay|load-only MODEL_ROOT CORPUS_ROOT OUTPUT_ROOT")
        }
        let modelRoot = URL(fileURLWithPath: arguments[1])
        let corpusRoot = URL(fileURLWithPath: arguments[2])
        let outputRoot = URL(fileURLWithPath: arguments[3])
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let stages = [
            Stage(name: "stage1-intelligibility", recordings: "stage1-intelligibility-built-in", output: "stage1"),
            Stage(name: "stage1-longform", recordings: "stage1-longform", output: "stage1-longform"),
            Stage(name: "stage2-dictionary", recordings: "stage2-dictionary-built-in", output: "stage2-bare"),
            Stage(name: "stage2-holdout", recordings: "stage2-holdout-built-in", output: "stage2-holdout-bare"),
            Stage(name: "stage3-polish", recordings: "stage3-polish-built-in", output: "stage3-raw")
        ]
        var fixtures: [(stage: Stage, entries: [(id: String, samples: [Float])])] = []
        if arguments[0] == "replay" {
            for stage in stages {
                let text = try String(contentsOf: corpusRoot.appending(path: "\(stage.name).jsonl"), encoding: .utf8)
                let entries = try text.split(separator: "\n").map { line in
                    let entry = try JSONDecoder().decode(Entry.self, from: Data(line.utf8))
                    let samples = try loadSamples(corpusRoot.appending(path: "recordings/\(stage.recordings)/\(entry.id).wav"))
                    return (id: entry.id, samples: samples)
                }
                guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count else {
                    throw ReplayError(description: "empty stage or duplicate ids: \(stage.name)")
                }
                fixtures.append((stage, entries))
            }
        }
        ModelHub.offlineMode = true
        let loadStart = DispatchTime.now().uptimeNanoseconds
        let models = try await AsrModels.load(from: modelRoot, version: .v3, encoderPrecision: .int8)
        let manager = AsrManager(config: ASRConfig(
            parallelChunkConcurrency: 4, streamingEnabled: false,
            melChunkContext: true, dualDecodeArbitration: false
        ), models: models)
        let loadMs = millisecondsSince(loadStart)
        let loadRSS = try peakResidentBytes()
        print("model load \(loadMs) ms; peak RSS \(loadRSS) bytes")
        if arguments[0] == "load-only" {
            try writeJSON(["loadMs": loadMs, "peakResidentBytes": loadRSS],
                          to: outputRoot.appending(path: "reload.json"))
            return
        }
        let warmup = fixtures[0].entries[0]
        let warmupStart = DispatchTime.now().uptimeNanoseconds
        var warmupState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        _ = try await manager.transcribe(warmup.samples, decoderState: &warmupState)
        let warmupMs = millisecondsSince(warmupStart)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for fixture in fixtures {
            var lines: [String] = []
            for entry in fixture.entries {
                let start = DispatchTime.now().uptimeNanoseconds
                var state = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
                let result = try await manager.transcribe(entry.samples, decoderState: &state)
                let elapsedMs = millisecondsSince(start)
                let record = Record(
                    id: entry.id, transcript: result.text,
                    latencyMs: (elapsedMs * 10).rounded() / 10,
                    outcome: result.text.isEmpty ? "engineEmpty" : "transcript",
                    audioSeconds: (Double(entry.samples.count) / 16000 * 1000).rounded() / 1000
                )
                lines.append(String(decoding: try encoder.encode(record), as: UTF8.self))
                print("\(entry.id) \(record.latencyMs) ms \(record.transcript)")
            }
            try (lines.joined(separator: "\n") + "\n").write(
                to: outputRoot.appending(path: "\(fixture.stage.output).jsonl"), atomically: true, encoding: .utf8
            )
        }
        try writeJSON([
            "loadMs": loadMs, "peakResidentBytesAfterLoad": loadRSS,
            "peakResidentBytes": try peakResidentBytes(),
            "warmupId": warmup.id, "warmupMs": warmupMs,
            "entries": fixtures.reduce(0) { $0 + $1.entries.count }
        ], to: outputRoot.appending(path: "runtime.json"))
    }
}
