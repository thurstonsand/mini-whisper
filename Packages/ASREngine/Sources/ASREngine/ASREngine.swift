import FluidAudio
import Foundation
import ModelLibrary
import OSLog

private let engineLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "engine")

// MARK: - LocalASREngine

public actor LocalASREngine {
  // MARK: Lifecycle

  public init(
    library: ModelLibrary, speechModel: SpeechModel,
    gateConfiguration: GateConfiguration = .calibrated,
    boostThresholds: RecognitionBoostThresholds = .default,
  ) {
    self.library = library
    self.speechModel = speechModel
    gate = SpeechGate(library: library, configuration: gateConfiguration)
    self.boostThresholds = boostThresholds
  }

  // MARK: Public

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

  /// Lets go of every loaded model so its files can be deleted. Setup in flight is left alone:
  /// whatever it is loading, it finishes or fails on its own.
  public func unload() {
    guard !readiness.isSetupInProgress else {
      return
    }
    gate.unload()
    asrManager = nil
    decoderLayerCount = nil
    boost = nil
    readiness = .modelMissing
  }

  public func submit(
    _ samples: [Float], sampleRate: Double, dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    if let refusal = try await gate.refusal(of: samples, sampleRate: sampleRate) {
      return refusal
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

  private let gate: SpeechGate
  private let boostThresholds: RecognitionBoostThresholds
  private let library: ModelLibrary
  private let speechModel: SpeechModel
  private var readiness: EngineReadiness = .modelMissing
  private var asrManager: AsrManager?
  private var decoderLayerCount: Int?
  private var boost: VocabularyBoost?

  /// The gate, and the speech model's asset when it ships.
  private var assets: [ModelAsset] {
    [.gate] + (speechModel.asset.map { [$0] } ?? [])
  }

  /// A candidate has no asset, so it brings the recognition helper the shipped asset carries.
  private var candidateRepositories: [PinnedRepository] {
    [speechModel.repository, .parakeetCTC]
  }

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
      for asset in assets {
        _ = try library.validate(asset)
      }
      if speechModel.asset == nil {
        _ = try library.validate(candidateRepositories)
      }
      try await loadAndPrewarm { continuation.yield($0) }
    } catch ModelLibraryError.missing, ModelLibraryError.missingRepository {
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
      // A validated install that still failed to load is the one case a fresh download of
      // everything repairs; otherwise only what is missing is fetched.
      let missing = assets.filter { (try? library.validate($0)) == nil }
      try await library.install(missing.isEmpty ? assets : missing) { fraction in
        continuation.yield(.downloading(fraction))
      }
      if speechModel.asset == nil {
        // The recognition helper is usually there already, as half of the shipped asset.
        let missing = candidateRepositories.filter { (try? library.validate([$0])) == nil }
        if !missing.isEmpty {
          try await library.install(missing, name: speechModel.id) { fraction in
            continuation.yield(.downloading(fraction))
          }
        }
      }
      try await loadAndPrewarm { continuation.yield($0) }
    } catch { updateReadiness(.failed(error.localizedDescription)) { continuation.yield($0) } }
  }

  private func loadAndPrewarm(
    progress: @escaping @Sendable (EngineReadiness) -> Void,
  ) async throws {
    ModelHub.offlineMode = true
    updateReadiness(.compiling, progress: progress)
    // `load` resolves a family's own repository folder; the pinned model lives in the library's.
    let models = try AsrModels.loadLocal(
      from: library.directory(speechModel.repository), version: speechModel.family,
    )
    let asrManager = AsrManager(
      config: ASRConfig(
        parallelChunkConcurrency: 4, streamingEnabled: false, melChunkContext: true,
        dualDecodeArbitration: false,
      ), models: models,
    )

    updateReadiness(.prewarming, progress: progress)
    try await gate.load()
    var decoderState = try TdtDecoderState(decoderLayers: models.version.decoderLayers)
    _ = try await asrManager.transcribe(
      Array(repeating: 0, count: 16000), decoderState: &decoderState,
    )

    self.asrManager = asrManager
    decoderLayerCount = models.version.decoderLayers
    boost = try await VocabularyBoost(
      backend: FluidVocabularyBoostBackend.load(
        from: library.directory(.parakeetCTC), thresholds: boostThresholds,
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
