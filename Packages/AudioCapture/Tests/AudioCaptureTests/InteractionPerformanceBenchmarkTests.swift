import AVFAudio
import Foundation
import Testing

@testable import AudioCapture

@Suite struct InteractionPerformanceBenchmarkTests {
  @Test func oneHundredCaptureProcessorsStartWithinBudget() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let converter = try CanonicalAudioConverter(inputFormat: format)
    let inputBuffers = try AudioBufferPool(
      format: format,
      bufferCapacity: CaptureBufferConfiguration.frameCount(sampleRate: format.sampleRate))
    let clock = ContinuousClock()
    let startedAt = clock.now

    for _ in 0..<100 {
      let (_, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
      let processor = CaptureProcessor(
        converter: converter, continuation: continuation, inputBuffers: inputBuffers)
      processor.cancel()
    }

    let elapsed = startedAt.duration(to: clock.now)
    #expect(elapsed < .milliseconds(50))
  }
}
