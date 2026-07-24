import Foundation

let prototypeRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let runtimeRevision = "a94e021ef658dc7c788837341a13f6acea3baf3c"
let xcframeworkSHA256 = "b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd"

struct FixtureResult: Codable {
    let id: String
    let durationSeconds: Double
    let reference: String
    let transcript: String?
    let error: String?
    let holdReleaseMilliseconds: Double
    let wordErrors: Int?
    let referenceWords: Int?
    let wordErrorRate: Double?
    let melMilliseconds: Double?
    let encodeMilliseconds: Double?
    let decodeMilliseconds: Double?
}

struct BatchResult: Codable {
    let measuredAt: String
    let runtimeRevision: String
    let xcframeworkSHA256: String
    let model: ModelConfiguration
    let wrapper: WrapperIdentity
    let coldLoadMilliseconds: Double
    let peakResidentBytes: UInt64
    let averageWordErrorRate: Double
    let corpusWordErrors: Int
    let corpusReferenceWords: Int
    let corpusWordErrorRate: Double
    let fixtures: [FixtureResult]
    let cancellation: CancellationOutput
}

struct StreamResult: Codable {
    let measuredAt: String
    let runtimeRevision: String
    let xcframeworkSHA256: String
    let model: ModelConfiguration
    let wrapper: WrapperIdentity
    let coldLoadMilliseconds: Double
    let fixtureID: String
    let reference: String
    let peakResidentBytes: UInt64
    let streaming: StreamingOutput
}

func runBatch(
    modelID: String,
    outputPath: String,
    backend: RequestedBackend = .metal
) throws {
    let configuration = try modelConfiguration(id: modelID)
    guard configuration.mode == "batch" else {
        throw BakeoffError("\(modelID) is not a batch bakeoff model")
    }
    let fixtures = try loadFixtures()
    let loaded = try fixtures.map { ($0, try $0.loadSamples()) }
    let transcriber = try ResidentTranscriber(
        modelURL: configuration.fileURL,
        backend: backend
    )

    let warmup = loaded.min { $0.0.durationSeconds < $1.0.durationSeconds }!
    _ = try transcriber.transcribe(warmup.1)

    var results: [FixtureResult] = []
    for (fixture, samples) in loaded {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let transcript = try transcriber.transcribe(samples)
            let wordErrors = wordErrorStats(
                reference: fixture.reference,
                hypothesis: transcript.text
            )
            results.append(
                FixtureResult(
                    id: fixture.id,
                    durationSeconds: fixture.durationSeconds,
                    reference: fixture.reference,
                    transcript: transcript.text,
                    error: nil,
                    holdReleaseMilliseconds: millisecondsSince(start),
                    wordErrors: wordErrors.errors,
                    referenceWords: wordErrors.referenceWords,
                    wordErrorRate: wordErrors.rate,
                    melMilliseconds: transcript.melMilliseconds,
                    encodeMilliseconds: transcript.encodeMilliseconds,
                    decodeMilliseconds: transcript.decodeMilliseconds
                )
            )
        } catch {
            results.append(
                FixtureResult(
                    id: fixture.id,
                    durationSeconds: fixture.durationSeconds,
                    reference: fixture.reference,
                    transcript: nil,
                    error: String(describing: error),
                    holdReleaseMilliseconds: millisecondsSince(start),
                    wordErrors: nil,
                    referenceWords: nil,
                    wordErrorRate: nil,
                    melMilliseconds: nil,
                    encodeMilliseconds: nil,
                    decodeMilliseconds: nil
                )
            )
        }
    }

    let successfulWERs = results.compactMap(\.wordErrorRate)
    let averageWER = successfulWERs.reduce(0, +) / Double(successfulWERs.count)
    let corpusWordErrors = results.compactMap(\.wordErrors).reduce(0, +)
    let corpusReferenceWords = results.compactMap(\.referenceWords).reduce(0, +)
    let cancellationFixture = loaded.max { $0.0.durationSeconds < $1.0.durationSeconds }!
    let cancellation = transcriber.cancellationProbe(cancellationFixture.1)
    let result = BatchResult(
        measuredAt: ISO8601DateFormatter().string(from: Date()),
        runtimeRevision: runtimeRevision,
        xcframeworkSHA256: xcframeworkSHA256,
        model: configuration,
        wrapper: transcriber.identity,
        coldLoadMilliseconds: transcriber.coldLoadMilliseconds,
        peakResidentBytes: peakResidentBytes(),
        averageWordErrorRate: averageWER,
        corpusWordErrors: corpusWordErrors,
        corpusReferenceWords: corpusReferenceWords,
        corpusWordErrorRate: Double(corpusWordErrors) / Double(corpusReferenceWords),
        fixtures: results,
        cancellation: cancellation
    )
    try writeJSON(result, to: outputPath)
    printBatchSummary(result)
}

func runCancellationSweep(modelID: String, delays: [Double]) throws {
    let configuration = try modelConfiguration(id: modelID)
    let fixture = try loadFixtures().max { $0.durationSeconds < $1.durationSeconds }!
    let samples = try fixture.loadSamples()
    let transcriber = try ResidentTranscriber(modelURL: configuration.fileURL)

    for delay in delays {
        let output = transcriber.cancellationProbe(samples, delayMilliseconds: delay)
        print(
            String(
                format: "request at %.0f ms: %@ after %.1f ms",
                delay,
                output.outcome,
                output.responseMilliseconds ?? output.completionMilliseconds
            )
        )
    }
}

