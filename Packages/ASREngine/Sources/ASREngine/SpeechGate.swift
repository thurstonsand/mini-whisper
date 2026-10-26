import FluidAudio
import Foundation
import ModelLibrary
import OSLog

private let gateLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

/// Gesture timing is deliberately irrelevant here: 500 ms covers press reaction time plus the
/// minimum voicing needed for an intended utterance.
let minimumUtteranceDuration: TimeInterval = 0.5

// MARK: - SpeechGate

/// Silence rejection, in front of every engine: the duration floor, then one whole-utterance
/// Silero classification. Audio the gate refuses never reaches a decoder, local or hosted, so an
/// empty recording can never come back as hallucinated text.
final class SpeechGate: @unchecked Sendable {
  // MARK: Lifecycle

  init(library: ModelLibrary, configuration: GateConfiguration) {
    self.library = library
    self.configuration = configuration
  }

  // MARK: Internal

  /// Loads and prewarms Silero. Callers serialize this behind their own readiness.
  func load() async throws {
    let manager = try await VadManager(
      config: VadConfig(defaultThreshold: configuration.threshold, computeUnits: .cpuOnly),
      modelDirectory: library.root,
    )
    _ = try await manager.process(Array(repeating: 0, count: GateFraming.frameSampleCount))
    lock.withLock { self.manager = manager }
  }

  func unload() {
    lock.withLock { manager = nil }
  }

  /// Nil when the audio may proceed to an engine; otherwise the outcome it ends with.
  func refusal(of samples: [Float], sampleRate: Double) async throws -> TranscriptionOutcome? {
    precondition(sampleRate > 0)
    let duration = Double(samples.count) / sampleRate
    guard duration >= minimumUtteranceDuration else {
      gateLogger.notice(
        "Gate discarded recording below duration floor: duration=\(duration, format: .fixed(precision: 3))s",
      )
      return .tooShort
    }
    guard let manager = lock.withLock({ manager }) else {
      throw ASREngineError.notReady
    }
    let results = try await manager.process(GateFraming.zeroPaddedCopy(of: samples))
    let segments = await manager.segmentSpeech(
      from: results, totalSamples: samples.count,
      config: configuration.segmentationConfiguration,
    )
    return segments.isEmpty ? .noSpeech : nil
  }

  // MARK: Private

  private let library: ModelLibrary
  private let configuration: GateConfiguration
  private let lock = NSLock()
  private var manager: VadManager?
}
