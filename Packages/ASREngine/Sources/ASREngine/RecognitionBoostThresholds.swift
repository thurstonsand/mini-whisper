import Foundation

/// MacParakeet measured false substitutions at FluidAudio's defaults. A correctly heard word
/// silently replaced by a taught term is worse than a missed boost, so MiniWhisper starts stricter.
public struct RecognitionBoostThresholds: Equatable, Sendable {
  // MARK: Lifecycle

  public init(minimumSimilarity: Float = 0.65) {
    self.minimumSimilarity = minimumSimilarity
  }

  // MARK: Public

  public static let `default` = RecognitionBoostThresholds()

  public let minimumSimilarity: Float // FluidAudio size-aware defaults: 0.50/0.55/0.60.

  // MARK: Internal

  static let minimumTermLength = 3 // Matches FluidAudio's default.
  static let minimumSpotterScore: Float = -12 // FluidAudio default: -15.
  static let minimumVocabularyCTCScore: Float = -10 // FluidAudio default: -12.
  static let contextBiasingWeight: Float = 3 // FluidAudio default: 4.5.
  static let marginSeconds: Double = 0.5 // Matches FluidAudio's default.
}