func runStreaming(fixtureID: String, outputPath: String, realtime: Bool) throws {
    let configuration = try modelConfiguration(id: "moonshine-streaming-tiny")
    guard let fixture = try loadFixtures().first(where: { $0.id == fixtureID }) else {
        throw BakeoffError("unknown fixture \(fixtureID)")
    }
    let samples = try fixture.loadSamples()
    let transcriber = try ResidentTranscriber(modelURL: configuration.fileURL)
    let output = try transcriber.stream(samples, realtime: realtime) { event in
        guard realtime else { return }
        let seconds = event.wallMilliseconds / 1_000
        print(
            String(
                format: "[%5.1fs] committed: %@ | tentative: %@",
                seconds,
                event.committed,
                event.tentative
            )
        )
    }
    let result = StreamResult(
        measuredAt: ISO8601DateFormatter().string(from: Date()),
        runtimeRevision: runtimeRevision,
        xcframeworkSHA256: xcframeworkSHA256,
        model: configuration,
        wrapper: transcriber.identity,
        coldLoadMilliseconds: transcriber.coldLoadMilliseconds,
        fixtureID: fixture.id,
        reference: fixture.reference,
        peakResidentBytes: peakResidentBytes(),
        streaming: output
    )
    try writeJSON(result, to: outputPath)
    print("final: \(output.finalText)")
}

func feel(modelID: String, fixtureID: String?) throws {
    let configuration = try modelConfiguration(id: modelID)
    let fixtures = try loadFixtures()
    let selected: [Fixture]
    if let fixtureID {
        guard let fixture = fixtures.first(where: { $0.id == fixtureID }) else {
            throw BakeoffError("unknown fixture \(fixtureID)")
        }
        selected = [fixture]
    } else {
        selected = Array(fixtures.sorted { $0.durationSeconds < $1.durationSeconds }.prefix(2))
    }

    print("Loading \(modelID)…")
    let transcriber = try ResidentTranscriber(modelURL: configuration.fileURL)
    _ = try transcriber.transcribe(try fixtures[0].loadSamples())
    print(String(format: "Resident on Metal. Cold load %.0f ms.\n", transcriber.coldLoadMilliseconds))

    for fixture in selected {
        let samples = try fixture.loadSamples()
        print("HOLD — playing \(fixture.id) (\(String(format: "%.1f", fixture.durationSeconds)) s)")
        try play(fixture.fileURL)
        print("RELEASE → ", terminator: "")
        fflush(stdout)
        let start = DispatchTime.now().uptimeNanoseconds
        let output = try transcriber.transcribe(samples)
        let latency = millisecondsSince(start)
        print(String(format: "text in %.0f ms", latency))
        print("  \(output.text)\n")
    }
}

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let url = prototypeRoot.appending(path: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}

func printBatchSummary(_ result: BatchResult) {
    let latencies = result.fixtures.map(\.holdReleaseMilliseconds).sorted()
    let middle = latencies.count / 2
    let median = latencies.count.isMultiple(of: 2)
        ? (latencies[middle - 1] + latencies[middle]) / 2
        : latencies[middle]
    print("\(result.model.id): \(result.wrapper.architecture)/\(result.wrapper.variant) on \(result.wrapper.backend)")
    print(String(format: "  cold %.0f ms | median warm %.0f ms | mean WER %.1f%% | peak %.0f MiB",
                 result.coldLoadMilliseconds,
                 median,
                 result.averageWordErrorRate * 100,
                 Double(result.peakResidentBytes) / 1_048_576))
    if let response = result.cancellation.responseMilliseconds {
        print(String(format: "  cancellation %@ (%.1f ms response)",
                     result.cancellation.outcome,
                     response))
    } else {
        print("  cancellation \(result.cancellation.outcome)")
    }
}

func play(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = [url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw BakeoffError("afplay exited \(process.terminationStatus)")
    }
}

func usage() -> Never {
    print("""
    Usage:
      engine-bakeoff batch <model-id> <output.json> [--backend metal|cpu]
      engine-bakeoff stream <fixture-id> <output.json> [--realtime]
      engine-bakeoff cancel <model-id> <delay-ms> [delay-ms ...]
      engine-bakeoff feel <model-id> [fixture-id]
    """)
    exit(2)
}

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { usage() }
    switch command {
    case "batch":
        guard arguments.count == 3 || arguments.count == 5 else { usage() }
        let backend: RequestedBackend
        if arguments.count == 5 {
            guard arguments[3] == "--backend",
                  let requested = RequestedBackend(rawValue: arguments[4])
            else { usage() }
            backend = requested
        } else {
            backend = .metal
        }
        try runBatch(modelID: arguments[1], outputPath: arguments[2], backend: backend)
    case "stream":
        guard arguments.count == 3 || arguments.count == 4 else { usage() }
        try runStreaming(
            fixtureID: arguments[1],
            outputPath: arguments[2],
            realtime: arguments.dropFirst(3).first == "--realtime"
        )
    case "cancel":
        guard arguments.count >= 3 else { usage() }
        let delays = try arguments.dropFirst(2).map {
            guard let delay = Double($0), delay >= 0 else {
                throw BakeoffError("invalid cancellation delay \($0)")
            }
            return delay
        }
        try runCancellationSweep(modelID: arguments[1], delays: delays)
    case "feel":
        guard arguments.count == 2 || arguments.count == 3 else { usage() }
        try feel(modelID: arguments[1], fixtureID: arguments.dropFirst(2).first)
    default:
        usage()
    }
}

do {
    try main()
} catch {
    fputs("engine-bakeoff: \(error)\n", stderr)
    exit(1)
}
