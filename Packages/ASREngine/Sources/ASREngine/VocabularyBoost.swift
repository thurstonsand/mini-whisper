import FluidAudio
import Foundation
import OSLog

private let boostLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "recognition-boost",
)

// MARK: - VocabularyBoostBackend

/// Preparation is separate from application because tokenizing the taught terms is the expensive
/// half and only changes when the dictionary does. `VocabularyBoost` owns that cache so it is
/// tested once, against a spy, rather than once per backend.
protocol VocabularyBoostBackend: Sendable {
  func prepare(terms: [String]) async throws
  func apply(
    samples: [Float], transcript: String, tokenTimings: [TokenTiming],
  ) async throws -> String
}

// MARK: - VocabularyBoost

actor VocabularyBoost {
  // MARK: Lifecycle

  init(backend: any VocabularyBoostBackend) {
    self.backend = backend
  }

  // MARK: Internal

  private(set) var preparedTerms: [String]?

  func apply(
    samples: [Float], transcript: String, tokenTimings: [TokenTiming],
    dictionary: TranscriptionDictionary,
  ) async throws -> String {
    let terms = dictionary.boostableTerms
    guard !terms.isEmpty else {
      return transcript
    }
    if preparedTerms != terms {
      try await backend.prepare(terms: terms)
      preparedTerms = terms
    }
    boostLogger.notice("Recognition boost inference started with \(terms.count) eligible terms")
    let boosted = try await backend.apply(
      samples: samples, transcript: transcript, tokenTimings: tokenTimings,
    )
    boostLogger.notice("Recognition boost inference completed")
    return boosted
  }

  // MARK: Private

  private let backend: any VocabularyBoostBackend
}

// MARK: - FluidVocabularyBoostBackend

actor FluidVocabularyBoostBackend: VocabularyBoostBackend {
  // MARK: Lifecycle

  private init(directory: URL, models: CtcModels, tokenizer: CtcTokenizer) {
    self.directory = directory
    self.tokenizer = tokenizer
    spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
  }

  // MARK: Internal

  static func load(from directory: URL) async throws -> FluidVocabularyBoostBackend {
    try await FluidVocabularyBoostBackend(
      directory: directory, models: CtcModels.loadDirect(from: directory),
      tokenizer: CtcTokenizer.load(from: directory),
    )
  }

  func prepare(terms: [String]) async throws {
    let tokenizedTerms = terms.compactMap { text -> CustomVocabularyTerm? in
      let tokenIDs = tokenizer.encode(text)
      guard !tokenIDs.isEmpty else {
        return nil
      }
      return CustomVocabularyTerm(
        text: text, ctcTokenIds: tokenIDs,
        minSimilarity: RecognitionBoostThresholds.minimumSimilarity,
      )
    }
    let vocabulary = CustomVocabularyContext(
      terms: tokenizedTerms,
      minCtcScore: RecognitionBoostThresholds.minimumVocabularyCTCScore,
      minSimilarity: RecognitionBoostThresholds.minimumSimilarity,
      minTermLength: RecognitionBoostThresholds.minimumTermLength,
    )
    self.vocabulary = vocabulary
    rescorer = try await VocabularyRescorer.create(
      spotter: spotter, vocabulary: vocabulary,
      config: VocabularyRescorer.Config(
        spotterRescueMinSimilarity: RecognitionBoostThresholds.minimumSimilarity,
        spotterRescueMultiWordMinSimilarity: RecognitionBoostThresholds.minimumSimilarity,
      ),
      ctcModelDirectory: directory,
    )
  }

  func apply(
    samples: [Float], transcript: String, tokenTimings: [TokenTiming],
  ) async throws -> String {
    guard let vocabulary, let rescorer else {
      return transcript
    }
    let spotted = try await spotter.spotKeywordsWithLogProbs(
      audioSamples: samples, customVocabulary: vocabulary,
      minScore: RecognitionBoostThresholds.minimumSpotterScore,
    )
    guard !spotted.logProbs.isEmpty else {
      return transcript
    }
    return rescorer.ctcTokenRescore(
      transcript: transcript, tokenTimings: tokenTimings, logProbs: spotted.logProbs,
      frameDuration: spotted.frameDuration,
      cbw: RecognitionBoostThresholds.contextBiasingWeight,
      marginSeconds: RecognitionBoostThresholds.marginSeconds,
      minSimilarity: RecognitionBoostThresholds.minimumSimilarity,
    )
    .text
  }

  // MARK: Private

  private let directory: URL
  private let tokenizer: CtcTokenizer
  private let spotter: CtcKeywordSpotter
  private var vocabulary: CustomVocabularyContext?
  private var rescorer: VocabularyRescorer?
}
