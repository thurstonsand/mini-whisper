import CoreML
import Darwin
import FluidAudio
import Foundation

struct HarnessError: Error, CustomStringConvertible {
    let description: String
}

struct FixtureManifest: Decodable {
    let fixtures: [Fixture]
}

struct Fixture: Decodable {
    let id: String
    let sourceFilename: String
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
    let encoderMilliseconds: Double?
    let decoderMilliseconds: Double?
    let wordErrors: Int
    let referenceWords: Int
    let wordErrorRate: Double
}

struct ModelDescription: Encodable {
    let checkpoint = "CohereLabs/cohere-transcribe-03-2026"
    let upstreamLicense = "Apache-2.0"
    let artifact = "FluidInference/cohere-transcribe-03-2026-coreml"
    let artifactRevision = "fccec19ecf93b40969d4888f27e10d714daeb3cf"
    let artifactLicense = "Conflicting metadata: Apache-2.0 card, CC-BY-NC-4.0 README"
    let precision = "INT8 encoder + FP32 static-shape decoder"
}

struct Result: Encodable {
    let runtime = "FluidAudio"
    let runtimeVersion = "v0.15.5"
    let runtimeRevision = "19600a485baa4998812e4654b70d2bab8f2c9949"
    let backend = "Core ML defaults: ANE-preferred"
    let model = ModelDescription()
    let longFormConfiguration = "35-second windows, 5-second overlap, sequential token merge"
    let coldLoadMilliseconds: Double
    let warmMedianMilliseconds: Double
    let warmP95Milliseconds: Double
    let warmWorstMilliseconds: Double
    let peakResidentBytes: UInt64
    let corpusWordErrors: Int
    let corpusReferenceWords: Int
    let corpusWordErrorRate: Double
    let fixtures: [FixtureResult]
}

@main
struct CohereTranscriptionHarness {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4 else {
            throw HarnessError(
                description: "usage: CohereTranscriptionHarness model-folder manifest.json aqua-audio-folder output.json"
            )
        }

        let modelRoot = URL(fileURLWithPath: arguments[0])
        let manifestURL = URL(fileURLWithPath: arguments[1])
        let audioRoot = URL(fileURLWithPath: arguments[2])
        let outputURL = URL(fileURLWithPath: arguments[3])
        let fixtures = try JSONDecoder().decode(
            FixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        ).fixtures
        let converter = AudioConverter()
        let loadedFixtures = try fixtures.map {
            (
                $0,
                try converter.resampleAudioFile(
                    path: audioRoot.appending(path: $0.sourceFilename).path
                )
            )
        }

        let loadStart = DispatchTime.now().uptimeNanoseconds
        let models = try await CoherePipeline.loadModels(
            encoderDir: modelRoot.appending(path: "q8"),
            decoderDir: modelRoot.appending(path: "q8"),
            vocabDir: modelRoot,
            decoderVariant: .v2,
            computeUnits: .all
        )
        let pipeline = CoherePipeline()
        let coldLoadMilliseconds = millisecondsSince(loadStart)

        let warmup = loadedFixtures.min { $0.0.durationSeconds < $1.0.durationSeconds }!
        _ = try await pipeline.transcribeLong(
            audio: warmup.1,
            models: models,
            language: .english
        )

        var fixtureResults: [FixtureResult] = []
        var corpusWordErrors = 0
        var corpusReferenceWords = 0
        for (fixture, samples) in loadedFixtures {
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                let transcript = try await pipeline.transcribeLong(
                    audio: samples,
                    models: models,
                    language: .english
                )
                let latency = millisecondsSince(start)
                let stats = wordErrorStats(reference: fixture.reference, hypothesis: transcript.text)
                corpusWordErrors += stats.errors
                corpusReferenceWords += stats.referenceWords
                fixtureResults.append(
                    FixtureResult(
                        id: fixture.id,
                        durationSeconds: fixture.durationSeconds,
                        reference: fixture.reference,
                        transcript: transcript.text,
                        error: nil,
                        holdReleaseMilliseconds: latency,
                        encoderMilliseconds: transcript.encoderSeconds * 1_000,
                        decoderMilliseconds: transcript.decoderSeconds * 1_000,
                        wordErrors: stats.errors,
                        referenceWords: stats.referenceWords,
                        wordErrorRate: stats.rate
                    )
                )
            } catch {
                let latency = millisecondsSince(start)
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
                        holdReleaseMilliseconds: latency,
                        encoderMilliseconds: nil,
                        decoderMilliseconds: nil,
                        wordErrors: referenceWords,
                        referenceWords: referenceWords,
                        wordErrorRate: 1
                    )
                )
            }
        }

        let latencies = fixtureResults.map(\.holdReleaseMilliseconds).sorted()
        let result = Result(
            coldLoadMilliseconds: coldLoadMilliseconds,
            warmMedianMilliseconds: percentile(latencies, fraction: 0.5),
            warmP95Milliseconds: percentile(latencies, fraction: 0.95),
            warmWorstMilliseconds: latencies.last!,
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
                format: "Cohere local: cold %.0f ms | warm p50 %.0f ms | p95 %.0f ms | worst %.0f ms | WER %.2f%% | peak %.0f MiB",
                result.coldLoadMilliseconds,
                result.warmMedianMilliseconds,
                result.warmP95Milliseconds,
                result.warmWorstMilliseconds,
                result.corpusWordErrorRate * 100,
                Double(result.peakResidentBytes) / 1_048_576
            )
        )
    }
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

func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
    let rank = fraction * Double(sortedValues.count - 1)
    let lower = Int(rank.rounded(.down))
    let upper = Int(rank.rounded(.up))
    if lower == upper { return sortedValues[lower] }
    let weight = rank - Double(lower)
    return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight
}

func peakResidentBytes() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return UInt64(usage.ru_maxrss)
}

func millisecondsSince(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}
