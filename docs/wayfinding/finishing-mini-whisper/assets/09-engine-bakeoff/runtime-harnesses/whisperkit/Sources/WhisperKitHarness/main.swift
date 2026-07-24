import Darwin
import Foundation
import WhisperKit

struct HarnessError: Error, CustomStringConvertible {
    let description: String
}

struct FixtureManifest: Decodable {
    let fixtures: [Fixture]
}

struct Fixture: Decodable {
    let id: String
    let filename: String
    let durationSeconds: Double
    let reference: String
}

struct FixtureResult: Encodable {
    let id: String
    let durationSeconds: Double
    let reference: String
    let transcript: String
    let error: String?
    let holdReleaseMilliseconds: Double
    let wordErrors: Int
    let referenceWords: Int
    let wordErrorRate: Double
}

struct ModelDescription: Encodable {
    let checkpoint = "openai/whisper-small.en"
    let artifact = "argmaxinc/whisperkit-coreml/openai_whisper-small.en_217MB"
    let artifactRevision = "97a5bf9bbc74c7d9c12c755d04dea59e672e3808"
    let modelBytes = 217_878_408
    let tokenizerRevision = "e8727524f962ee844a7319d92be39ac1bd25655a"
}

struct Result: Encodable {
    let runtime = "WhisperKit"
    let runtimeRevision = "25c62997041c134b03ca82731ce2f6fd2cae1eb9"
    let runtimeVersion = "v1.0.0"
    let backend = "Core ML defaults: ANE-preferred encoder/decoder, GPU-eligible mel"
    let model = ModelDescription()
    let coldLoadMilliseconds: Double
    let warmMedianMilliseconds: Double
    let peakResidentBytes: UInt64
    let corpusWordErrors: Int
    let corpusReferenceWords: Int
    let corpusWordErrorRate: Double
    let fixtures: [FixtureResult]
}

@main
struct WhisperKitHarness {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4 else {
            throw HarnessError(
                description: "usage: WhisperKitHarness model-folder tokenizer-folder manifest.json output.json"
            )
        }
        let modelFolder = arguments[0]
        let tokenizerFolder = URL(fileURLWithPath: arguments[1])
        let manifestURL = URL(fileURLWithPath: arguments[2])
        let outputURL = URL(fileURLWithPath: arguments[3])
        let fixturesRoot = manifestURL.deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode(
            FixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        ).fixtures

        let loadStart = DispatchTime.now().uptimeNanoseconds
        let engine = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: modelFolder,
                tokenizerFolder: tokenizerFolder,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
        )
        let coldLoadMilliseconds = millisecondsSince(loadStart)

        let warmup = fixtures.min { $0.durationSeconds < $1.durationSeconds }!
        _ = try await transcribe(
            engine: engine,
            samples: loadSamples(fixturesRoot.appending(path: warmup.filename))
        )

        var fixtureResults: [FixtureResult] = []
        var corpusWordErrors = 0
        var corpusReferenceWords = 0
        for fixture in fixtures {
            let samples = try loadSamples(fixturesRoot.appending(path: fixture.filename))
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                let transcript = try await transcribe(engine: engine, samples: samples)
                let latency = millisecondsSince(start)
                let stats = wordErrorStats(reference: fixture.reference, hypothesis: transcript)
                corpusWordErrors += stats.errors
                corpusReferenceWords += stats.referenceWords
                fixtureResults.append(
                    FixtureResult(
                        id: fixture.id,
                        durationSeconds: fixture.durationSeconds,
                        reference: fixture.reference,
                        transcript: transcript,
                        error: nil,
                        holdReleaseMilliseconds: latency,
                        wordErrors: stats.errors,
                        referenceWords: stats.referenceWords,
                        wordErrorRate: stats.rate
                    )
                )
            } catch {
                let referenceWords = normalizedWords(fixture.reference).count
                corpusWordErrors += referenceWords
                corpusReferenceWords += referenceWords
                fixtureResults.append(
                    FixtureResult(
                        id: fixture.id,
                        durationSeconds: fixture.durationSeconds,
                        reference: fixture.reference,
                        transcript: "",
                        error: String(describing: error),
                        holdReleaseMilliseconds: millisecondsSince(start),
                        wordErrors: referenceWords,
                        referenceWords: referenceWords,
                        wordErrorRate: 1
                    )
                )
            }
        }

        let latencies = fixtureResults.map(\.holdReleaseMilliseconds).sorted()
        let middle = latencies.count / 2
        let median = latencies.count.isMultiple(of: 2)
            ? (latencies[middle - 1] + latencies[middle]) / 2
            : latencies[middle]
        let result = Result(
            coldLoadMilliseconds: coldLoadMilliseconds,
            warmMedianMilliseconds: median,
            peakResidentBytes: peakResidentBytes(),
            corpusWordErrors: corpusWordErrors,
            corpusReferenceWords: corpusReferenceWords,
            corpusWordErrorRate: Double(corpusWordErrors) / Double(corpusReferenceWords),
            fixtures: fixtureResults
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: outputURL, options: .atomic)
        print(
            String(
                format: "WhisperKit: cold %.0f ms | warm median %.0f ms | WER %.2f%% | peak %.0f MiB",
                coldLoadMilliseconds,
                median,
                result.corpusWordErrorRate * 100,
                Double(result.peakResidentBytes) / 1_048_576
            )
        )
    }

    static func transcribe(engine: WhisperKit, samples: [Float]) async throws -> String {
        let results = try await engine.transcribe(audioArray: samples)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func loadSamples(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard data.count >= 44,
          String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
          String(bytes: data[8..<12], encoding: .ascii) == "WAVE"
    else {
        throw HarnessError(description: "\(url.lastPathComponent) is not RIFF WAVE")
    }

    var offset = 12
    var sampleData: Range<Int>?
    while offset + 8 <= data.count {
        let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
        let size = Int(littleEndianUInt32(data, at: offset + 4))
        let contentStart = offset + 8
        let contentEnd = min(contentStart + size, data.count)
        if id == "data" {
            sampleData = contentStart..<contentEnd
        }
        offset = contentStart + size + (size & 1)
    }
    guard let sampleData else {
        throw HarnessError(description: "\(url.lastPathComponent) has no data chunk")
    }

    var samples: [Float] = []
    samples.reserveCapacity(sampleData.count / 2)
    var sampleOffset = sampleData.lowerBound
    while sampleOffset + 1 < sampleData.upperBound {
        let raw = UInt16(data[sampleOffset]) | UInt16(data[sampleOffset + 1]) << 8
        samples.append(Float(Int16(bitPattern: raw)) / 32_768)
        sampleOffset += 2
    }
    return samples
}

func wordErrorStats(reference: String, hypothesis: String) -> (errors: Int, referenceWords: Int, rate: Double) {
    let referenceWords = normalizedWords(reference)
    let hypothesisWords = normalizedWords(hypothesis)
    var previous = Array(0...hypothesisWords.count)
    for (referenceIndex, referenceWord) in referenceWords.enumerated() {
        var current = [referenceIndex + 1]
        for (hypothesisIndex, hypothesisWord) in hypothesisWords.enumerated() {
            current.append(
                min(
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex + 1] + 1,
                    previous[hypothesisIndex] + (referenceWord == hypothesisWord ? 0 : 1)
                )
            )
        }
        previous = current
    }
    let errors = previous.last!
    return (errors, referenceWords.count, Double(errors) / Double(referenceWords.count))
}

func normalizedWords(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

func peakResidentBytes() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return UInt64(usage.ru_maxrss)
}

func millisecondsSince(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
}
