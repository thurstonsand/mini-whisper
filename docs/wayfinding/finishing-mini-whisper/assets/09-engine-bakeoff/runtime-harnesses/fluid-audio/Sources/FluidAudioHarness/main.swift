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
    let reportedProcessingMilliseconds: Double?
    let confidence: Float?
    let wordErrors: Int
    let referenceWords: Int
    let wordErrorRate: Double
}

struct CancellationResult: Encodable {
    let requestDelayMilliseconds: Double
    let outcome: String
    let completionMilliseconds: Double
    let responseMilliseconds: Double?
}

struct ModelDescription: Encodable {
    let checkpoint: String
    let artifactRevision: String
    let encoderPrecision = "int8"
}

struct Result: Encodable {
    let runtime = "FluidAudio"
    let runtimeRevision = "19600a485baa4998812e4654b70d2bab8f2c9949"
    let runtimeVersion = "v0.15.5"
    let backend = "Core ML defaults: ANE-preferred models, CPU preprocessor"
    let model: ModelDescription
    let longFormConfiguration: String
    let coldLoadMilliseconds: Double
    let warmMedianMilliseconds: Double
    let peakResidentBytes: UInt64
    let corpusWordErrors: Int
    let corpusReferenceWords: Int
    let corpusWordErrorRate: Double
    let fixtures: [FixtureResult]
    let cancellation: CancellationResult
}

struct Configuration {
    let modelVersion: AsrModelVersion
    let model: ModelDescription
    let asr: ASRConfig
    let name: String
}

@main
struct FluidAudioHarness {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 6 else {
            throw HarnessError(
                description: "usage: FluidAudioHarness v2|v3 default|no-mel|dual model-folder manifest.json output.json cancel-delay-ms"
            )
        }
        let configuration = try configuration(version: arguments[0], longForm: arguments[1])
        let modelFolder = URL(fileURLWithPath: arguments[2])
        let manifestURL = URL(fileURLWithPath: arguments[3])
        let outputURL = URL(fileURLWithPath: arguments[4])
        guard let cancellationDelay = Double(arguments[5]), cancellationDelay >= 0 else {
            throw HarnessError(description: "invalid cancellation delay \(arguments[5])")
        }
        let fixturesRoot = manifestURL.deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode(
            FixtureManifest.self,
            from: Data(contentsOf: manifestURL)
        ).fixtures
        let loadedFixtures = try fixtures.map {
            ($0, try loadSamples(fixturesRoot.appending(path: $0.filename)))
        }

        let loadStart = DispatchTime.now().uptimeNanoseconds
        let models = try await AsrModels.load(
            from: modelFolder,
            version: configuration.modelVersion,
            encoderPrecision: .int8
        )
        let manager = AsrManager(config: configuration.asr, models: models)
        let coldLoadMilliseconds = millisecondsSince(loadStart)

        let warmup = loadedFixtures.min { $0.0.durationSeconds < $1.0.durationSeconds }!
        var warmupState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
        _ = try await manager.transcribe(warmup.1, decoderState: &warmupState)

