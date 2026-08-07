@testable import AudioCapture
import AVFAudio
import Foundation
import Testing

// MARK: - CanonicalAudioFormatTests

struct CanonicalAudioFormatTests {
  @Test func `canonical format is mono float 32 at 16 kilohertz`() throws {
    let format = try #require(CanonicalAudioFormat.make())

    #expect(CanonicalAudioFormat.containsCanonicalSamples(format))
    #expect(format.sampleRate == 16000)
    #expect(format.channelCount == 1)
    #expect(format.commonFormat == .pcmFormatFloat32)
    #expect(!format.isInterleaved)
  }
}

// MARK: - CanonicalAudioConverterTests

struct CanonicalAudioConverterTests {
  @Test func `canonical input remains complete`() throws {
    let input = try makeBuffer(sampleRate: 16000, channels: 1, frameCount: 1600) {
      channel, frame in Float(channel + frame) / 1600
    }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)

    let samples = try converter.convert(input) + converter.finish()

    #expect(samples.count == 1600)
    #expect(abs(samples[400] - 0.25) < 0.001)
    #expect(abs(samples[1200] - 0.75) < 0.001)
  }

  @Test func `stereo 48 kilohertz input is downmixed and resampled`() throws {
    let input = try makeBuffer(sampleRate: 48000, channels: 2, frameCount: 4800) { channel, _ in
      channel == 0 ? 0.25 : 0.75
    }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)

    let samples = try converter.convert(input) + converter.finish()
    let settledSamples = samples.dropFirst(100).dropLast(100)
    let average = settledSamples.reduce(Float.zero, +) / Float(settledSamples.count)

    #expect(abs(samples.count - 1600) <= 2)
    #expect(abs(average - 0.5) < 0.01)
  }

  @Test func `reset reuses the converter for A new recording`() throws {
    let input = try makeBuffer(sampleRate: 48000, channels: 1, frameCount: 4800) { _, _ in 0.25 }
    let converter = try CanonicalAudioConverter(inputFormat: input.format)
    let first = try converter.convert(input) + converter.finish()

    converter.reset()
    let second = try converter.convert(input) + converter.finish()

    #expect(second == first)
  }

  @Test func `conversion across buffers retains the complete stream`() throws {
    let inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
    var samples: [Float] = []

    for _ in 0 ..< 3 {
      let input = try makeBuffer(format: inputFormat, frameCount: 4800, sample: { _, _ in 0.25 })
      try samples.append(contentsOf: converter.convert(input))
    }
    try samples.append(contentsOf: converter.finish())

    #expect(abs(samples.count - 4800) <= 2)
  }

  @Test(arguments: [8000.0, 44100.0, 192_000.0])
  func `arbitrary chunking matches monolithic conversion`(sampleRate: Double) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    let frameCount = 2049
    let monolithicInput = try makeBuffer(
      format: format, frameCount: AVAudioFrameCount(frameCount),
      sample: { _, frame in sin(Float(frame) * 0.017) },
    )
    let monolithicConverter = try CanonicalAudioConverter(inputFormat: format)
    let expected = try monolithicConverter.convert(monolithicInput) + monolithicConverter.finish()
    let chunkedConverter = try CanonicalAudioConverter(inputFormat: format)
    let chunkSizes = [1, 7, 333, 1024]
    var actual: [Float] = []
    var offset = 0
    var chunkIndex = 0

    while offset < frameCount {
      let chunkSize = min(chunkSizes[chunkIndex % chunkSizes.count], frameCount - offset)
      let input = try makeBuffer(
        format: format, frameCount: AVAudioFrameCount(chunkSize),
        sample: { _, frame in sin(Float(offset + frame) * 0.017) },
      )
      try actual.append(contentsOf: chunkedConverter.convert(input))
      offset += chunkSize
      chunkIndex += 1
    }
    try actual.append(contentsOf: chunkedConverter.finish())

    #expect(actual == expected)
  }
}

// MARK: - CaptureBufferConfigurationTests

struct CaptureBufferConfigurationTests {
  @Test(arguments: [
    48000.0,
    96000.0,
    192_000.0,
  ]) func `uses one hundred milliseconds at the input rate`(
    sampleRate: Double,
  ) throws {
    #expect(
      try CaptureBufferConfiguration.frameCount(sampleRate: sampleRate)
        == AVAudioFrameCount(sampleRate / 10),
    )
  }
}

// MARK: - AudioBufferPoolTests

struct AudioBufferPoolTests {
  @Test func `copied buffer owns every input sample`() throws {
    let input = try makeBuffer(sampleRate: 48000, channels: 2, frameCount: 1024) {
      channel, frame in Float(channel * 2000 + frame)
    }
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: 1024)

    let copy = try #require(pool.copy(input))

