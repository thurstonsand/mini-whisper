import AVFAudio

// MARK: - CanonicalRecording

public struct CanonicalRecording: Equatable, Sendable {
  // MARK: Lifecycle

  public init(samples: [Float]) {
    self.samples = samples
  }

  // MARK: Public

  public static let sampleRate = 16000.0
  public static let channelCount: AVAudioChannelCount = 1

  public let samples: [Float]

  public var duration: Duration {
    .seconds(durationSeconds)
  }

  public var durationSeconds: Double {
    Double(samples.count) / Self.sampleRate
  }
}

// MARK: - CanonicalAudioFormat

enum CanonicalAudioFormat {
  static func make() -> AVAudioFormat? {
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: CanonicalRecording.sampleRate,
      channels: CanonicalRecording.channelCount, interleaved: false,
    )
  }

  static func containsCanonicalSamples(_ format: AVAudioFormat) -> Bool {
    format.commonFormat == .pcmFormatFloat32 && format.sampleRate == CanonicalRecording.sampleRate
      && format.channelCount == CanonicalRecording.channelCount && !format.isInterleaved
  }
}