        var fixtureResults: [FixtureResult] = []
        var corpusWordErrors = 0
        var corpusReferenceWords = 0
        for (fixture, samples) in loadedFixtures {
            let start = DispatchTime.now().uptimeNanoseconds
            do {
                var decoderState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
                let transcript = try await manager.transcribe(samples, decoderState: &decoderState)
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
                        reportedProcessingMilliseconds: transcript.processingTime * 1_000,
                        confidence: transcript.confidence,
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
                        reportedProcessingMilliseconds: nil,
                        confidence: nil,
                        wordErrors: referenceWords,
                        referenceWords: referenceWords,
                        wordErrorRate: 1
                    )
                )
            }
        }

        let cancellationFixture = loadedFixtures.max { $0.0.durationSeconds < $1.0.durationSeconds }!
        let cancellation = await cancellationProbe(
            manager: manager,
            samples: cancellationFixture.1,
            decoderLayers: models.version.decoderLayers,
            delayMilliseconds: cancellationDelay
        )
        let latencies = fixtureResults.map(\.holdReleaseMilliseconds).sorted()
        let middle = latencies.count / 2
        let median = latencies.count.isMultiple(of: 2)
            ? (latencies[middle - 1] + latencies[middle]) / 2
            : latencies[middle]
        let result = Result(
            model: configuration.model,
            longFormConfiguration: configuration.name,
            coldLoadMilliseconds: coldLoadMilliseconds,
            warmMedianMilliseconds: median,
            peakResidentBytes: peakResidentBytes(),
            corpusWordErrors: corpusWordErrors,
            corpusReferenceWords: corpusReferenceWords,
            corpusWordErrorRate: Double(corpusWordErrors) / Double(corpusReferenceWords),
            fixtures: fixtureResults,
            cancellation: cancellation
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: outputURL, options: .atomic)
        print(
            String(
                format: "FluidAudio %@/%@: cold %.0f ms | warm median %.0f ms | WER %.2f%% | peak %.0f MiB | cancellation %@",
                arguments[0],
                arguments[1],
                coldLoadMilliseconds,
                median,
                result.corpusWordErrorRate * 100,
                Double(result.peakResidentBytes) / 1_048_576,
                cancellation.outcome
            )
        )
    }

    static func configuration(version: String, longForm: String) throws -> Configuration {
        let modelVersion: AsrModelVersion
        let model: ModelDescription
        switch version {
        case "v2":
            modelVersion = .v2
            model = ModelDescription(
                checkpoint: "nvidia/parakeet-tdt-0.6b-v2",
                artifactRevision: "ee09c569f73759e6d44c9bd16766f477b2b36d39"
            )
        case "v3":
            modelVersion = .v3
            model = ModelDescription(
                checkpoint: "nvidia/parakeet-tdt-0.6b-v3",
                artifactRevision: "aed02740059203c4a87495924f685de3722ae9ce"
            )
        default:
            throw HarnessError(description: "model version must be v2 or v3")
        }

        let melChunkContext: Bool
        let dualDecodeArbitration: Bool
        switch longForm {
        case "default":
            melChunkContext = true
            dualDecodeArbitration = false
        case "no-mel":
            melChunkContext = false
            dualDecodeArbitration = false
        case "dual":
            guard version == "v3" else {
                throw HarnessError(description: "dual mode is only supported for v3")
            }
            melChunkContext = false
            dualDecodeArbitration = true
        default:
            throw HarnessError(description: "long-form mode must be default, no-mel, or dual")
        }
        return Configuration(
            modelVersion: modelVersion,
            model: model,
            asr: ASRConfig(
                parallelChunkConcurrency: 4,
                streamingEnabled: false,
                melChunkContext: melChunkContext,
                dualDecodeArbitration: dualDecodeArbitration
            ),
            name: longForm
        )
    }

    static func cancellationProbe(
        manager: AsrManager,
        samples: [Float],
        decoderLayers: Int,
        delayMilliseconds: Double
    ) async -> CancellationResult {
        let start = DispatchTime.now().uptimeNanoseconds
        let task = Task {
            var state = try TdtDecoderState(decoderLayers: decoderLayers)
            return try await manager.transcribe(samples, decoderState: &state)
        }
        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        let requested = DispatchTime.now().uptimeNanoseconds
        task.cancel()
        do {
            _ = try await task.value
            let completion = DispatchTime.now().uptimeNanoseconds
            return CancellationResult(
                requestDelayMilliseconds: milliseconds(from: start, to: requested),
                outcome: "completed-despite-cancel",
                completionMilliseconds: milliseconds(from: start, to: completion),
                responseMilliseconds: milliseconds(from: requested, to: completion)
            )
        } catch is CancellationError {
            let completion = DispatchTime.now().uptimeNanoseconds
            return CancellationResult(
                requestDelayMilliseconds: milliseconds(from: start, to: requested),
                outcome: "aborted",
                completionMilliseconds: milliseconds(from: start, to: completion),
                responseMilliseconds: milliseconds(from: requested, to: completion)
            )
        } catch {
            let completion = DispatchTime.now().uptimeNanoseconds
            return CancellationResult(
                requestDelayMilliseconds: milliseconds(from: start, to: requested),
                outcome: "error: \(error)",
                completionMilliseconds: milliseconds(from: start, to: completion),
                responseMilliseconds: milliseconds(from: requested, to: completion)
            )
        }
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
    milliseconds(from: start, to: DispatchTime.now().uptimeNanoseconds)
}

func milliseconds(from start: UInt64, to end: UInt64) -> Double {
    Double(end - start) / 1_000_000
}

func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
}
