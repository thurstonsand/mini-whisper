import AVFAudio

public struct CanonicalRecording: Equatable, Sendable {
  public static let sampleRate = 16_000.0
  public static let channelCount: AVAudioChannelCount = 1

  public let samples: [Float]

  public init(samples: [Float]) { self.samples = samples }

  public var duration: Duration { .seconds(durationSeconds) }

  public var durationSeconds: Double { Double(samples.count) / Self.sampleRate }
}

enum CanonicalAudioFormat {
  static func make() -> AVAudioFormat? {
    AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: CanonicalRecording.sampleRate,
      channels: CanonicalRecording.channelCount, interleaved: false)
  }

  static func containsCanonicalSamples(_ format: AVAudioFormat) -> Bool {
    format.commonFormat == .pcmFormatFloat32 && format.sampleRate == CanonicalRecording.sampleRate
      && format.channelCount == CanonicalRecording.channelCount && !format.isInterleaved
  }
}
