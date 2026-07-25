import AVFAudio
import Foundation
import Testing

@testable import AudioCapture

@Suite struct CanonicalAudioFormatTests {
  @Test func canonicalFormatIsMonoFloat32At16Kilohertz() throws {
    let format = try #require(CanonicalAudioFormat.make())

    #expect(CanonicalAudioFormat.containsCanonicalSamples(format))
    #expect(format.sampleRate == 16_000)
    #expect(format.channelCount == 1)
    #expect(format.commonFormat == .pcmFormatFloat32)
    #expect(!format.isInterleaved)
  }
}

@Suite struct CanonicalAudioConverterTests {
  @Test func canonicalInputRemainsComplete() throws {
    let input = try makeBuffer(sampleRate: 16_000, channels: 1, frameCount: 1_600) {
      channel, frame in Float(channel + frame) / 1_600
    }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)

    let samples = try converter.convert(input) + converter.finish()

    #expect(samples.count == 1_600)
    #expect(abs(samples[400] - 0.25) < 0.001)
    #expect(abs(samples[1_200] - 0.75) < 0.001)
  }

  @Test func stereo48KilohertzInputIsDownmixedAndResampled() throws {
    let input = try makeBuffer(sampleRate: 48_000, channels: 2, frameCount: 4_800) { channel, _ in
      channel == 0 ? 0.25 : 0.75
    }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)

    let samples = try converter.convert(input) + converter.finish()
    let settledSamples = samples.dropFirst(100).dropLast(100)
    let average = settledSamples.reduce(Float.zero, +) / Float(settledSamples.count)

    #expect(abs(samples.count - 1_600) <= 2)
    #expect(abs(average - 0.5) < 0.01)
  }

  @Test func resetReusesTheConverterForANewRecording() throws {
    let input = try makeBuffer(sampleRate: 48_000, channels: 1, frameCount: 4_800) { _, _ in 0.25 }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)
    let first = try converter.convert(input) + converter.finish()

    converter.reset()
    let second = try converter.convert(input) + converter.finish()

    #expect(second == first)
  }

  @Test func conversionAcrossBuffersRetainsTheCompleteStream() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
    var samples: [Float] = []

    for _ in 0..<3 {
      let input = try makeBuffer(format: inputFormat, frameCount: 4_800, sample: { _, _ in 0.25 })
      samples.append(contentsOf: try converter.convert(input))
    }
    samples.append(contentsOf: try converter.finish())

    #expect(abs(samples.count - 4_800) <= 2)
  }

  @Test(arguments: [8_000.0, 44_100.0, 192_000.0])
  func arbitraryChunkingMatchesMonolithicConversion(sampleRate: Double) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let frameCount = 2_049
    let monolithicInput = try makeBuffer(
      format: format, frameCount: AVAudioFrameCount(frameCount),
      sample: { _, frame in sin(Float(frame) * 0.017) })
    let monolithicConverter = try CanonicalAudioConverter(inputFormat: format)
    let expected = try monolithicConverter.convert(monolithicInput) + monolithicConverter.finish()
    let chunkedConverter = try CanonicalAudioConverter(inputFormat: format)
    let chunkSizes = [1, 7, 333, 1_024]
    var actual: [Float] = []
    var offset = 0
    var chunkIndex = 0

    while offset < frameCount {
      let chunkSize = min(chunkSizes[chunkIndex % chunkSizes.count], frameCount - offset)
      let input = try makeBuffer(
        format: format, frameCount: AVAudioFrameCount(chunkSize),
        sample: { _, frame in sin(Float(offset + frame) * 0.017) })
      actual.append(contentsOf: try chunkedConverter.convert(input))
      offset += chunkSize
      chunkIndex += 1
    }
    actual.append(contentsOf: try chunkedConverter.finish())

    #expect(actual == expected)
  }
}

@Suite struct CaptureBufferConfigurationTests {
  @Test(arguments: [48_000.0, 96_000.0, 192_000.0]) func usesOneHundredMillisecondsAtTheInputRate(
    sampleRate: Double
  ) throws {
    #expect(
      try CaptureBufferConfiguration.frameCount(sampleRate: sampleRate)
        == AVAudioFrameCount(sampleRate / 10))
  }
}

