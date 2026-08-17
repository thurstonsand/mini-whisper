@testable import ASREngine
import Foundation
import Testing

// MARK: - RealAssetVocabularyBoostTests

/// The only test that touches installed Core ML assets, so it is opt-in by environment. It is
/// skipped rather than silently passing when they are absent — a test that cannot fail is worse
/// than no test. Whether the boost *improved* the transcript is a human judgement, so both
/// transcripts are attached as comments; whether the pipeline still runs is asserted.
struct RealAssetVocabularyBoostTests {
  // MARK: Internal

  @Test(.enabled(if: RealAssetFixture.isAvailable))
  func `installed sidecar transcribes with the boost off and on`() async throws {
    let fixture = try #require(RealAssetFixture.resolve())
    let engine = LocalASREngine(modelRoot: fixture.modelRoot)
    var finalReadiness = EngineReadiness.modelMissing
    for await readiness in engine.prepareInstalled() {
      finalReadiness = readiness
    }
    #expect(finalReadiness == .ready)

    let samples = try pcm16Samples(from: fixture.audio)
    let withoutBoost = try await engine.submit(
      samples, sampleRate: 16000,
      dictionary: TranscriptionDictionary(
        vocabulary: ["MiniWhisper"], corrections: [], boostsVocabulary: false,
      ),
    )
    let withBoost = try await engine.submit(
      samples, sampleRate: 16000,
      dictionary: TranscriptionDictionary(
        vocabulary: ["MiniWhisper"], corrections: [], boostsVocabulary: true,
      ),
    )

    guard case let .transcript(unboosted) = withoutBoost,
          case let .transcript(boosted) = withBoost
    else {
      Issue.record(
        "Real-asset transcription produced no transcript: \(withoutBoost) / \(withBoost)",
      )
      return
    }
    // Whether the boost helped is the human's call, so both transcripts are printed for reading.
    // That the pipeline ran at all is not a judgement call, so it is asserted.
    print("Real-asset transcript, boost off: \(unboosted)")
    print("Real-asset transcript, boost on:  \(boosted)")
    #expect(!unboosted.isEmpty)
    #expect(!boosted.isEmpty)
  }

  // MARK: Private

  private func pcm16Samples(from url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    let marker = Data("data".utf8)
    guard let markerRange = data.range(of: marker) else {
      throw AudioFixtureError.missingDataChunk
    }
    let sizeStart = markerRange.upperBound
    let sampleStart = sizeStart + 4
    guard data.count >= sampleStart else {
      throw AudioFixtureError.missingDataChunk
    }
    let byteCount = Int(
      UInt32(data[sizeStart])
        | UInt32(data[sizeStart + 1]) << 8
        | UInt32(data[sizeStart + 2]) << 16
        | UInt32(data[sizeStart + 3]) << 24,
    )
    guard data.count >= sampleStart + byteCount else {
      throw AudioFixtureError.missingDataChunk
    }
    return stride(from: sampleStart, to: sampleStart + byteCount, by: 2).map { offset in
      let bits = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
      return Float(Int16(bitPattern: bits)) / Float(Int16.max)
    }
  }
}

// MARK: - RealAssetFixture

enum RealAssetFixture {
  static var isAvailable: Bool {
    resolve() != nil
  }

  static func resolve() -> (modelRoot: URL, audio: URL)? {
    let environment = ProcessInfo.processInfo.environment
    guard let modelPath = environment["MINIWHISPER_REAL_ASSET_ROOT"],
          let audioPath = environment["MINIWHISPER_REAL_AUDIO"]
    else {
      return nil
    }
    return (URL(fileURLWithPath: modelPath), URL(fileURLWithPath: audioPath))
  }
}

// MARK: - AudioFixtureError

private enum AudioFixtureError: Error {
  case missingDataChunk
}
