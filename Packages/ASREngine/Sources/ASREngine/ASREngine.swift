import FluidAudio
import Foundation
import OSLog

private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

/// Gesture timing is deliberately irrelevant here: 500 ms covers press reaction time plus the
/// minimum voicing needed for an intended utterance.
let minimumUtteranceDuration: TimeInterval = 0.5

// MARK: - LocalASREngine

public actor LocalASREngine {
  // MARK: Lifecycle

  public init(
    modelRoot: URL, gateConfiguration: GateConfiguration = .calibrated,
    boostThresholds: RecognitionBoostThresholds = .default,
  ) {
    self.gateConfiguration = gateConfiguration
    self.boostThresholds = boostThresholds
    modelStore = PinnedModelStore(root: modelRoot)
  }

  init(gateConfiguration: GateConfiguration, modelStore: PinnedModelStore) {
    self.gateConfiguration = gateConfiguration
    boostThresholds = .default
    self.modelStore = modelStore
  }

  // MARK: Public

  public nonisolated static let identity =
    "\(PinnedModelStore.asrRepository)@\(PinnedModelStore.asrRevision)"

  public nonisolated func prepareInstalled() -> AsyncStream<EngineReadiness> {
    AsyncStream { continuation in
      let task = Task { await self.prepareInstalled(continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public nonisolated func installAndPrepare() -> AsyncStream<EngineReadiness> {
    AsyncStream { continuation in
      let task = Task { await self.installAndPrepare(continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func submit(
    _ samples: [Float], sampleRate: Double, dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    precondition(sampleRate > 0)
    let duration = Double(samples.count) / sampleRate
    guard duration >= minimumUtteranceDuration else {
      engineLogger.notice(
        "Gate discarded recording below duration floor: duration=\(duration, format: .fixed(precision: 3))s",
      )
      return .tooShort
    }
    guard readiness == .ready, let vadManager else {
      throw ASREngineError.notReady
    }

    let gateSamples = GateFraming.zeroPaddedCopy(of: samples)
    let results = try await vadManager.process(gateSamples)
    let segments = await vadManager.segmentSpeech(
      from: results, totalSamples: samples.count,
      config: gateConfiguration.segmentationConfiguration,
    )
    guard !segments.isEmpty else {
      return .noSpeech
    }

    return try await decode(samples, dictionary: dictionary)
  }

  /// Offline replay of recordings that were made on purpose. The gate answers "did the user mean
  /// to say anything", a question a corpus fixture has already answered, so replay decodes
  /// directly and the gate's own thresholds stay out of the measurement.
  public func transcribeIgnoringGate(
    _ samples: [Float], sampleRate: Double, dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    precondition(sampleRate > 0)
    return try await decode(samples, dictionary: dictionary)
  }

  // MARK: Private

  private let gateConfiguration: GateConfiguration
  private let boostThresholds: RecognitionBoostThresholds
  private let modelStore: PinnedModelStore
  private var readiness: EngineReadiness = .modelMissing
  private var vadManager: VadManager?
  private var asrManager: AsrManager?
  private var decoderLayerCount: Int?
  private var boost: VocabularyBoost?

  private func decode(
    _ samples: [Float], dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    guard readiness == .ready, let asrManager, let decoderLayerCount, let boost else {
      throw ASREngineError.notReady
    }
    var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
    let transcript = try await asrManager.transcribe(samples, decoderState: &decoderState)
    let boosted: String
    if let tokenTimings = transcript.tokenTimings {
      do {
        boosted = try await boost.apply(
          samples: samples, transcript: transcript.text, tokenTimings: tokenTimings,
          dictionary: dictionary,
        )
      } catch {
        engineLogger.error(
          "Recognition boost failed; continuing with decoded transcript: \(error.localizedDescription, privacy: .public)",
        )
        boosted = transcript.text
      }
    } else {
      boosted = transcript.text
    }
    return TranscriptionOutcomeFinisher.finish(transcript: boosted, dictionary: dictionary)
  }

  private func prepareInstalled(continuation: AsyncStream<EngineReadiness>.Continuation) async {
    defer { continuation.finish() }
    if readiness == .ready {
      continuation.yield(.ready)
      return
    }
    if readiness.isSetupInProgress {
      continuation.yield(readiness)
      return
    }
    do {
      try modelStore.validateInstalledArtifact()
      try await loadAndPrewarm { continuation.yield($0) }
    } catch ASREngineError.modelMissing {
      updateReadiness(.modelMissing) { continuation.yield($0) }
    } catch { updateReadiness(.failed(error.localizedDescription)) { continuation.yield($0) } }
  }

  private func installAndPrepare(continuation: AsyncStream<EngineReadiness>.Continuation) async {
    defer { continuation.finish() }
    guard !readiness.isSetupInProgress else {
      continuation.yield(.failed(ASREngineError.setupInProgress.localizedDescription))
      return
    }
    do {
      updateReadiness(.downloading(0)) { continuation.yield($0) }
      try await modelStore.download { fraction in continuation.yield(.downloading(fraction)) }
      try await loadAndPrewarm { continuation.yield($0) }
    } catch { updateReadiness(.failed(error.localizedDescription)) { continuation.yield($0) } }
  }

  private func loadAndPrewarm(
    progress: @escaping @Sendable (EngineReadiness) -> Void,
  ) async throws {
    ModelHub.offlineMode = true
    updateReadiness(.compiling, progress: progress)
    let vadManager = try await VadManager(
      config: VadConfig(defaultThreshold: gateConfiguration.threshold, computeUnits: .cpuOnly),
      modelDirectory: modelStore.vadBaseDirectory,
    )
    let models = try await AsrModels.load(
      from: modelStore.asrDirectory, version: .v2, encoderPrecision: .int8,
    )
    let asrManager = AsrManager(
      config: ASRConfig(
        parallelChunkConcurrency: 4, streamingEnabled: false, melChunkContext: true,
        dualDecodeArbitration: false,
      ), models: models,
    )

    updateReadiness(.prewarming, progress: progress)
    _ = try await vadManager.process(Array(repeating: 0, count: GateFraming.frameSampleCount))
    var decoderState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
    _ = try await asrManager.transcribe(
      Array(repeating: 0, count: 16000), decoderState: &decoderState,
    )

    self.vadManager = vadManager
    self.asrManager = asrManager
    decoderLayerCount = models.version.decoderLayers
    boost = try await VocabularyBoost(
      backend: FluidVocabularyBoostBackend.load(
        from: modelStore.ctcDirectory, thresholds: boostThresholds,
      ),
    )
    updateReadiness(.ready, progress: progress)
  }

  private func updateReadiness(
    _ readiness: EngineReadiness, progress: @escaping @Sendable (EngineReadiness) -> Void,
  ) {
    self.readiness = readiness
    progress(readiness)
  }
}