    #expect(copy.buffer.frameLength == input.frameLength)
    #expect(copy.buffer.floatChannelData?[0][512] == 512)
    #expect(copy.buffer.floatChannelData?[1][512] == 2512)
    pool.checkIn(copy)
  }

  @Test func `exhausted pool fails instead of dropping input silently`() throws {
    let input = try makeBuffer(sampleRate: 48000, channels: 1, frameCount: 1024) { _, _ in 0 }
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: 1024)
    var checkedOut: [OwnedAudioBuffer] = []

    while let buffer = pool.copy(input) {
      checkedOut.append(buffer)
    }

    #expect(checkedOut.count == 8)
    #expect(pool.copy(input) == nil)
    for buffer in checkedOut {
      pool.checkIn(buffer)
    }
    #expect(pool.copy(input) != nil)
  }

  @Test func `copies A full hundred milliseconds at 192 kilohertz`() throws {
    let frameCount = try CaptureBufferConfiguration.frameCount(sampleRate: 192_000)
    let input = try makeBuffer(
      sampleRate: 192_000, channels: 1, frameCount: frameCount,
      sample: { _, frame in Float(frame) },
    )
    let pool = try AudioBufferPool(format: input.format, bufferCapacity: frameCount)

    let copy = try #require(pool.copy(input))

    #expect(copy.buffer.frameLength == 19200)
    #expect(copy.buffer.floatChannelData?[0][19199] == 19199)
  }
}

// MARK: - CaptureProcessorTests

struct CaptureProcessorTests {
  @Test func `interruption always prevents partial recording completion`() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let (_, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let processor = try CaptureProcessor(inputFormat: format, continuation: continuation)

    processor.fail(.engineConfigurationChanged)

    #expect(throws: AudioCaptureError.engineConfigurationChanged) { try processor.complete() }
  }
}

// MARK: - SampleAccumulatorTests

struct SampleAccumulatorTests {
  @Test func `recording contains every appended sample in order`() {
    var accumulator = SampleAccumulator()

    accumulator.append([0.1, 0.2])
    accumulator.append([])
    accumulator.append([0.3, 0.4, 0.5])

    #expect(accumulator.recording().samples == [0.1, 0.2, 0.3, 0.4, 0.5])
  }
}

// MARK: - CanonicalWAVWriterTests

struct CanonicalWAVWriterTests {
  @Test func `writes float 32 mono 16 kilohertz audio`() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MiniWhisper-test-\(UUID().uuidString).wav",
    )
    defer { try? FileManager.default.removeItem(at: url) }
    let recording = CanonicalRecording(samples: Array(repeating: 0.25, count: 1600))

    try CanonicalWAVWriter.write(recording, to: url)

    let file = try AVAudioFile(forReading: url)
    #expect(file.fileFormat.sampleRate == 16000)
    #expect(file.fileFormat.channelCount == 1)
    #expect(file.fileFormat.commonFormat == .pcmFormatFloat32)
    #expect(file.length == 1600)
  }

  @Test func `a written recording reads back sample for sample`() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MiniWhisper-test-\(UUID().uuidString).wav",
    )
    defer { try? FileManager.default.removeItem(at: url) }
    let recording = CanonicalRecording(
      samples: (0 ..< 1600).map { Float($0 % 100) / 100 - 0.5 },
    )

    try CanonicalWAVWriter.write(recording, to: url)

    #expect(try CanonicalWAVReader.read(contentsOf: url) == recording)
  }

  @Test func `audio that is not canonical is rejected rather than converted`() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MiniWhisper-test-\(UUID().uuidString).wav",
    )
    defer { try? FileManager.default.removeItem(at: url) }
    let format = try #require(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false,
      ),
    )
    let file = try AVAudioFile(
      forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
      interleaved: false,
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
    buffer.frameLength = 64
    try file.write(from: buffer)

    #expect(throws: AudioCaptureError.self) { try CanonicalWAVReader.read(contentsOf: url) }
  }
}

// MARK: - AudioInputLevelThrottleTests

struct AudioInputLevelThrottleTests {
  @Test func `meter publication is capped at thirty hertz`() {
    var throttle = AudioInputLevelThrottle()

    let first = throttle.shouldPublish(now: 1_000_000_000)
    let tooSoon = throttle.shouldPublish(now: 1_033_333_332)
    let next = throttle.shouldPublish(now: 1_033_333_333)

    #expect(first)
    #expect(!tooSoon)
    #expect(next)
  }
}

// MARK: - AudioLevelTests

struct AudioLevelTests {
  @Test func `the meter's running sum lands where the sample array would`() {
    let samples: [Float] = [0.1, -0.4, 1, 0.25]
    let sumSquares = samples.reduce(Float.zero) { $0 + $1 * $1 }

    let accumulated = AudioLevel(sumSquares: sumSquares, sampleCount: samples.count)

    #expect(accumulated == AudioLevel(samples: samples))
  }

  @Test func `silence and full scale have canonical bounds`() {
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
  sample: (Int, Int) -> Float,
) throws -> AVAudioPCMBuffer {
  let format = try #require(
    AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels),
  )
  return try makeBuffer(format: format, frameCount: frameCount, sample: sample)
}

private func makeBuffer(
  format: AVAudioFormat, frameCount: AVAudioFrameCount, sample: (Int, Int) -> Float,
) throws -> AVAudioPCMBuffer {
  let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
  let channelData = try #require(buffer.floatChannelData)
  buffer.frameLength = frameCount

  for channel in 0 ..< Int(format.channelCount) {
    for frame in 0 ..< Int(frameCount) {
      channelData[channel][frame] = sample(channel, frame)
    }
  }
  return buffer
}
