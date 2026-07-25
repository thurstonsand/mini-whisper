import Foundation
import Testing

@testable import ASREngine

@Suite struct EngineLifecycleTests {
  @Test func onlyActiveSetupPhasesRejectASecondSetup() {
    #expect(EngineReadiness.downloading(0).isSetupInProgress)
    #expect(EngineReadiness.compiling.isSetupInProgress)
    #expect(EngineReadiness.prewarming.isSetupInProgress)
    #expect(!EngineReadiness.modelMissing.isSetupInProgress)
    #expect(!EngineReadiness.ready.isSetupInProgress)
    #expect(!EngineReadiness.failed("failure").isSetupInProgress)
  }

  @Test func modelRevisionsAreImmutableCodePins() {
    #expect(PinnedModelStore.asrRevision.count == 40)
    #expect(PinnedModelStore.vadRevision.count == 40)
    #expect(!PinnedModelStore.asrRevision.contains("main"))
    #expect(!PinnedModelStore.vadRevision.contains("main"))
  }

  @Test func missingAndCorruptProvenanceRemainDistinct() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PinnedModelStore(root: root)

    #expect(throws: ASREngineError.modelMissing) { try store.validateInstalledArtifact() }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: root.appending(path: "provenance.json"))
    #expect(throws: ASREngineError.self) { try store.validateInstalledArtifact() }
  }

  @Test func missingInstallEmitsModelMissingBeforeFinishing() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    let engine = LocalASREngine(
      gateConfiguration: .calibrated, modelStore: PinnedModelStore(root: root))
    var readiness: [EngineReadiness] = []

    for await update in engine.prepareInstalled() { readiness.append(update) }

    #expect(readiness == [.modelMissing])
  }

  @Test func concurrentSetupEmitsFailureBeforeFinishing() async {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    let engine = LocalASREngine(
      gateConfiguration: .calibrated, modelStore: PinnedModelStore(root: root))
    let (setupStarted, setupStartedContinuation) = AsyncStream<Void>.makeStream()
    let firstSetup = Task {
      for await update in engine.installAndPrepare() {
        guard update == .downloading(0) else { continue }
        setupStartedContinuation.yield()
        setupStartedContinuation.finish()
      }
    }

    for await _ in setupStarted { break }
    var duplicateReadiness: [EngineReadiness] = []
    for await update in engine.installAndPrepare() { duplicateReadiness.append(update) }

    #expect(duplicateReadiness == [.failed(ASREngineError.setupInProgress.localizedDescription)])
    firstSetup.cancel()
    await firstSetup.value
  }
}

@Suite struct GateFramingTests {
  @Test(
    "Zero padding produces exact FluidAudio frames",
    arguments: [
      (count: 1, padded: 4096), (count: 4095, padded: 4096), (count: 4096, padded: 4096),
      (count: 4097, padded: 8192),
    ]) func zeroPadding(count: Int, padded: Int)
  {
    let samples = (0..<count).map(Float.init)
    let result = GateFraming.zeroPaddedCopy(of: samples)

    #expect(result.count == padded)
    #expect(Array(result.prefix(count)) == samples)
    #expect(result.dropFirst(count).allSatisfy { $0 == 0 })
    #expect(result.count.isMultiple(of: GateFraming.frameSampleCount))
  }

  @Test func emptyAudioDoesNotManufactureAFrame() {
    #expect(GateFraming.zeroPaddedCopy(of: []).isEmpty)
  }
}

@Suite struct GateConfigurationTests {
  @Test func calibratedSettingsMatchThePublishedBakeoff() {
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

  @Test func negativeThresholdNeverReachesZero() {
    let segmentation = GateConfiguration(threshold: 0.1, minimumSpeechDuration: 0.15)
      .segmentationConfiguration

    #expect(segmentation.negativeThreshold == 0.01)
  }
}

@Suite struct TranscriptionOutcomeMapperTests {
  @Test func acceptedEmptyTranscriptRemainsDistinct() {
    #expect(TranscriptionOutcomeMapper.map(transcript: "  \n") == .engineEmpty)
  }

  @Test func acceptedTextIsTrimmedAndReturned() {
    #expect(TranscriptionOutcomeMapper.map(transcript: " hello \n") == .transcript("hello"))
  }
}
