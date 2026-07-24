import Foundation
import TranscribeCpp

struct WrapperIdentity: Codable {
    let runtimeVersion: String
    let runtimeCommit: String
    let architecture: String
    let variant: String
    let backend: String
    let backendDevice: String
    let nativeSampleRate: Int32
    let supportsCancellation: Bool
    let supportsStreaming: Bool
}

struct TranscriptionOutput {
    let text: String
    let melMilliseconds: Double
    let encodeMilliseconds: Double
    let decodeMilliseconds: Double
}

struct CancellationOutput: Codable {
    let outcome: String
    let requestedAtMilliseconds: Double?
    let completionMilliseconds: Double
    let responseMilliseconds: Double?
    let partialText: String?
}

private final class CancellationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var timestamp: UInt64?

    func fire(_ token: CancellationToken) {
        lock.lock()
        timestamp = DispatchTime.now().uptimeNanoseconds
        lock.unlock()
        token.cancel()
    }

    func firedAt() -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return timestamp
    }
}

struct StreamingEvent: Codable {
    let wallMilliseconds: Double
    let inputReceivedMilliseconds: Int64
    let audioCommittedMilliseconds: Int64
    let committed: String
    let tentative: String
}

struct StreamingOutput: Codable {
    let finalText: String
    let events: [StreamingEvent]
}

enum RequestedBackend: String {
    case metal
    case cpu

    var transcribeBackend: Backend {
        switch self {
        case .metal: .metal
        case .cpu: .cpu
        }
    }
}

final class ResidentTranscriber {
    let identity: WrapperIdentity
    let coldLoadMilliseconds: Double

    private let model: Model
    private let session: Session

    init(modelURL: URL, backend requestedBackend: RequestedBackend = .metal) throws {
        Transcribe.disableLogging()
        guard Transcribe.backendAvailable(requestedBackend.transcribeBackend) else {
            throw BakeoffError("the pinned XCFramework does not expose \(requestedBackend.rawValue)")
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let model = try Model(
            path: modelURL.path,
            options: ModelOptions(backend: requestedBackend.transcribeBackend)
        )
        let session = try model.session()
        let end = DispatchTime.now().uptimeNanoseconds

        let device = try model.device
        guard device.kind == requestedBackend.rawValue else {
            throw BakeoffError(
                "requested \(requestedBackend.rawValue) but runtime selected \(device.kind)/\(model.backend)"
            )
        }

        self.model = model
        self.session = session
        coldLoadMilliseconds = milliseconds(from: start, to: end)
        let capabilities = model.capabilities
        identity = WrapperIdentity(
            runtimeVersion: Transcribe.version(),
            runtimeCommit: Transcribe.versionCommit(),
            architecture: model.arch,
            variant: model.variant,
            backend: device.kind,
            backendDevice: "\(model.backend): \(device.description)",
            nativeSampleRate: capabilities.nativeSampleRate,
            supportsCancellation: model.supports(.cancellation),
            supportsStreaming: capabilities.supportsStreaming
        )
    }

    func transcribe(_ samples: [Float]) throws -> TranscriptionOutput {
        let transcript = try session.run(samples)
        return TranscriptionOutput(
            text: transcript.text,
            melMilliseconds: Double(transcript.timings.melMs),
            encodeMilliseconds: Double(transcript.timings.encodeMs),
            decodeMilliseconds: Double(transcript.timings.decodeMs)
        )
    }

    func cancellationProbe(_ samples: [Float], delayMilliseconds: Double = 10) -> CancellationOutput {
        let token = CancellationToken()
        session.setCancellationToken(token)
        defer { session.clearCancellationToken() }

        let request = CancellationRequest()
        let start = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.global().asyncAfter(deadline: .now() + delayMilliseconds / 1_000) {
            request.fire(token)
        }

        do {
            let transcript = try session.run(samples)
            let completionTimestamp = DispatchTime.now().uptimeNanoseconds
            return cancellationOutput(
                outcome: request.firedAt() == nil ? "completed-before-cancel" : "completed-despite-cancel",
                start: start,
                completion: completionTimestamp,
                request: request,
                partialText: transcript.text
            )
        } catch TranscribeError.aborted(_, let partial) {
            return cancellationOutput(
                outcome: "aborted",
                start: start,
                completion: DispatchTime.now().uptimeNanoseconds,
                request: request,
                partialText: partial?.text
            )
        } catch {
            return cancellationOutput(
                outcome: "error: \(error)",
                start: start,
                completion: DispatchTime.now().uptimeNanoseconds,
                request: request,
                partialText: nil
            )
        }
    }

    func stream(
        _ samples: [Float],
        chunkMilliseconds: Int = 100,
        realtime: Bool,
        onEvent: (StreamingEvent) -> Void = { _ in }
    ) throws -> StreamingOutput {
        guard identity.supportsStreaming else {
            throw BakeoffError("\(identity.architecture)/\(identity.variant) is not streaming-capable")
        }

        let stream = try session.stream()
        let chunkSamples = 16_000 * chunkMilliseconds / 1_000
        let start = DispatchTime.now().uptimeNanoseconds
        var events: [StreamingEvent] = []
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkSamples, samples.count)
            if realtime {
                Thread.sleep(forTimeInterval: Double(end - offset) / 16_000)
            }
            let update = try stream.feed(Array(samples[offset..<end]))
            if update.committedChanged || update.tentativeChanged {
                let text = stream.text
                let event = StreamingEvent(
                    wallMilliseconds: millisecondsSince(start),
                    inputReceivedMilliseconds: update.inputReceivedMs,
                    audioCommittedMilliseconds: update.audioCommittedMs,
                    committed: text.committed,
                    tentative: text.tentative
                )
                events.append(event)
                onEvent(event)
            }
            offset = end
        }
        _ = try stream.finalize()
        let final = stream.text
        if events.last?.committed != final.committed || events.last?.tentative != final.tentative {
            let event = StreamingEvent(
                wallMilliseconds: millisecondsSince(start),
                inputReceivedMilliseconds: Int64(samples.count * 1_000 / 16_000),
                audioCommittedMilliseconds: Int64(samples.count * 1_000 / 16_000),
                committed: final.committed,
                tentative: final.tentative
            )
            events.append(event)
            onEvent(event)
        }
        return StreamingOutput(finalText: final.full, events: events)
    }
}

private func cancellationOutput(
    outcome: String,
    start: UInt64,
    completion: UInt64,
    request: CancellationRequest,
    partialText: String?
) -> CancellationOutput {
    let requestTimestamp = request.firedAt()
    return CancellationOutput(
        outcome: outcome,
        requestedAtMilliseconds: requestTimestamp.map { milliseconds(from: start, to: $0) },
        completionMilliseconds: milliseconds(from: start, to: completion),
        responseMilliseconds: requestTimestamp.map { milliseconds(from: $0, to: completion) },
        partialText: partialText
    )
}

func peakResidentBytes() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return UInt64(usage.ru_maxrss)
}

func millisecondsSince(_ start: UInt64) -> Double {
    milliseconds(from: start, to: DispatchTime.now().uptimeNanoseconds)
}

private func milliseconds(from start: UInt64, to end: UInt64) -> Double {
    Double(end - start) / 1_000_000
}
