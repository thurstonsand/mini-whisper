import FluidAudio
import Foundation

// MARK: - TranscriptionDictionary

public struct TranscriptionDictionary: Equatable, Sendable {
  // MARK: Lifecycle

  public init(vocabulary: [String], corrections: [TranscriptionCorrection]) {
    self.vocabulary = vocabulary
    self.corrections = corrections
  }

  // MARK: Public

  public static let empty = TranscriptionDictionary(vocabulary: [], corrections: [])

  public let vocabulary: [String]
  public let corrections: [TranscriptionCorrection]
}

// MARK: - TranscriptionCorrection

public struct TranscriptionCorrection: Equatable, Sendable {
  // MARK: Lifecycle

  public init(misspelling: String, text: String) {
    self.misspelling = misspelling
    self.text = text
  }

  // MARK: Public

  public let misspelling: String
  public let text: String
}

// MARK: - TranscriptionOutcome

public enum TranscriptionOutcome: Equatable, Sendable {
  case transcript(String)
  case tooShort
  case noSpeech
  case engineEmpty
}

// MARK: - EngineReadiness

public enum EngineReadiness: Equatable, Sendable {
  case modelMissing
  case downloading(Double)
  case compiling
  case prewarming
  case ready
  case failed(String)
}

// MARK: - ASREngineError

public enum ASREngineError: Error, Equatable, LocalizedError, Sendable {
  case modelMissing
  case invalidArtifact(String)
  case invalidDownload(String)
  case setupInProgress
  case notReady

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case .modelMissing:
      "Pinned speech models are not installed"
    case let .invalidArtifact(message):
      "Invalid pinned model artifact: \(message)"
    case let .invalidDownload(message):
      "Pinned model download failed: \(message)"
    case .setupInProgress:
      "Speech engine setup is already in progress"
    case .notReady:
      "Speech engine is not ready"
    }
  }
}

// MARK: - GateConfiguration

public struct GateConfiguration: Equatable, Sendable {
  // MARK: Lifecycle

  public init(threshold: Float, minimumSpeechDuration: TimeInterval) {
    precondition((0 ... 1).contains(threshold))
    precondition(minimumSpeechDuration >= 0)
    self.threshold = threshold
    self.minimumSpeechDuration = minimumSpeechDuration
  }

  // MARK: Public

  public static let calibrated = GateConfiguration(threshold: 0.9, minimumSpeechDuration: 0.15)

  public let threshold: Float
  public let minimumSpeechDuration: TimeInterval

  public var segmentationConfiguration: VadSegmentationConfig {
    var configuration = VadSegmentationConfig(
      minSpeechDuration: minimumSpeechDuration, minSilenceDuration: 0.75,
      maxSpeechDuration: .infinity, speechPadding: 0, silenceThresholdForSplit: 0.3,
      negativeThreshold: nil, negativeThresholdOffset: 0.15, minSilenceAtMaxSpeech: 0.098,
      useMaxPossibleSilenceAtMaxSpeech: true,
    )
    // FluidAudio 0.15.5 contradicts its threshold-override semantics with a debug-only
    // constructor assertion, so assign the public override after initialization.
    configuration.negativeThreshold = max(0.01, threshold - configuration.negativeThresholdOffset)
    return configuration
  }
}

public extension EngineReadiness {
  /// Setup is already running, so a second request to start one would only race the first.
  var isSetupInProgress: Bool {
    switch self {
    case .downloading,
         .compiling,
         .prewarming:
      true
    case .modelMissing,
         .ready,
         .failed:
      false
    }
  }
}

// MARK: - GateFraming

public enum GateFraming {
  public static let frameSampleCount = 4096

  public static func zeroPaddedCopy(of samples: [Float]) -> [Float] {
    guard !samples.isEmpty else {
      return []
    }
    let remainder = samples.count % frameSampleCount
    guard remainder != 0 else {
      return samples
    }
    return samples + Array(repeating: 0, count: frameSampleCount - remainder)
  }
}

// MARK: - TranscriptionOutcomeFinisher

public enum TranscriptionOutcomeFinisher {
  public static func finish(
    transcript: String?, dictionary: TranscriptionDictionary,
  ) -> TranscriptionOutcome {
    let decoded = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !decoded.isEmpty else {
      return .engineEmpty
    }
    let corrected = TranscriptCorrector(dictionary: dictionary).apply(to: decoded)
    return corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .engineEmpty : .transcript(corrected)
  }
}
