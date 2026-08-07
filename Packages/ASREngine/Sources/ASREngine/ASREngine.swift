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

  public init(modelRoot: URL, gateConfiguration: GateConfiguration = .calibrated) {
    self.gateConfiguration = gateConfiguration
    modelStore = PinnedModelStore(root: modelRoot)
  }

  init(gateConfiguration: GateConfiguration, modelStore: PinnedModelStore) {
    self.gateConfiguration = gateConfiguration
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
    _ samples: [Float], sampleRate: Double,
  ) async throws -> TranscriptionOutcome {
    precondition(sampleRate > 0)
    let duration = Double(samples.count) / sampleRate
    guard duration >= minimumUtteranceDuration else {
      engineLogger.notice(
        "Gate discarded recording below duration floor: duration=\(duration, format: .fixed(precision: 3))s",
      )
      return .tooShort
    }
    guard readiness == .ready, let vadManager, let asrManager, let decoderLayerCount else {
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

    var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
    let transcript = try await asrManager.transcribe(samples, decoderState: &decoderState)
    return TranscriptionOutcomeMapper.map(transcript: transcript.text)
  }

  // MARK: Private

  private let gateConfiguration: GateConfiguration
  private let modelStore: PinnedModelStore
  private var readiness: EngineReadiness = .modelMissing
  private var vadManager: VadManager?
  private var asrManager: AsrManager?
  private var decoderLayerCount: Int?

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

  private func loadAndPrewarm(progress: @escaping @Sendable (EngineReadiness) -> Void) async throws
  {
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
    updateReadiness(.ready, progress: progress)
  }

  private func updateReadiness(
    _ readiness: EngineReadiness, progress: @escaping @Sendable (EngineReadiness) -> Void,
  ) {
    self.readiness = readiness
    progress(readiness)
  }
}
