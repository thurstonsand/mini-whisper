@preconcurrency import AVFoundation
import Darwin
import Foundation
import Voz

struct ReplayError: Error { let message: String }
struct Entry: Decodable { let id: String }
struct Record: Encodable {
    let id: String
    let transcript: String
    let latencyMs: Double
    let outcome: String
    let audioSeconds: Double
}

func milliseconds(_ start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
}
func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
func samples(_ url: URL, rate: Double) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    guard file.fileFormat.sampleRate == 16000, file.fileFormat.channelCount == 1 else {
        throw ReplayError(message: "Expected 16 kHz mono: \(url.path)")
    }
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: source)
    let buffer: AVAudioPCMBuffer
    if rate == 16000 {
        buffer = source
    } else {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: source.format, to: format)!
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(source.frameLength) * rate / 16000) + 32))!
        // AVAudioConverter consumes this input block synchronously within convert.
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let error { throw error }
        guard status != .error else { throw ReplayError(message: "Resampling failed") }
    }
    guard let channel = buffer.floatChannelData?[0] else { throw ReplayError(message: "No float audio") }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 3 || (args.count == 4 && args[3] == "--pad-tail-500ms") || (args.count == 2 && args[1] == "--load-only") else {
        throw ReplayError(message: "usage: VozReplay MODEL_DIRECTORY CORPUS_DIRECTORY OUTPUT_DIRECTORY [--pad-tail-500ms] | MODEL_DIRECTORY --load-only")
    }
    let padsTail = args.count == 4
    log("Powered by Desert Ant Labs")
    let start = ContinuousClock.now
    let voz = try await Voz(directory: args[0])
    let loadMs = milliseconds(start)
    log("loadMs=\(loadMs) sampleRate=\(voz.sampleRate) resamplingRequired=\(voz.sampleRate != 16000)")
    var warmupMs: Double = 0
    if args[1] != "--load-only" {
        let corpus = URL(filePath: args[1])
        let output = URL(filePath: args[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let warmup = try samples(corpus.appending(path: "recordings/stage1-intelligibility-built-in/harvard-01-01.wav"), rate: voz.sampleRate)
        let warmupStart = ContinuousClock.now
        _ = try await voz.transcribe(samples: warmup)
        warmupMs = milliseconds(warmupStart)
        log("excludedWarmupMs=\(warmupMs)")
        let stages = [
            ("stage1-intelligibility", "stage1-intelligibility-built-in", "stage1"),
            ("stage1-longform", "stage1-longform", "stage1-longform"),
            ("stage2-dictionary", "stage2-dictionary-built-in", "stage2-bare"),
            ("stage3-polish", "stage3-polish-built-in", "stage3-raw"),
            ("stage2-holdout", "stage2-holdout-built-in", "stage2-holdout-bare")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for (stage, recordings, name) in stages {
            let entries = try String(contentsOf: corpus.appending(path: "\(stage).jsonl"), encoding: .utf8)
                .split(separator: "\n").map { try JSONDecoder().decode(Entry.self, from: Data($0.utf8)) }
            var lines: [String] = []
            for entry in entries {
                var audio = try samples(corpus.appending(path: "recordings/\(recordings)/\(entry.id).wav"), rate: voz.sampleRate)
                let audioSeconds = Double(audio.count) / voz.sampleRate
                if padsTail { audio += [Float](repeating: 0, count: Int(voz.sampleRate / 2)) }
                let started = ContinuousClock.now
                let result = try await voz.transcribe(samples: audio)
                let latency = milliseconds(started)
                let record = Record(id: entry.id, transcript: result.text,
                    latencyMs: (latency * 10).rounded() / 10,
                    outcome: result.text.isEmpty ? "engineEmpty" : "transcript",
                    audioSeconds: (audioSeconds * 1000).rounded() / 1000)
                lines.append(String(decoding: try encoder.encode(record), as: UTF8.self))
                log("\(entry.id) \(record.latencyMs) ms \(result.text)")
            }
            try (lines.joined(separator: "\n") + "\n").write(to: output.appending(path: "\(name).jsonl"), atomically: true, encoding: .utf8)
        }
    }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw ReplayError(message: "getrusage failed") }
    log("metrics " + String(decoding: try JSONSerialization.data(withJSONObject: [
        "loadMs": loadMs, "excludedWarmupMs": warmupMs,
        "peakRSSBytes": usage.ru_maxrss, "sampleRate": voz.sampleRate,
        "resamplingRequired": voz.sampleRate != 16000
    ], options: [.sortedKeys]), as: UTF8.self))
}

do { try await run() }
catch { log("\(error)"); exit(1) }