@Suite struct AudioBufferPoolTests {
  @Test func copiedBufferOwnsEveryInputSample() throws {
    let input = try makeBuffer(sampleRate: 48_000, channels: 2, frameCount: 1_024) {
      channel, frame in Float(channel * 2_000 + frame)
    }
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: 1_024)

    let copy = try #require(pool.copy(input))

    #expect(copy.buffer.frameLength == input.frameLength)
    #expect(copy.buffer.floatChannelData?[0][512] == 512)
    #expect(copy.buffer.floatChannelData?[1][512] == 2_512)
    pool.checkIn(copy)
  }

  @Test func exhaustedPoolFailsInsteadOfDroppingInputSilently() throws {
    let input = try makeBuffer(sampleRate: 48_000, channels: 1, frameCount: 1_024) { _, _ in 0 }
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: 1_024)
    var checkedOut: [OwnedAudioBuffer] = []

    while let buffer = pool.copy(input) { checkedOut.append(buffer) }

    #expect(checkedOut.count == 8)
    #expect(pool.copy(input) == nil)
    for buffer in checkedOut { pool.checkIn(buffer) }
    #expect(pool.copy(input) != nil)
  }

  @Test func copiesAFullHundredMillisecondsAt192Kilohertz() throws {
    let frameCount = try CaptureBufferConfiguration.frameCount(sampleRate: 192_000)
    let input = try makeBuffer(
      sampleRate: 192_000, channels: 1, frameCount: frameCount, sample: { _, frame in Float(frame) }
    )
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: frameCount)

    let copy = try #require(pool.copy(input))

    #expect(copy.buffer.frameLength == 19_200)
    #expect(copy.buffer.floatChannelData?[0][19_199] == 19_199)
  }
}

@Suite struct CaptureProcessorTests {
  @Test func interruptionAlwaysPreventsPartialRecordingCompletion() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let (_, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let processor = try CaptureProcessor(inputFormat: format, continuation: continuation)

    processor.fail(.engineConfigurationChanged)

    #expect(throws: AudioCaptureError.engineConfigurationChanged) { try processor.complete() }
  }
}

@Suite struct SampleAccumulatorTests {
  @Test func recordingContainsEveryAppendedSampleInOrder() {
    var accumulator = SampleAccumulator()

    accumulator.append([0.1, 0.2])
    accumulator.append([])
    accumulator.append([0.3, 0.4, 0.5])

    #expect(accumulator.recording().samples == [0.1, 0.2, 0.3, 0.4, 0.5])
  }
}

@Suite struct CanonicalWAVWriterTests {
  @Test func writesFloat32Mono16KilohertzAudio() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MiniWhisper-test-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let recording = CanonicalRecording(samples: Array(repeating: 0.25, count: 1_600))

    try CanonicalWAVWriter.write(recording, to: url)

    let file = try AVAudioFile(forReading: url)
    #expect(file.fileFormat.sampleRate == 16_000)
    #expect(file.fileFormat.channelCount == 1)
    #expect(file.fileFormat.commonFormat == .pcmFormatFloat32)
    #expect(file.length == 1_600)
  }
}

@Suite struct AudioLevelTests {
  @Test func silenceAndFullScaleHaveCanonicalBounds() {
    let silence = AudioLevel(samples: [0, 0, 0])
    let fullScale = AudioLevel(samples: [1, 1, 1])

    #expect(silence.decibels == -60)
    #expect(silence.normalizedPower == 0)
    #expect(fullScale.decibels == 0)
    #expect(fullScale.normalizedPower == 1)
  }
}

private func makeBuffer(
  sampleRate: Double, channels: AVAudioChannelCount, frameCount: AVAudioFrameCount,
  sample: (Int, Int) -> Float
) throws -> AVAudioPCMBuffer {
  let format = try #require(
    AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
  return try makeBuffer(format: format, frameCount: frameCount, sample: sample)
}

private func makeBuffer(
  format: AVAudioFormat, frameCount: AVAudioFrameCount, sample: (Int, Int) -> Float
) throws -> AVAudioPCMBuffer {
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
  let channelData = try #require(buffer.floatChannelData)
  buffer.frameLength = frameCount

  for channel in 0..<Int(format.channelCount) {
    for frame in 0..<Int(frameCount) { channelData[channel][frame] = sample(channel, frame) }
  }
  return buffer
}
