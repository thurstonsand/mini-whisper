@testable import ASREngine
import FluidAudio
import Foundation
import Testing

// MARK: - VocabularyBoostTests

struct VocabularyBoostTests {
  // MARK: Internal

  @Test func `strict thresholds reject evidence accepted by FluidAudio defaults`() {
    #expect(RecognitionBoostThresholds.minimumSimilarity == 0.65)
    #expect(
      RecognitionBoostThresholds.minimumSimilarity
        > ContextBiasingConstants.rescorerConfig(forVocabSize: 101).minSimilarity,
    )
    #expect(
      RecognitionBoostThresholds.minimumSpotterScore
        > ContextBiasingConstants.defaultMinSpotterScore,
    )
    #expect(
      RecognitionBoostThresholds.minimumVocabularyCTCScore
        > ContextBiasingConstants.defaultMinVocabCtcScore,
    )
    #expect(
      RecognitionBoostThresholds.contextBiasingWeight
        < ContextBiasingConstants.rescorerConfig(forVocabSize: 1).cbw,
    )
  }

  @Test func `only a consenting dictionary offers terms long enough to boost`() {
    #expect(dictionary(["MiniWhisper"], boosts: false).boostableTerms.isEmpty)
    #expect(dictionary([], boosts: true).boostableTerms.isEmpty)
    #expect(dictionary(["AI"], boosts: true).boostableTerms.isEmpty)
    #expect(dictionary(["AI", "MiniWhisper"], boosts: true).boostableTerms == ["MiniWhisper"])
  }

  @Test func `a dictionary with no boostable terms never reaches the backend`() async throws {
    let spy = BoostSpy()
    let boost = VocabularyBoost(backend: spy)

    _ = try await boost.apply(
      samples: [], transcript: "decoded", tokenTimings: [],
      dictionary: dictionary(["MiniWhisper"], boosts: false),
    )
    _ = try await boost.apply(
      samples: [], transcript: "decoded", tokenTimings: [], dictionary: dictionary(
        [],
        boosts: true,
      ),
    )

    #expect(await spy.preparationCount == 0)
    #expect(await spy.invocationCount == 0)
  }

  @Test func `tokenized vocabulary is prepared once per distinct set of terms`() async throws {
    let spy = BoostSpy()
    let boost = VocabularyBoost(backend: spy)

    _ = try await boost.apply(
      samples: [], transcript: "first", tokenTimings: [],
      dictionary: dictionary(["MiniWhisper"], boosts: true),
    )
    // Only the corrections changed, and corrections never reach the spotter.
    _ = try await boost.apply(
      samples: [], transcript: "second", tokenTimings: [],
      dictionary: TranscriptionDictionary(
        vocabulary: ["MiniWhisper"],
        corrections: [TranscriptionCorrection(misspelling: "unrelated", text: "change")],
        boostsVocabulary: true,
      ),
    )
    _ = try await boost.apply(
      samples: [], transcript: "third", tokenTimings: [],
      dictionary: dictionary(["MiniWhisper", "Ghostty"], boosts: true),
    )

    #expect(await spy.preparationCount == 2)
    #expect(await spy.invocationCount == 3)
    #expect(await spy.preparedTerms == [["MiniWhisper"], ["MiniWhisper", "Ghostty"]])
    #expect(await boost.preparedTerms == ["MiniWhisper", "Ghostty"])
  }

  // MARK: Private

  private func dictionary(_ vocabulary: [String], boosts: Bool) -> TranscriptionDictionary {
    TranscriptionDictionary(
      vocabulary: vocabulary, corrections: [], boostsVocabulary: boosts,
    )
  }
}

// MARK: - BoostSpy

private actor BoostSpy: VocabularyBoostBackend {
  private(set) var preparationCount = 0
  private(set) var invocationCount = 0
  private(set) var preparedTerms: [[String]] = []

  func prepare(terms: [String]) async throws {
    preparationCount += 1
    preparedTerms.append(terms)
  }

  func apply(
    samples _: [Float], transcript: String, tokenTimings _: [TokenTiming],
  ) async throws -> String {
    invocationCount += 1
    return transcript
  }
}
