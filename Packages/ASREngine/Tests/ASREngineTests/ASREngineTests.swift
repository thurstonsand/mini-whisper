@testable import ASREngine
import Foundation
import ModelLibrary
import Testing

// MARK: - EngineLifecycleTests

struct EngineLifecycleTests {
  @Test func `only active setup phases reject A second setup`() {
    #expect(EngineReadiness.downloading(0).isSetupInProgress)
    #expect(EngineReadiness.compiling.isSetupInProgress)
    #expect(EngineReadiness.prewarming.isSetupInProgress)
    #expect(!EngineReadiness.modelMissing.isSetupInProgress)
    #expect(!EngineReadiness.ready.isSetupInProgress)
    #expect(!EngineReadiness.failed("failure").isSetupInProgress)
  }

  @Test func `missing install emits model missing before finishing`() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    let engine = LocalASREngine(
      library: ModelLibrary(root: root), speechModel: .parakeetV2,
    )
    var readiness: [EngineReadiness] = []

    for await update in engine.prepareInstalled() {
      readiness.append(update)
    }

    #expect(readiness == [.modelMissing])
  }

  @Test func `every catalogue model is an immutable code pin`() {
    for model in SpeechModel.catalogue {
      #expect(model.repository.revision.count == 40)
      #expect(!model.repository.revision.contains("main"))
    }
  }

  /// A candidate lives outside the assets, so its absence is its own error; it still reads as a
  /// model to download rather than a failure.
  @Test func `a candidate not yet installed reads missing`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let gate = PinnedRepository.sileroVAD
    try Data(
      #"{"repositories":[{"repository":"\#(gate.repository)","revision":"\#(gate.revision)","files":[]}]}"#
        .utf8,
    ).write(to: root.appending(path: "provenance.json"))
    let engine = LocalASREngine(library: ModelLibrary(root: root), speechModel: .fluidSpeechMini)
    var readiness: [EngineReadiness] = []

    for await update in engine.prepareInstalled() {
      readiness.append(update)
    }

    #expect(readiness == [.modelMissing])
  }

  @Test func `four hundred ninety nine milliseconds is discarded before engine work`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = LocalASREngine(
      library: ModelLibrary(root: root), speechModel: .parakeetV2,
    )
    let samples = Array(repeating: Float.zero, count: 7984)

    #expect(try await engine.submit(samples, sampleRate: 16000, dictionary: .empty) == .tooShort)
  }

  @Test func `five hundred milliseconds proceeds beyond the duration floor`() async {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = LocalASREngine(
      library: ModelLibrary(root: root), speechModel: .parakeetV2,
    )
    let samples = Array(repeating: Float.zero, count: 8000)

    await #expect(throws: ASREngineError.notReady) {
      try await engine.submit(samples, sampleRate: 16000, dictionary: .empty)
    }
  }

  @Test func `replay below the duration floor still reaches the engine`() async {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = LocalASREngine(
      library: ModelLibrary(root: root), speechModel: .parakeetV2,
    )
    let samples = Array(repeating: Float.zero, count: 7984)

    await #expect(throws: ASREngineError.notReady) {
      try await engine.transcribeIgnoringGate(samples, sampleRate: 16000, dictionary: .empty)
    }
  }

  @Test func `concurrent setup emits failure before finishing`() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory,
    )
    let engine = LocalASREngine(
      library: ModelLibrary(root: root), speechModel: .parakeetV2,
    )
    let (setupStarted, setupStartedContinuation) = AsyncStream<Void>.makeStream()
    let firstSetup = Task {
      for await update in engine.installAndPrepare() {
        guard update == .downloading(0) else {
          continue
        }
        setupStartedContinuation.yield()
        setupStartedContinuation.finish()
      }
    }

    for await _ in setupStarted {
      break
    }
    var duplicateReadiness: [EngineReadiness] = []
    for await update in engine.installAndPrepare() {
      duplicateReadiness.append(update)
    }

    #expect(duplicateReadiness == [.failed(ASREngineError.setupInProgress.localizedDescription)])
    firstSetup.cancel()
    await firstSetup.value
  }
}

// MARK: - GateFramingTests

struct GateFramingTests {
  @Test(
    arguments: [
      (count: 1, padded: 4096), (count: 4095, padded: 4096), (count: 4096, padded: 4096),
      (count: 4097, padded: 8192),
    ],
  ) func `Zero padding produces exact FluidAudio frames`(count: Int, padded: Int) {
    let samples = (0 ..< count).map(Float.init)
    let result = GateFraming.zeroPaddedCopy(of: samples)

    #expect(result.count == padded)
    #expect(Array(result.prefix(count)) == samples)
    #expect(result.dropFirst(count).allSatisfy { $0 == 0 })
    #expect(result.count.isMultiple(of: GateFraming.frameSampleCount))
  }

  @Test func `empty audio does not manufacture A frame`() {
    #expect(GateFraming.zeroPaddedCopy(of: []).isEmpty)
  }
}

// MARK: - GateConfigurationTests

struct GateConfigurationTests {
  @Test func `calibrated settings match the published bakeoff`() {
    let configuration = GateConfiguration.calibrated
    let segmentation = configuration.segmentationConfiguration

    #expect(configuration.threshold == 0.9)
    #expect(configuration.minimumSpeechDuration == 0.15)
    #expect(segmentation.minSpeechDuration == 0.15)
    #expect(segmentation.minSilenceDuration == 0.75)
    #expect(segmentation.maxSpeechDuration == .infinity)
    #expect(segmentation.speechPadding == 0)
    #expect(segmentation.silenceThresholdForSplit == 0.3)
    #expect(segmentation.negativeThreshold == 0.75)
    #expect(segmentation.negativeThresholdOffset == 0.15)
    #expect(segmentation.minSilenceAtMaxSpeech == 0.098)
    #expect(segmentation.useMaxPossibleSilenceAtMaxSpeech)
    #expect(GateFraming.frameSampleCount == 4096)
  }

  @Test func `negative threshold never reaches zero`() {
    let segmentation = GateConfiguration(threshold: 0.1, minimumSpeechDuration: 0.15)
      .segmentationConfiguration

    #expect(segmentation.negativeThreshold == 0.01)
  }
}

// MARK: - TranscriptionOutcomeFinisherTests

struct TranscriptionOutcomeFinisherTests {
  @Test func `accepted empty transcript remains distinct`() {
    #expect(
      TranscriptionOutcomeFinisher.finish(transcript: "  \n", dictionary: .empty) == .engineEmpty,
    )
  }

  @Test func `accepted text is trimmed and returned`() {
    #expect(
      TranscriptionOutcomeFinisher.finish(transcript: " hello \n", dictionary: .empty)
        == .transcript("hello"),
    )
  }

  @Test func `decoded text is corrected before it leaves the engine boundary`() {
    let dictionary = TranscriptionDictionary(
      vocabulary: ["TCA"],
      corrections: [TranscriptionCorrection(misspelling: "mini whisper", text: "MiniWhisper")],
    )

    #expect(
      TranscriptionOutcomeFinisher.finish(
        transcript: "mini whisper uses tca", dictionary: dictionary,
      ) == .transcript("MiniWhisper uses TCA"),
    )
  }

  @Test func `a correction that removes all text produces engine empty`() {
    let dictionary = TranscriptionDictionary(
      vocabulary: [], corrections: [TranscriptionCorrection(misspelling: "remove", text: "")],
    )

    #expect(
      TranscriptionOutcomeFinisher.finish(transcript: "remove", dictionary: dictionary)
        == .engineEmpty,
    )
  }
}
